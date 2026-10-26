//
//  LogRedactorTests.swift
//  GlucoseBarTests
//

import XCTest
@testable import GlucoseBar

/// Covers `LogRedactor`, whose job is to keep credentials and personal data out
/// of the debug log — a file users are asked to attach to public GitHub issues.
///
/// The fixtures below are the real shapes of the payloads that were being written
/// to the log before this existed.
final class LogRedactorTests: XCTestCase {

    // MARK: - Credentials

    func testRedactsNightscoutTokenResponse() {
        let message = #"status code under 300: 200. Body: {"token":"a1b2c3d4e5f6a7b8c9d0","exp":1750000000}"#

        let redacted = LogRedactor.redact(message)

        XCTAssertFalse(redacted.contains("a1b2c3d4e5f6a7b8c9d0"))
        XCTAssertTrue(redacted.contains("[redacted]"))
        // Non-secret context is preserved so the log is still worth reading.
        XCTAssertTrue(redacted.contains("exp"))
        XCTAssertTrue(redacted.contains("200"))
    }

    func testRedactsOidcTokenResponse() {
        let message = #"TandemLogin: OIDC token returned HTTP 400, body: {"access_token":"eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop","id_token":"eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop","refresh_token":"b8f2c1d4e6a7","expires_in":3600}"#

        let redacted = LogRedactor.redact(message)

        for secret in [
            "eyJhbGciOiJSUzI1NiJ9",
            "abcdefghijklmnop",
            "b8f2c1d4e6a7",
        ] {
            XCTAssertFalse(redacted.contains(secret), "leaked \(secret)")
        }
        // Key names survive, which is what diagnoses a contract change.
        XCTAssertTrue(redacted.contains("refresh_token"))
        XCTAssertTrue(redacted.contains("3600"))
    }

    func testRedactsSnakeCaseCamelCaseAndKebabCaseKeys() {
        let message = #"{"access_token":"aaa","accessToken":"bbb","Access-Token":"ccc","api_key":"ddd","clientSecret":"eee"}"#

        let redacted = LogRedactor.redact(message)

        for secret in ["aaa", "bbb", "ccc", "ddd", "eee"] {
            XCTAssertFalse(redacted.contains("\"\(secret)\""), "leaked \(secret)")
        }
    }

    func testRedactsNonStringValuesForSensitiveKeys() {
        let message = #"{"sessionId":1234567,"userId":98765,"password":null}"#

        let redacted = LogRedactor.redact(message)

        XCTAssertFalse(redacted.contains("1234567"))
        XCTAssertFalse(redacted.contains("98765"))
    }

    func testRedactsStringValuesContainingSpaces() {
        let message = #"{"name":"Ada Lovelace","email":"ada@example.com"}"#

        let redacted = LogRedactor.redact(message)

        XCTAssertFalse(redacted.contains("Ada Lovelace"))
        XCTAssertFalse(redacted.contains("ada@example.com"))
        // The whole value was consumed, not partially rewritten.
        XCTAssertFalse(redacted.contains("Lovelace"))
    }

    func testRedactsBearerTokens() {
        let message = "GET /api/v3/entries with Authorization: Bearer a1b2c3d4-e5f6-7890-abcd-ef1234567890"

        let redacted = LogRedactor.redact(message)

        XCTAssertFalse(redacted.contains("a1b2c3d4-e5f6-7890-abcd-ef1234567890"))
        XCTAssertTrue(redacted.contains("Bearer [redacted]"))
    }

    func testRedactsStandaloneJwt() {
        let message = "Unable to parse response: unexpected value eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk"

        let redacted = LogRedactor.redact(message)

        XCTAssertFalse(redacted.contains("eyJhbGciOiJSUzI1NiJ9"))
        XCTAssertTrue(redacted.contains("[redacted]-jwt"))
    }

    // MARK: - Tokens carried in URLs

    func testRedactsTokensInQueryStrings() {
        let message = "redirect: https://example.com/cb?state=xyz&code=SplxlOBeZQQYbYS6WxSbIA&access_token=abc123"

        let redacted = LogRedactor.redact(message)

        XCTAssertFalse(redacted.contains("SplxlOBeZQQYbYS6WxSbIA"))
        XCTAssertFalse(redacted.contains("abc123"))
        // A query item with a harmless name is left alone.
        XCTAssertTrue(redacted.contains("state=xyz"))
    }

    func testRedactsTokenInNightscoutAuthorizationPath() {
        let message = "GET https://ns.example.com/api/v2/authorization/request/a1b2c3d4e5f6a7b8c9d0 failed"

        let redacted = LogRedactor.redact(message)

        XCTAssertFalse(redacted.contains("a1b2c3d4e5f6a7b8c9d0"))
        XCTAssertTrue(redacted.contains("/authorization/request/[redacted]"))
    }

