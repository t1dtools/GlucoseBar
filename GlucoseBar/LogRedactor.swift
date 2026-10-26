//
//  LogRedactor.swift
//  GlucoseBar
//

import Foundation

/// Scrubs credentials and personal data out of log messages.
///
/// The debug log is written to a file that users are asked to attach to public
/// GitHub issues, so in practice anything it contains is published. Log messages
/// are free-form strings assembled at the call site, which makes it very easy to
/// interpolate a response body, a URL that carries an authorization code, or a
/// decoded dictionary of event properties without noticing — so redaction happens
/// centrally (in `Logger.dlog`, and again in `DebugLogger`, which owns the file)
/// instead of relying on every call site to remember.
///
/// Two tiers, deliberately:
///
///  * **Call sites must not log payload contents.** `payloadShape(of:)` exists to
///    replace them with structural information — key names and array counts — which
///    is what actually diagnoses a vendor API change, with none of the data.
///  * **This scrubber is the safety net** for anything that slips through: values
///    whose key looks like a credential, `Bearer` tokens, JWTs, and sensitive query
///    parameters or path components.
///
/// Measurement *values* (glucose, basal rates, carbs, boluses) cannot be
/// recognised by pattern, so nothing here can catch them — they are kept out of
/// the log only by the first tier.
enum LogRedactor {

    static let placeholder = "[redacted]"

    /// Longest message that will be written. Bounds the damage from anything
    /// large being interpolated in the future.
    static let maxLength = 2000

    /// Keys (compared after normalising: lowercased, `_` and `-` removed) whose
    /// values must never reach the log.
    ///
    /// Matching is exact on the normalised key, so `"eventCode"` and `"modelName"`
    /// — useful and not secret — are untouched, while `"access_token"`,
    /// `"accessToken"` and `"access-token"` all match. Note that a bare `"code"`
    /// is deliberately *not* here: in these payloads it means a pump event code.
    private static let sensitiveJSONKeys: Set<String> = [
        "token", "accesstoken", "refreshtoken", "idtoken", "sessiontoken", "bearertoken",
        "password", "passwd", "pwd", "passcode",
        "secret", "clientsecret", "apisecret", "apikey", "authorization",
        "cookie", "setcookie", "sessionid",
        "accountname", "accountid", "pumperid", "patientid", "userid",
        "email", "username", "user", "phone", "phonenumber",
        "firstname", "lastname", "fullname", "name",
        "ssn", "mrn", "dob", "dateofbirth",
    ]

    /// In a *query string* a bare `code` is the OAuth authorization code, which
    /// is exchangeable for tokens. Hence the extra keys — the JSON set cannot
    /// include `code` without destroying the pump event codes.
    private static let sensitiveQueryKeys: Set<String> =
        sensitiveJSONKeys.union(["code", "authcode", "authorizationcode"])

    // MARK: - Message scrubbing

    /// Returns `message` with credential-looking values replaced by
    /// `placeholder`. Idempotent: applying it twice changes nothing.
    static func redact(_ message: String) -> String {
        var result = message

        // Order matters: the quoted-value rule runs before the bare-value rule so
        // that a string value containing spaces is consumed whole rather than
        // partially rewritten.
        result = redactPairs(in: result, using: jsonStringPair, keyGroup: 1, valueGroup: 2, keys: sensitiveJSONKeys)
        result = redactPairs(in: result, using: jsonBarePair, keyGroup: 1, valueGroup: 2, keys: sensitiveJSONKeys)
        result = redactPairs(in: result, using: queryPair, keyGroup: 1, valueGroup: 2, keys: sensitiveQueryKeys)
        result = replaceAll(matching: bearerToken, in: result, with: "Bearer \(placeholder)")
        result = replaceAll(matching: jwt, in: result, with: "\(placeholder)-jwt")
        result = replaceAll(matching: authorizationPath, in: result, with: "/authorization/request/\(placeholder)")

        if result.count > maxLength {
            let dropped = result.count - maxLength
            result = String(result.prefix(maxLength)) + "… [truncated \(dropped) chars]"
        }

        return result
    }

    /// A URL with credential-bearing parts removed: userinfo and fragment are
    /// dropped outright, sensitive query values are redacted, and the Nightscout
    /// authorization path segment is masked. Everything else (host, path, other
    /// query items) is kept, since that is what makes the log useful.
    static func safeURL(_ url: URL?) -> String {
        guard let url else { return "nil" }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        components?.fragment = nil

        return redact(components?.string ?? url.absoluteString)
    }

