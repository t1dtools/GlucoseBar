//
//  SettingsStoreTests.swift
//  GlucoseBarTests
//

import XCTest
@testable import GlucoseBar

/// Round-trip tests for settings persistence, run against a scratch
/// `UserDefaults` suite so the developer's real settings are never touched.
@MainActor
final class SettingsStoreTests: XCTestCase {

    private let suiteName = "tools.t1d.GlucoseBar.tests.settings"
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

    private func key(_ id: UUID, _ base: String) -> String {
        "\(id.uuidString).\(base)"
    }

    private func makeStore(_ id: UUID) -> SettingsStore {
        SettingsStore(sourceId: id, defaults: defaults, credentials: credentials)
    }

    // MARK: - Stable identifiers

    func testProviderIsPersistedAsStableIdentifier() {
        let id = UUID()
        let store = makeStore(id)

        store.cgmProvider = .tandemsource
        store.saveInternal()

        XCTAssertEqual(defaults.string(forKey: key(id, "cgmProvider")), "tandemsource")
    }

    func testGlucoseUnitIsPersistedAsStableIdentifier() {
        let id = UUID()
        let store = makeStore(id)

        store.glucoseUnit = .mmoll
        store.saveInternal()

        XCTAssertEqual(defaults.string(forKey: key(id, "glucoseUnit")), GlucoseUnit.mmoll.rawValue)
    }

    func testColorSchemeAndForecastDisplayArePersistedAsStableIdentifiers() {
        let id = UUID()
        let store = makeStore(id)

        store.glucoseColorScheme = .staticColor
        store.aidChartForecastDisplay = .cone
        store.saveInternal()

        XCTAssertEqual(defaults.string(forKey: key(id, "glucoseColorScheme")), "staticColor")
        XCTAssertEqual(defaults.string(forKey: key(id, "trioChartForecastDisplay")), "cone")
    }

    // MARK: - Migration of values written by older builds

    func testReadsLegacyLocalizedProviderName() {
        let id = UUID()
        // Exactly what an older build wrote while running in Spanish.
        defaults.set("Explorador nocturno", forKey: key(id, "cgmProvider"))

        XCTAssertEqual(makeStore(id).cgmProvider, .nightscout)
    }

    func testLegacyLocalizedValueIsRewrittenAsAnIdentifier() {
        let id = UUID()
        defaults.set("Compartir Dexcom", forKey: key(id, "cgmProvider"))
        defaults.set("Simulateur", forKey: key(id, "cgmProvider"))

        let store = makeStore(id)
        XCTAssertEqual(store.cgmProvider, .simulator)
        store.saveInternal()

        XCTAssertEqual(defaults.string(forKey: key(id, "cgmProvider")), "simulator")
    }

    /// The user-visible regression: whichever language wrote the value, reading it
    /// back in any language must produce the same setting.
    func testProviderSurvivesALanguageChange() {
        for stored in ["Dexcom Share", "Compartir Dexcom", "Dexcom Delen", "dexcomshare"] {
            let id = UUID()
            defaults.set(stored, forKey: key(id, "cgmProvider"))
            XCTAssertEqual(makeStore(id).cgmProvider, .dexcomshare, "failed to resolve \"\(stored)\"")
        }
    }

    func testUnrecognisedProviderFallsBackToNone() {
        let id = UUID()
        defaults.set("Banana", forKey: key(id, "cgmProvider"))

        XCTAssertEqual(makeStore(id).cgmProvider, .null)
    }

    func testAbsentGlucoseUnitDefaultsToMmolPerLitre() {
        let id = UUID()
        XCTAssertEqual(makeStore(id).glucoseUnit, .mmoll)
    }

    // MARK: - Ordinary fields

    func testScalarSettingsRoundTrip() {
        let id = UUID()
        let store = makeStore(id)

        store.nsURL = "https://nightscout.example.com"
        store.nsSecret = "abc123"
        store.highThreshold = 190
        store.lowThreshold = 65
        store.zenMode = true
        store.saveInternal()

        let reloaded = makeStore(id)
        XCTAssertEqual(reloaded.nsURL, "https://nightscout.example.com")
        XCTAssertEqual(reloaded.nsSecret, "abc123")
        XCTAssertEqual(reloaded.highThreshold, 190)
        XCTAssertEqual(reloaded.lowThreshold, 65)
        XCTAssertTrue(reloaded.zenMode)
    }

    func testDefaultsWhenNothingHasBeenSaved() {
        let store = makeStore(UUID())

        XCTAssertEqual(store.cgmProvider, .null)
        XCTAssertEqual(store.highThreshold, 180)
        XCTAssertEqual(store.lowThreshold, 70)
        XCTAssertEqual(store.graphMinutes, 180)
    }
}
