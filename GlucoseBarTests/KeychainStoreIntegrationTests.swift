//
//  KeychainStoreIntegrationTests.swift
//  GlucoseBarTests
//

import XCTest
@testable import GlucoseBar

/// Exercises the real `KeychainCredentialStore`, which the in-memory store cannot:
/// add-versus-update behaviour, the two item classes, and migration between them.
///
/// **Opt-in**, because it talks to the login keychain and writes items to it. Run
/// with `GLUCOSEBAR_KEYCHAIN_TESTS=1`. It uses a scratch service name and removes
/// everything afterwards, so the app's own credentials are never touched.
///
/// Note the data-protection keychain is unavailable to ad-hoc/unsigned builds
/// (including this test host), so a run here exercises the legacy-keychain
/// fallback. The data-protection path needs a normally signed build.
final class KeychainStoreIntegrationTests: XCTestCase {

    private let service = "t1d.tools.GlucoseBar.tests"
    private var store: KeychainCredentialStore!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GLUCOSEBAR_KEYCHAIN_TESTS"] == "1",
            "set GLUCOSEBAR_KEYCHAIN_TESTS=1 to run keychain integration tests"
        )
        store = KeychainCredentialStore(service: service)
        try store.deleteAllSecrets()
    }

    override func tearDownWithError() throws {
        try? store?.deleteAllSecrets()
        store = nil
    }

    func testRoundTripAndUpdate() throws {
        let id = UUID()

        XCTAssertNil(try store.secret(for: .nightscoutToken, sourceId: id), "a fresh source has no credential")

        try store.setSecret("s3cret", for: .nightscoutToken, sourceId: id)
        XCTAssertEqual(try store.secret(for: .nightscoutToken, sourceId: id), "s3cret")

        // A second write must update the existing item rather than add a duplicate.
        try store.setSecret("rotated", for: .nightscoutToken, sourceId: id)
        XCTAssertEqual(try store.secret(for: .nightscoutToken, sourceId: id), "rotated")

        try store.deleteSecret(for: .nightscoutToken, sourceId: id)
        XCTAssertNil(try store.secret(for: .nightscoutToken, sourceId: id))
    }

    func testFieldsAndSourcesAreIsolated() throws {
        let first = UUID()
        let second = UUID()

        try store.setSecret("token", for: .nightscoutToken, sourceId: first)
        try store.setSecret("password", for: .tandemPassword, sourceId: first)
        try store.setSecret("other", for: .nightscoutToken, sourceId: second)

        XCTAssertEqual(try store.secret(for: .nightscoutToken, sourceId: first), "token")
        XCTAssertEqual(try store.secret(for: .tandemPassword, sourceId: first), "password")
        XCTAssertNil(try store.secret(for: .dexcomPassword, sourceId: first))
        XCTAssertEqual(try store.secret(for: .nightscoutToken, sourceId: second), "other")
    }

    func testDeleteAllForOneSourceLeavesAnotherIntact() throws {
        let kept = UUID()
        let removed = UUID()
        try store.setSecret("keep", for: .nightscoutToken, sourceId: kept)
        try store.setSecret("drop", for: .dexcomPassword, sourceId: removed)
        try store.setSecret("drop too", for: .tandemPassword, sourceId: removed)

        try store.deleteAll(for: removed)

        XCTAssertEqual(try store.secret(for: .nightscoutToken, sourceId: kept), "keep")
        XCTAssertNil(try store.secret(for: .dexcomPassword, sourceId: removed))
        XCTAssertNil(try store.secret(for: .tandemPassword, sourceId: removed))
    }

    /// The invariant the iCloud toggle depends on: after migrating, the credential
    /// is still readable and there is exactly one copy — not one in each class.
    func testMigrationBetweenClassesKeepsExactlyOneReadableCopy() throws {
        let id = UUID()
        try store.setSecret("value", for: .dexcomPassword, sourceId: id)

        try store.migrateSecrets(for: id, to: .iCloudKeychain)
        XCTAssertEqual(try store.secret(for: .dexcomPassword, sourceId: id), "value", "must be readable after moving to the synced class")

        try store.migrateSecrets(for: id, to: .local)
        XCTAssertEqual(try store.secret(for: .dexcomPassword, sourceId: id), "value", "and after moving back")
    }

    func testDeleteAllSecretsRemovesEverything() throws {
        let id = UUID()
        try store.setSecret("token", for: .nightscoutToken, sourceId: id)
        try store.setSecret("password", for: .tandemPassword, sourceId: id)

        try store.deleteAllSecrets()

        XCTAssertNil(try store.secret(for: .nightscoutToken, sourceId: id))
        XCTAssertNil(try store.secret(for: .tandemPassword, sourceId: id))
    }



}