    func testSafeURLKeepsHostAndPathButDropsCredentials() {
        let url = URL(string: "https://user:pw@vcr.example.com/tandem/accounts/api/connect/authorize?client_id=abc&code=SECRETCODE&scope=openid#frag")

        let safe = LogRedactor.safeURL(url)

        XCTAssertFalse(safe.contains("pw"))
        XCTAssertFalse(safe.contains("SECRETCODE"))
        XCTAssertFalse(safe.contains("frag"))
        // Still recognisably the same endpoint.
        XCTAssertTrue(safe.contains("vcr.example.com"))
        XCTAssertTrue(safe.contains("/tandem/accounts/api/connect/authorize"))
        XCTAssertTrue(safe.contains("client_id=abc"))
    }

    func testSafeURLHandlesNil() {
        XCTAssertEqual(LogRedactor.safeURL(nil), "nil")
    }

    // MARK: - No over-redaction

    /// Over-redaction would make the log useless for its actual purpose —
    /// diagnosing vendor API changes — so the fields that matter must survive.
    func testKeepsPumpEventDataUseful() {
        let message = #"{"eventCode":279,"code":200,"sequenceNumber":3289576,"modelName":"t:slim X2"}"#

        let redacted = LogRedactor.redact(message)

        XCTAssertTrue(redacted.contains("279"))
        XCTAssertTrue(redacted.contains("200"))
        XCTAssertTrue(redacted.contains("3289576"))
        XCTAssertTrue(redacted.contains("t:slim X2"))
        XCTAssertFalse(redacted.contains("[redacted]"))
    }

    func testKeepsStatusCodesCountsAndTimes() {
        let message = "fetchPumpLogs: HTTP 200, 1264 bytes, keys: clockChanges=0, events=1188"

        XCTAssertEqual(LogRedactor.redact(message), message)
    }

    func testIsIdempotent() {
        let message = #"{"token":"aaa","eventCode":279} Bearer bbb"#

        let once = LogRedactor.redact(message)
        XCTAssertEqual(LogRedactor.redact(once), once)
    }

    func testTruncatesVeryLongMessages() {
        let message = String(repeating: "a", count: LogRedactor.maxLength + 500)

        let redacted = LogRedactor.redact(message)

        XCTAssertLessThan(redacted.count, message.count)
        XCTAssertTrue(redacted.contains("[truncated 500 chars]"))
    }

    // MARK: - Payload shapes

    func testPayloadShapeDescribesKeysAndArrayLengthsWithoutValues() throws {
        let json = #"{"events":[{"eventCode":279,"commandedRate":290},{"eventCode":279,"commandedRate":290}],"clockChanges":[],"patientName":"Ada"}"#

        let shape = LogRedactor.payloadShape(of: Data(json.utf8))

        XCTAssertTrue(shape.contains("clockChanges=0"))
        XCTAssertTrue(shape.contains("events=2"))
        XCTAssertTrue(shape.contains("patientName"))
        // No values, and no key whose value was a measurement.
        XCTAssertFalse(shape.contains("290"))
        XCTAssertFalse(shape.contains("279"))
        XCTAssertFalse(shape.contains("Ada"))
    }

    func testPayloadShapeSummarisesNestedObjectsByTheirKeys() throws {
        let json = #"{"settings":{"id":"x","dda":300,"maxBasalRate":2.5}}"#

        let shape = LogRedactor.payloadShape(of: Data(json.utf8))

        XCTAssertTrue(shape.contains("settings={"))
        XCTAssertTrue(shape.contains("maxBasalRate"))
        XCTAssertFalse(shape.contains("2.5"))
        XCTAssertFalse(shape.contains("300"))
    }

    func testPayloadShapeHandlesArraysAndNonJson() throws {
        let array = LogRedactor.payloadShape(of: Data(#"[{"sgv":112,"direction":"Flat"}]"#.utf8))
        XCTAssertTrue(array.contains("array of 1"))
        XCTAssertTrue(array.contains("element keys: direction, sgv"))
        XCTAssertFalse(array.contains("112"))

        XCTAssertTrue(LogRedactor.payloadShape(of: Data("<html>error</html>".utf8)).contains("not JSON"))
        XCTAssertEqual(LogRedactor.payloadShape(of: Data()), "empty body")
        XCTAssertEqual(LogRedactor.payloadShape(of: nil), "empty body")
    }

    // MARK: - Guard rail

    /// The scrubber can recognise credentials, but not measurement values — a
    /// glucose reading is just a number. So the rule that call sites must not
    /// interpolate a raw response body is enforced here, over the source tree.
    func testNoLogCallSiteInterpolatesARawResponseBody() throws {
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GlucoseBarTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("GlucoseBar")

        let forbidden = ["\\(data)", "\\(body)", "\\(preview)", "\\(str)", "\\(json)"]

        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sourceDirectory, includingPropertiesForKeys: nil))
        var offenders: [String] = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), trimmed.contains("plog(") || trimmed.contains("dlog(") else { continue }
                for pattern in forbidden where line.contains(pattern) {
                    offenders.append("\(fileURL.lastPathComponent):\(index + 1): \(trimmed)")
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "log calls must use LogRedactor.payloadShape(of:) instead of interpolating a payload:\n\(offenders.joined(separator: "\n"))"
        )
    }
}
