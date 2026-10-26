//
//  VCRProxy.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2026-08-30.
//

import Foundation
import OSLog

/// Resolves provider base URLs to a VCR proxy (the `glucosebar-vcr` emulator)
/// when one is configured, so the app can record against real providers or
/// replay recorded fixtures without touching production systems.
///
/// Two triggers, per the handover doc (glucosebar-vcr/docs/glucosebar-fixture-capture.md):
///  1. **Debug field** — a single "VCR proxy address" persisted in
///     `UserDefaults` (global key `vcrProxyAddress`), active only while debug
///     mode is on. Empty by default, so release builds are unaffected.
///  2. **App Review account** — when the configured account email for a
///     provider is exactly `review@t1d.tools`, that provider routes to the
///     hosted replay-only instance (`https://vcr.t1d.tools`) with no debug
///     mode and no extra fields.
///
/// Precedence: debug field > review account > production URLs.
enum VCRProxy {
    /// Hosted replay-only instance used by Apple App Review. Plain HTTP inside
    /// Docker; Caddy terminates TLS, so the app-facing base is `https://`.
    static let reviewBaseURL = "https://vcr.t1d.tools"

    /// The trimmed debug-field base with a trailing slash, or nil when debug mode
    /// is off, the field is empty, or the address is unusable.
    private static var debugBase: String? {
        guard UserDefaults.standard.bool(forKey: "debugMode") else { return nil }
        let trimmed = (UserDefaults.standard.string(forKey: "vcrProxyAddress") ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Validated here rather than at each call site: the field is saved on every
        // keystroke in the debug screen, and a mistyped address used to reach
        // force-unwrapped URL construction in the providers and crash the app on
        // launch. Normalising through the http(s) form means a `wss://` typo still
        // yields requestable URLs, and an unusable address is ignored — with a log
        // line, so it is not a silent no-op.
        guard let url = ProviderURL.httpURL(from: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            Logger(subsystem: "tools.t1d.GlucoseBar", category: "vcr-proxy")
                .dlog("Ignoring unusable VCR proxy address", category: "vcr-proxy", level: .error)
            return nil
        }

        let normalized = url.absoluteString
        return normalized.hasSuffix("/") ? normalized : normalized + "/"
    }

    /// True only for the exact App Review account (case-insensitive, trimmed).
    static func isReviewAccount(_ email: String) -> Bool {
        email.trimmingCharacters(in: .whitespaces).lowercased() == "review@t1d.tools"
    }

    /// Effective base for a provider suffix: debug field first, then the
    /// review host when `account` matches. `account` is the provider's
    /// configured email (Nightscout has none and is only ever debug-routed).
    private static func resolve(account: String?, suffix: String) -> String? {
        if let base = debugBase { return base + suffix }
        if let email = account, isReviewAccount(email) {
            return reviewBaseURL + "/" + suffix
        }
        return nil
    }

    // MARK: - Per-provider bases (match the emulator's route prefixes)

    /// `GET /nightscout/...` — Nightscout's URL is a user setting, so only the
    /// debug field routes it (the review account enters the VCR host directly).
    static func nightscout() -> String? {
        resolve(account: nil, suffix: "nightscout")
    }

    /// `DexcomServer.url` value — `/dexcom/ShareWebServices/Services`.
    static func dexcom(account: String?) -> String? {
        resolve(account: account, suffix: "dexcom/ShareWebServices/Services")
    }

    /// Tandem login page + API source base — `/tandem`.
    static func tandem(account: String?) -> String? {
        resolve(account: account, suffix: "tandem")
    }

    /// Tandem OIDC endpoints — `/tandem/accounts/api/...`.
    static func tandemLoginAPI(account: String?) -> String? { resolve(account: account, suffix: "tandem/accounts/api/login") }
    static func tandemAuthorize(account: String?) -> String? { resolve(account: account, suffix: "tandem/accounts/api/connect/authorize") }
    static func tandemToken(account: String?) -> String? { resolve(account: account, suffix: "tandem/accounts/api/connect/token") }
}