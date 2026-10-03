#!/usr/bin/env python3
"""Nightly Tandem Source watch (research per openspec tandem-api-change-resilience).

Checks three free, no-auth/light-auth signals and alerts on ANY change that
could mean Tandem moved their (undocumented, reverse-engineered) BFF contract:

1. jwoglom/tconnectsync latest release tag — the OSS standard client ships
   a fix release within hours of a break (verified: Oct 1 2026 break = same
   day v3.0.2/v3.0.3).
2. jwoglom/tconnectsync issues matching breakage keywords (zod/eventCodes/
   pump-logs/HTTP 4xx...).
3. Tandem public deploy fingerprint: source.tandemdiabetes.com main.<hash>.js
   bundle + /mf-manifest.json buildVersion + sso.tandemdiabetes.com bundle
   hash. A hash/version bump = "Tandem shipped something"; the contract
   strings themselves are not in public assets (verified 2026-10-03).

State (last seen) is committed so each run compares against the previous one.
First run only establishes the baseline — no alert. Detection is GitHub-issue
based (no external secrets); Postmark email is a possible add-on.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone, timedelta

TANDEM_HOST = "https://source.tandemdiabetes.com"
SSO_HOST = "https://sso.tandemdiabetes.com"
TC = "jwoglom/tconnectsync"
STATE_DEFAULT = "scripts/tandem-watch-state.json"
CHANGES_DEFAULT = "watch-changes.md"
UA_TANDEM = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
UA_GH = "tandem-watch (GlucoseBar)"
ISSUE_KEYWORDS = [
    "eventcod", "eventid", "pump-log", "pump_log", "http 400", "http 404",
    "zoderror", "zod error", "unrecognized", "tandemsourceapi", "api change",
    "api break", "breaking", "required update",
]


def http_text(url, headers=None):
    req = urllib.request.Request(url, headers={"User-Agent": UA_TANDEM, **(headers or {})})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def http_json(url, token=None):
    headers = {"User-Agent": UA_GH, "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def fetch_tconnectsync(token):
    rel = http_json(f"https://api.github.com/repos/{TC}/releases/latest", token)
    release = {"tag": rel.get("tag_name"), "name": rel.get("name"),
               "published_at": rel.get("published_at"), "url": rel.get("html_url")}

    since = datetime.now(timezone.utc) - timedelta(hours=48)
    since_iso = since.strftime("%Y-%m-%dT%H:%M:%SZ")
    issues = []
    try:
        data = http_json(f"https://api.github.com/repos/{TC}/issues?state=all&since={since_iso}&per_page=30", token)
    except urllib.error.HTTPError:
        data = []
    for it in data:
        if it.get("pull_request"):
            continue
        hay = f"{it.get('title') or ''} {it.get('body') or ''}".lower()
        if any(k in hay for k in ISSUE_KEYWORDS):
            issues.append({"id": it["id"], "number": it["number"], "title": it.get("title"),
                           "url": it.get("html_url"), "created_at": it.get("created_at")})
    return release, issues


def fetch_tandem_fingerprint():
    portal_html = http_text(TANDEM_HOST)
    m = re.search(r'main\.([a-f0-9]{8})\.js', portal_html)
    portal_hash = m.group(1) if m else None

    try:
        mf = json.loads(http_text(f"{TANDEM_HOST}/mf-manifest.json", {"Accept": "application/json"}))
        build_version = mf.get("metaData", {}).get("buildInfo", {}).get("buildVersion")
    except Exception:
        build_version = None

    sso_hash = None
    try:
        sso_html = http_text(SSO_HOST)
        m = re.search(r'/static/main\.([a-f0-9]{8})\.js', sso_html)
        sso_hash = m.group(1) if m else None
    except Exception:
        pass
    return {"portal_hash": portal_hash, "build_version": build_version, "sso_hash": sso_hash}


def main():
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    state_path = os.environ.get("TANDEM_WATCH_STATE", STATE_DEFAULT)
    changes_path = os.environ.get("TANDEM_WATCH_CHANGES_FILE", CHANGES_DEFAULT)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        with open(state_path) as f:
            prev = json.load(f)
    except (OSError, json.JSONDecodeError):
        prev = {}
    first_run = not prev

    release, issues = fetch_tconnectsync(token)
    fp = fetch_tandem_fingerprint()

    changes = []

    prev_rel = (prev.get("tconnectsync") or {}).get("tag") if prev else None
    if prev and prev_rel:
        if release["tag"] != prev_rel:
            changes.append(f"tconnectsync release: {release['tag']} ('{release['name']}') published {release['published_at']} — {release['url']}")
    else:
        print(f"baseline: tconnectsync latest release = {release['tag']}")

    prev_issues = set(prev.get("issues_seen", [])) if prev else set()
    new_matches = [i for i in issues if i["id"] not in prev_issues]
    if not first_run:
        for i in new_matches:
            changes.append(f"tconnectsync issue #{i['number']}: {i['title']} (created {i['created_at']}) — {i['url']}")

    prev_fp = prev.get("tandem") or {}
    if prev and prev_fp:
        for k, label in (("portal_hash", "portal bundle main.<hash>.js"), ("build_version", "buildVersion"),
                         ("sso_hash", "sso bundle hash")):
            if prev_fp.get(k) != fp.get(k) and fp.get(k):
                changes.append(f"Tandem fingerprint {label}: {prev_fp.get(k)} -> {fp.get(k)}")
    else:
        print(f"baseline: Tandem fingerprint = {fp}")

    changed = bool(changes)

    with open(state_path, "w") as f:
        json.dump({
            "last_run": now,
            "tconnectsync": {"tag": release["tag"], "published_at": release["published_at"]},
            "issues_seen": sorted(prev_issues | {i["id"] for i in issues}),
            "tandem": fp,
        }, f, indent=2)

    summary = f"tconnectsync {release['tag']}; issues since last run: {len(new_matches)} matching; portal {fp['portal_hash']} build {fp['build_version']}; sso {fp['sso_hash']}"
    print(summary)
    if os.path.exists(changes_path) and not changed:
        os.remove(changes_path)
    if changed:
        subject = "⚠️ Tandem Source watch: " + "; ".join(c.split(':')[0] for c in changes)
        body = ["## Tandem Source watch alert",
                "",
                f"`{summary}`",
                "",
                "Changes detected since last run:",
                ""]
        body += [f"- {c}" for c in changes]
        body += ["",
                 "Action: review whether GlucoseBar's Tandem integration is affected "
                 "(see openspec t1dtools/plans/tandem-api-change-resilience). "
                 "Tandem's BFF is undocumented and breaks without notice (verified 2026-10-01)."]
        with open(changes_path, "w") as f:
            f.write(subject + "\n\n" + "\n".join(body))
        for c in changes:
            print("CHANGE:", c)

    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as f:
            f.write(f"changed={'true' if changed else 'false'}\n")
            f.write(f"summary={summary}\n".replace('\n', ' '))
    return 0


if __name__ == "__main__":
    sys.exit(main())