    // MARK: - Payload summaries

    /// Describes the *shape* of a JSON response without any of its values, for
    /// logging in place of a raw body: the byte count, the top-level key names,
    /// and the length of any arrays.
    ///
    /// For example a pump-logs response becomes
    /// `"1264 bytes, keys: clockChanges=0, events=1188"`, which is enough to spot
    /// a renamed or missing field while carrying no measurements.
    static func payloadShape(of data: Data?) -> String {
        guard let data, !data.isEmpty else { return "empty body" }

        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return "\(data.count) bytes, not JSON"
        }

        if let dictionary = object as? [String: Any] {
            return "\(data.count) bytes, keys: \(describe(dictionary))"
        }

        if let array = object as? [Any] {
            let elementKeys = array.compactMap { ($0 as? [String: Any])?.keys }
                .first
                .map { Array($0).sorted().prefix(12).joined(separator: ", ") }
            let suffix = elementKeys.map { ", element keys: \($0)" } ?? ""
            return "\(data.count) bytes, array of \(array.count)\(suffix)"
        }

        return "\(data.count) bytes, scalar"
    }

    private static func describe(_ dictionary: [String: Any]) -> String {
        guard !dictionary.isEmpty else { return "<none>" }

        let parts = dictionary.keys.sorted().prefix(12).map { key -> String in
            if let array = dictionary[key] as? [Any] {
                return "\(key)=\(array.count)"
            }
            if let nested = dictionary[key] as? [String: Any] {
                let inner = nested.keys.sorted().prefix(6).joined(separator: ",")
                return "\(key)={\(inner)}"
            }
            return key
        }

        let overflow = dictionary.count > 12 ? ", …" : ""
        return parts.joined(separator: ", ") + overflow
    }

    // MARK: - Internals

    private static func isSensitive(_ key: String, in keys: Set<String>) -> Bool {
        keys.contains(normalise(key))
    }

    private static func normalise(_ key: String) -> String {
        key.lowercased().filter { $0 != "_" && $0 != "-" }
    }

    private static func redactPairs(
        in message: String,
        using regex: NSRegularExpression,
        keyGroup: Int,
        valueGroup: Int,
        keys: Set<String>
    ) -> String {
        let source = message as NSString
        let matches = regex.matches(in: message, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return message }

        var result = ""
        var cursor = 0
        var replaced = false

        for match in matches {
            let key = source.substring(with: match.range(at: keyGroup))
            guard isSensitive(key, in: keys) else { continue }

            let valueRange = match.range(at: valueGroup)
            guard valueRange.location != NSNotFound else { continue }

            result += source.substring(with: NSRange(location: cursor, length: valueRange.location - cursor))
            result += placeholder
            cursor = valueRange.location + valueRange.length
            replaced = true
        }

        guard replaced else { return message }
        result += source.substring(from: cursor)
        return result
    }

    private static func replaceAll(matching regex: NSRegularExpression, in message: String, with replacement: String) -> String {
        let range = NSRange(location: 0, length: (message as NSString).length)
        return regex.stringByReplacingMatches(in: message, range: range, withTemplate: replacement)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            // A malformed pattern must fail loudly during development rather than
            // silently stop redacting. Every pattern is covered by LogRedactorTests.
            preconditionFailure("LogRedactor: invalid pattern \(pattern): \(error)")
        }
    }

    // `"key": "value"` — the value is captured as a whole, escaped characters included.
    private static let jsonStringPair = regex(#""([A-Za-z0-9_.\-]+)"\s*:\s*"((?:[^"\\]|\\.)*)""#)
    // `"key": 1234` / `"key": null` — runs after the quoted form, so a string value
    // with spaces has already been consumed.
    private static let jsonBarePair = regex(#""([A-Za-z0-9_.\-]+)"\s*:\s*([^\s,}\]"']+)"#)
    // `key=value` in a query string or URL parameter list.
    private static let queryPair = regex(#"\b([A-Za-z0-9_.\-]+)=([^&\s"']+)"#)
    private static let bearerToken = regex(#"(?i)bearer\s+[A-Za-z0-9._~+/\-]+=*"#)
    // JWTs are three base64url segments starting with the encoding of `{"`.
    private static let jwt = regex(#"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}(?:\.[A-Za-z0-9_\-]+)?"#)
    // The Nightscout access token is a path segment, not a query item.
    private static let authorizationPath = regex(#"/authorization/request/[^\s"',}\]]+"#)
}
