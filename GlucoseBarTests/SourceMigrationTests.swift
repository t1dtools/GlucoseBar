//
//  SourceMigrationTests.swift
//  GlucoseBarTests
//

import XCTest
@testable import GlucoseBar

/// Covers the one-time migration of the pre-multi-source flat `UserDefaults`
/// keys into the namespaced `"<uuid>.<key>"` form. Run against a scratch suite;
/// `SourceManager` itself is deliberately not constructed here because doing so
/// would stand up live providers.
@MainActor
final class SourceMigrationTests: XCTestCase {

    private let suiteName = "tools.t1d.GlucoseBar.tests.migration"
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        try await super.tearDown()
    }

    @discardableResult
    private func migrate(newId: UUID) -> UUID? {
        SourceManager.migrateLegacyKeys(
            in: defaults,
            legacyKeys: SourceManager.legacyFlatKeys,
            sourceIdsKey: SourceManager.sourceIdsKey,
            migrationFlagKey: SourceManager.migrationFlagKey,
            newId: newId
        )
    }

    private func storedSourceIds() throws -> [String] {
        let data = try XCTUnwrap(defaults.data(forKey: SourceManager.sourceIdsKey))
        return try JSONDecoder().decode([String].self, from: data)
    }

    func testCopiesLegacyKeysIntoTheFirstSource() throws {
        defaults.set("https://nightscout.example.com", forKey: "nsURL")
        defaults.set("dexcomshare", forKey: "cgmProvider")
        defaults.set(190.0, forKey: "highThreshold")

        let id = UUID()
        XCTAssertEqual(migrate(newId: id), id)

        XCTAssertEqual(defaults.string(forKey: "\(id.uuidString).nsURL"), "https://nightscout.example.com")
        XCTAssertEqual(defaults.string(forKey: "\(id.uuidString).cgmProvider"), "dexcomshare")
        XCTAssertEqual(defaults.double(forKey: "\(id.uuidString).highThreshold"), 190.0)

        XCTAssertEqual(try storedSourceIds(), [id.uuidString])
        XCTAssertTrue(defaults.bool(forKey: SourceManager.migrationFlagKey))
    }

    func testLegacyKeysAreLeftInPlace() throws {
        defaults.set("https://nightscout.example.com", forKey: "nsURL")
        migrate(newId: UUID())

        // Intentionally not deleted, so a downgrade still finds them.
        XCTAssertEqual(defaults.string(forKey: "nsURL"), "https://nightscout.example.com")
    }

    func testKeysThatWereNeverSetAreNotMigrated() throws {
        defaults.set("https://nightscout.example.com", forKey: "nsURL")

        let id = UUID()
        migrate(newId: id)

        XCTAssertNil(defaults.object(forKey: "\(id.uuidString).dxEmail"))
        XCTAssertNil(defaults.object(forKey: "\(id.uuidString).nsSecret"))
    }

    func testDoesNotMigrateTwice() throws {
        defaults.set("https://nightscout.example.com", forKey: "nsURL")

        let first = UUID()
        XCTAssertNotNil(migrate(newId: first))
        XCTAssertNil(migrate(newId: UUID()), "second run must be a no-op")
        XCTAssertEqual(try storedSourceIds(), [first.uuidString])
    }

    /// An existing `sourceIds` list means multi-source support is already in use,
    /// so the flag is set without creating another source.
    func testSkipsWhenSourcesAlreadyExist() throws {
        let existing = UUID()
        defaults.set(try JSONEncoder().encode([existing.uuidString]), forKey: SourceManager.sourceIdsKey)
        defaults.set("https://nightscout.example.com", forKey: "nsURL")

        XCTAssertNil(migrate(newId: UUID()))
        XCTAssertEqual(try storedSourceIds(), [existing.uuidString])
        XCTAssertTrue(defaults.bool(forKey: SourceManager.migrationFlagKey))
    }

    func testMigratedProviderValueIsStillResolvedByTheStore() throws {
        defaults.set("Simulador", forKey: "cgmProvider")

        let id = UUID()
        migrate(newId: id)

        let store = SettingsStore(sourceId: id, defaults: defaults, credentials: InMemoryCredentialStore())
        XCTAssertEqual(store.cgmProvider, .simulator)
    }
}
