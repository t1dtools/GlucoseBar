//
//  CredentialMigrationTests.swift
//  GlucoseBarTests
//

import XCTest
@testable import GlucoseBar

/// Credentials must live in the Keychain rather than plaintext `UserDefaults`, and
/// an existing installation has to be migrated without losing anything.
///
/// Everything here runs against the in-memory store and a scratch defaults suite,
/// so the developer's real keychain and real settings are never touched.
@MainActor
final class CredentialMigrationTests: XCTestCase {

    private let suiteName = "tools.t1d.GlucoseBar.tests.credentials"
    private var defaults: UserDefaults!
    private var credentials: InMemoryCredentialStore!

    override func setUp() async throws {
        try await super.setUp()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        credentials = InMemoryCredentialStore()
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        credentials = nil
        try await super.tearDown()
    }

    /// The key an earlier release wrote the plaintext credential to.
    private func legacyKey(_ id: UUID, _ field: CredentialField) -> String {
        "\(id.uuidString).\(field.rawValue)"
    }

    private func makeStore(_ id: UUID) -> SettingsStore {
        SettingsStore(sourceId: id, defaults: defaults, credentials: credentials)
    }

    private func seedLegacy(_ values: [CredentialField: String], for id: UUID) {
        for (field, value) in values {
            defaults.set(value, forKey: legacyKey(id, field))
        }
    }

    // MARK: - Migration from plaintext

    func testMigratesPlaintextCredentialIntoTheKeychain() throws {
        let id = UUID()
        seedLegacy([.nightscoutToken: "token-abc123"], for: id)

        let store = makeStore(id)

        XCTAssertEqual(store.nsSecret, "token-abc123")
        XCTAssertEqual(try credentials.secret(for: .nightscoutToken, sourceId: id), "token-abc123")
        XCTAssertNil(
            defaults.string(forKey: legacyKey(id, .nightscoutToken)),
            "the plaintext copy must be removed once the keychain write succeeded"
        )
    }

    func testMigratesEveryCredentialField() throws {
        let id = UUID()
        seedLegacy([
            .nightscoutToken: "ns",
            .dexcomPassword: "dx",
            .librePassword: "libre",
            .tandemPassword: "tandem",
        ], for: id)

        let store = makeStore(id)

        XCTAssertEqual(store.nsSecret, "ns")
        XCTAssertEqual(store.dxPassword, "dx")
        XCTAssertEqual(store.librePassword, "libre")
        XCTAssertEqual(store.tandemPassword, "tandem")

        for field in CredentialField.allCases {
            XCTAssertNil(defaults.string(forKey: legacyKey(id, field)), "\(field.rawValue) was left in plaintext")
        }
    }

    func testMigrationIsIdempotent() throws {
        let id = UUID()
        seedLegacy([.nightscoutToken: "token"], for: id)

        _ = makeStore(id)

        // Simulate something re-creating the legacy key: a second launch must prefer
        // the keychain item and never fall back to plaintext again.
        seedLegacy([.nightscoutToken: "stale"], for: id)
        let second = makeStore(id)

        XCTAssertEqual(second.nsSecret, "token")
        XCTAssertEqual(try credentials.secret(for: .nightscoutToken, sourceId: id), "token")
    }

    /// A failed keychain write must leave the plaintext value working rather than
    /// losing the credential — and must not delete it.
    func testFailedMigrationKeepsThePlaintextCopy() throws {
        let id = UUID()
        seedLegacy([.nightscoutToken: "token"], for: id)
        credentials.failsWrites = true

        let store = makeStore(id)

        XCTAssertEqual(store.nsSecret, "token", "the credential must still be usable")
        XCTAssertEqual(
            defaults.string(forKey: legacyKey(id, .nightscoutToken)), "token",
            "the plaintext copy must survive a failed write"
        )
        XCTAssertNil(try credentials.secret(for: .nightscoutToken, sourceId: id))
    }

    // MARK: - Saving

    func testSavingWritesNoCredentialToUserDefaults() throws {
        let id = UUID()
        let store = makeStore(id)
        store.nsSecret = "ns"
        store.dxPassword = "dx"
        store.librePassword = "libre"
        store.tandemPassword = "tandem"

        store.saveInternal()

        for field in CredentialField.allCases {
            XCTAssertNil(
                defaults.string(forKey: legacyKey(id, field)),
                "\(field.rawValue) reached the plaintext store — this is the whole point of the change"
            )
        }
        XCTAssertEqual(try credentials.secret(for: .nightscoutToken, sourceId: id), "ns")
        XCTAssertEqual(try credentials.secret(for: .dexcomPassword, sourceId: id), "dx")
        XCTAssertEqual(try credentials.secret(for: .librePassword, sourceId: id), "libre")
        XCTAssertEqual(try credentials.secret(for: .tandemPassword, sourceId: id), "tandem")
    }

