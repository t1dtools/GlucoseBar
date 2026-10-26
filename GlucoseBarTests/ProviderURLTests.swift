//
//  ProviderURLTests.swift
//  GlucoseBarTests
//

import XCTest
@testable import GlucoseBar

/// Covers `ProviderURL`, which exists because these addresses used to be handed
/// straight to `URL(string:)!`. A single stray space in a pasted Nightscout URL
/// was enough to crash the app when saving settings and on every launch after
/// that, since the socket manager is built from the same string.
final class ProviderURLTests: XCTestCase {

    // MARK: - Accepted

    func testAcceptsPlainHTTPSURL() throws {
        let url = try XCTUnwrap(try? ProviderURL.validate("https://nightscout.example.com").get())
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "nightscout.example.com")
    }

    func testTrimsSurroundingWhitespaceAndNewlines() throws {
        let url = try XCTUnwrap(try? ProviderURL.validate("  https://nightscout.example.com\n").get())
        XCTAssertEqual(url.host, "nightscout.example.com")
    }

    func testStripsZeroWidthCharactersPastedFromWebPages() throws {
        let url = try XCTUnwrap(try? ProviderURL.validate("https://nightscout\u{200B}.example.com").get())
        XCTAssertEqual(url.host, "nightscout.example.com")
    }

    func testAcceptsPortAndPath() throws {
        let url = try XCTUnwrap(try? ProviderURL.validate("http://nightscout.example.com:1337/ns").get())
        XCTAssertEqual(url.host, "nightscout.example.com")
        XCTAssertEqual(url.port, 1337)
        XCTAssertEqual(url.path, "/ns")
    }

    // MARK: - Rejected

    /// Returns the rejection reason for an address, or nil when it was accepted.
    private func rejection(of raw: String) -> ProviderURL.Invalid? {
        guard case .failure(let invalid) = ProviderURL.validate(raw) else { return nil }
        return invalid
    }

    func testRejectsEmptyInput() {
        XCTAssertEqual(rejection(of: ""), .empty)
        XCTAssertEqual(rejection(of: "   "), .empty)
    }

    func testRejectsAddressWithoutAScheme() {
        XCTAssertEqual(rejection(of: "nightscout.example.com"), .unsupportedScheme)
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertEqual(rejection(of: "ftp://nightscout.example.com"), .unsupportedScheme)
    }

    /// A `ws://`/`wss://` address is a legitimate socket target and used to serve
    /// live readings, so rejecting it would break a working setup. The HTTP paths
    /// derive the matching http(s) scheme instead.
    func testAcceptsWebSocketSchemes() throws {
        let secure = try XCTUnwrap(try? ProviderURL.validate("wss://nightscout.example.com").get())
        XCTAssertEqual(secure.scheme, "wss")

        let plain = try XCTUnwrap(try? ProviderURL.validate("ws://nightscout.example.com").get())
        XCTAssertEqual(plain.scheme, "ws")
    }

    func testDerivesHTTPSchemeForWebSocketAddresses() throws {
        let secure = try XCTUnwrap(ProviderURL.httpURL(from: "wss://nightscout.example.com:1337/ns"))
        XCTAssertEqual(secure.scheme, "https")
        XCTAssertEqual(secure.host, "nightscout.example.com")
        XCTAssertEqual(secure.port, 1337)
        XCTAssertEqual(secure.path, "/ns")

        XCTAssertEqual(try XCTUnwrap(ProviderURL.httpURL(from: "ws://nightscout.example.com")).scheme, "http")
        // Already-HTTP addresses come back untouched.
        XCTAssertEqual(try XCTUnwrap(ProviderURL.httpURL(from: "https://nightscout.example.com")).scheme, "https")

        // Unusable addresses return nil rather than a partial URL.
        XCTAssertNil(ProviderURL.httpURL(from: "https://my nightscout.com"))
        XCTAssertNil(ProviderURL.httpURL(from: "https:///api"))
        XCTAssertNil(ProviderURL.httpURL(from: ""))
    }

    func testRejectsURLWithoutAHost() {
        XCTAssertEqual(rejection(of: "https:///api/v3/entries"), .malformed)
    }

    /// The regression test for the crash this type was written to prevent: every
    /// address here makes `URL(string:)` return nil, which the old code
    /// force-unwrapped.
    func testRejectsAddressesThatURLStringCannotParse() {
        let addresses = [
            "https://my nightscout.com",
            "https://a[b.com/api",
            "https://nightscout .example.com:1337",
        ]

        for address in addresses {
            XCTAssertNil(URL(string: address), "expected URL(string:) to reject \"\(address)\"")
            XCTAssertNotNil(rejection(of: address), "expected validation to reject \"\(address)\"")
        }
    }

    func testEveryRejectionHasAMessageForTheUser() {
        for invalid in [ProviderURL.Invalid.empty, .unsupportedScheme, .malformed] {
            XCTAssertFalse(invalid.message.isEmpty)
        }
    }
}
