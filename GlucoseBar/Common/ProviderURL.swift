//
//  ProviderURL.swift
//  GlucoseBar
//

import Foundation

/// Validation for provider addresses that the user types in by hand (currently
/// the Nightscout server URL).
///
/// These strings used to be handed straight to `URL(string:)!`, which traps on
/// anything the parser rejects. A single stray space in a pasted URL
/// (`https://my nightscout.com`) was enough to kill the app when the settings
/// were saved and then again on every launch, because the socket manager is
/// built from the same string. Everything user-supplied now goes through here
/// first, and a rejection is reported to the user instead of crashing.
enum ProviderURL {

    /// Why a user-entered address was rejected.
    enum Invalid: Error, Equatable {
        /// Nothing (or only whitespace) was entered.
        case empty
        /// The address has no scheme, or one we cannot talk to.
        case unsupportedScheme
        /// The address has a usable scheme but is not parseable as a URL.
        case malformed

        /// Message to show the user. Deliberately actionable: the user has to
        /// go and fix the field themselves.
        var message: String {
            switch self {
            case .empty:
                return String(localized: "The server URL can not be empty.", comment: "Validation message for an empty provider server URL field")
            case .unsupportedScheme:
                return String(localized: "The server URL must start with http:// or https://", comment: "Validation message for a provider server URL that is missing a supported scheme")
            case .malformed:
                return String(localized: "The server URL is not a valid address. Check it for typos and try again.", comment: "Validation message for a provider server URL that can not be parsed")
            }
        }
    }

    /// Schemes we accept. `ws`/`wss` are legitimate here because the socket is
    /// built from the same address and `SocketManager` handles the websocket
    /// scheme itself — a `wss://` address used to connect and serve live readings
    /// while its HTTP paths failed. The HTTP requests use the corresponding
    /// http(s) form via `httpEquivalent(of:)`, so both work.
    private static let supportedSchemes: Set<String> = ["http", "https", "ws", "wss"]

    /// Characters that are invisible in a text field but make the URL parser
    /// fail. They arrive routinely when an address is copied out of a web page
    /// or a terminal session.
    private static let invisibleCharacters: Set<Character> = [
        "\u{200B}", // zero width space
        "\u{200C}", // zero width non-joiner
        "\u{200D}", // zero width joiner
        "\u{FEFF}", // zero width no-break space / BOM
    ]

    /// Strips whitespace and invisible characters from a user-entered address.
    /// Callers should persist the cleaned value so that what was validated is
    /// what gets used later.
    static func cleaned(_ raw: String) -> String {
        raw.filter { !invisibleCharacters.contains($0) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates a user-entered provider address and returns the normalised
    /// `URL` on success.
    ///
    /// On failure the caller must not use the address for anything: show
    /// `Invalid.message` and leave the setting alone.
    static func validate(_ raw: String) -> Result<URL, Invalid> {
        let candidate = cleaned(raw)

        guard !candidate.isEmpty else { return .failure(.empty) }

        // Interior whitespace means this is not a URL at all. It is a typo, and
        // silently percent-encoding it would hide the mistake from the user.
        guard !candidate.contains(where: { $0.isWhitespace }) else { return .failure(.malformed) }

        guard let components = URLComponents(string: candidate) else { return .failure(.malformed) }

        guard let scheme = components.scheme?.lowercased(), supportedSchemes.contains(scheme) else {
            return .failure(.unsupportedScheme)
        }

        // `https:///api` and friends parse but have no host, so they would fail
        // only much later at request time.
        guard let host = components.host, !host.isEmpty, let url = components.url else {
            return .failure(.malformed)
        }

        return .success(url)
    }

    /// The HTTP(S) form of an already-validated address: `ws://` → `http://`,
    /// `wss://` → `https://`, anything else unchanged.
    ///
    /// The socket keeps the scheme the user typed, but the entries, treatments and
    /// authorization calls are plain HTTP, so they need this form. It is what makes
    /// a `ws://` address work for those paths rather than failing at request time.
    static func httpEquivalent(of url: URL) -> URL {
        let replacement: String
        switch url.scheme?.lowercased() {
        case "ws": replacement = "http"
        case "wss": replacement = "https"
        default: return url
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = replacement
        return components?.url ?? url
    }

    /// Validates a user-entered address and returns its HTTP(S) form, for callers
    /// that need a plain HTTP URL — the liveness probe, and links opened in a
    /// browser. Returns nil when the address is not usable.
    static func httpURL(from raw: String) -> URL? {
        guard case .success(let url) = validate(raw) else { return nil }
        return httpEquivalent(of: url)
    }
}