    func testSaveDoesNotRecreateAPlaintextCopy() throws {
        let id = UUID()
        seedLegacy([.dexcomPassword: "migrated"], for: id)

        let store = makeStore(id)
        store.dxPassword = "updated"
        store.saveInternal()

        XCTAssertNil(defaults.string(forKey: legacyKey(id, .dexcomPassword)))
        XCTAssertEqual(try credentials.secret(for: .dexcomPassword, sourceId: id), "updated")
    }

    func testFailedSaveSurfacesAnErrorAndKeepsTheOldValue() throws {
        let id = UUID()
        let store = makeStore(id)
        store.nsSecret = "good"
        store.saveInternal()
        XCTAssertNil(store.credentialSaveError)

        credentials.failsWrites = true
        store.nsSecret = "replacement"
        store.saveInternal()

        XCTAssertNotNil(store.credentialSaveError, "a failed write has to be visible to the user")
        XCTAssertEqual(
            try credentials.secret(for: .nightscoutToken, sourceId: id), "good",
            "the previous credential must survive a failed write"
        )
    }

    func testClearingACredentialRemovesItFromTheKeychain() throws {
        let id = UUID()
        let store = makeStore(id)
        store.nsSecret = "token"
        store.saveInternal()

        store.nsSecret = ""
        store.saveInternal()

        XCTAssertNil(try credentials.secret(for: .nightscoutToken, sourceId: id))
    }

    // MARK: - Deletion

    func testDeletingAProviderRemovesItsCredential() throws {
        let id = UUID()
        let store = makeStore(id)
        store.cgmProvider = .nightscout
        store.nsSecret = "token"
        store.saveInternal()
        XCTAssertNotNil(try credentials.secret(for: .nightscoutToken, sourceId: id))

        store.deleteCGMProviderInternal()

        XCTAssertNil(
            try credentials.secret(for: .nightscoutToken, sourceId: id),
            "deleting a provider must not leave its credential in the keychain"
        )
    }

    func testResettingASourceRemovesItsCredentials() throws {
        let id = UUID()
        let store = makeStore(id)
        store.nsSecret = "token"
        store.dxPassword = "password"
        store.saveInternal()

        store.resetToDefaultsInternal()

        XCTAssertNil(try credentials.secret(for: .nightscoutToken, sourceId: id))
        XCTAssertNil(try credentials.secret(for: .dexcomPassword, sourceId: id))
    }

    func testDeletingAllSecretsLeavesOtherSourcesAlone() throws {
        let kept = UUID()
        let removed = UUID()
        try credentials.setSecret("keep", for: .nightscoutToken, sourceId: kept)
        try credentials.setSecret("drop", for: .nightscoutToken, sourceId: removed)

        try credentials.deleteAll(for: removed)

        XCTAssertEqual(try credentials.secret(for: .nightscoutToken, sourceId: kept), "keep")
        XCTAssertNil(try credentials.secret(for: .nightscoutToken, sourceId: removed))
    }

    // MARK: - iCloud Keychain toggle

    func testMigratingASourceReStoresItsCredentialsInTheNewClass() throws {
        let id = UUID()
        try credentials.setSecret("token", for: .nightscoutToken, sourceId: id)

        try credentials.migrateSecrets(for: id, to: .iCloudKeychain)

        XCTAssertEqual(credentials.lastWriteMode, .iCloudKeychain, "the migration must write through the new class")
        XCTAssertEqual(try credentials.secret(for: .nightscoutToken, sourceId: id), "token", "the value must survive the move")

        try credentials.migrateSecrets(for: id, to: .local)

        XCTAssertEqual(credentials.lastWriteMode, .local)
        XCTAssertEqual(try credentials.secret(for: .nightscoutToken, sourceId: id), "token")
    }

    func testSyncPreferenceDefaultsToOff() {
        XCTAssertFalse(CredentialSyncPreference.isEnabled)
        XCTAssertEqual(CredentialSyncPreference.mode, .local)
        XCTAssertFalse(CredentialSyncMode.local.isSynchronizable)
        XCTAssertTrue(CredentialSyncMode.iCloudKeychain.isSynchronizable)
    }
}
