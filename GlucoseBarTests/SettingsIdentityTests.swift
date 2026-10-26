//
//  SettingsIdentityTests.swift
//  GlucoseBarTests
//

import XCTest
@testable import GlucoseBar

/// Covers the resolution of settings that older builds persisted as localized
/// display names. Those values were compared against the display name in the
/// *current* language, so changing the app language fell through to the default
/// and silently reset the setting.
final class SettingsIdentityTests: XCTestCase {

    /// `Bundle.main` is the app bundle for hosted tests, but resolving it by
    /// identifier is more explicit and keeps working if the test host changes.
    private let appBundle = Bundle(identifier: "t1d.tools.GlucoseBar") ?? .main

    private func resolveProvider(_ stored: String) -> CGMProvider? {
        SettingsIdentifier.resolve(stored, in: CGMProvider.self, sourceName: { $0.presentable }, bundle: appBundle)
    }

    // MARK: - Stable identifiers (what new builds write)

    func testResolvesStableRawValues() {
        XCTAssertEqual(resolveProvider("nightscout"), .nightscout)
        XCTAssertEqual(resolveProvider("dexcomshare"), .dexcomshare)
        XCTAssertEqual(resolveProvider("tandemsource"), .tandemsource)
        XCTAssertEqual(resolveProvider("simulator"), .simulator)
        XCTAssertEqual(resolveProvider("null"), .null)
    }

    // MARK: - Localized display names (what older builds wrote)

    func testResolvesEnglishDisplayNames() {
        XCTAssertEqual(resolveProvider("Nightscout"), .nightscout)
        XCTAssertEqual(resolveProvider("Dexcom Share"), .dexcomshare)
        XCTAssertEqual(resolveProvider("Tandem Source"), .tandemsource)
    }

    /// The actual bug: a build running in Spanish persisted "Explorador
    /// nocturno". Switching to any other language must not lose the provider.
    func testResolvesDisplayNamesFromOtherLanguages() {
        XCTAssertEqual(resolveProvider("Explorador nocturno"), .nightscout)   // es
        XCTAssertEqual(resolveProvider("Compartir Dexcom"), .dexcomshare)     // es
        XCTAssertEqual(resolveProvider("Simulador"), .simulator)              // es
        XCTAssertEqual(resolveProvider("Simulateur"), .simulator)             // fr
        XCTAssertEqual(resolveProvider("Simulatore"), .simulator)             // it
        XCTAssertEqual(resolveProvider("Symulator"), .simulator)              // pl
        XCTAssertEqual(resolveProvider("Partajare Dexcom"), .dexcomshare)     // ro
        XCTAssertEqual(resolveProvider("Dela Dexcom"), .dexcomshare)          // sv
        XCTAssertEqual(resolveProvider("Nachtscout"), .nightscout)            // nl
    }

    func testResolvesLegacyGlucoseUnitNames() {
        XCTAssertEqual(SettingsIdentifier.resolve("mmol/L", in: GlucoseUnit.self, sourceName: { $0.presentable }, bundle: appBundle), .mmoll)
        XCTAssertEqual(SettingsIdentifier.resolve("mg/dL", in: GlucoseUnit.self, sourceName: { $0.presentable }, bundle: appBundle), .mgdl)
        XCTAssertEqual(SettingsIdentifier.resolve("mmoll", in: GlucoseUnit.self, sourceName: { $0.presentable }, bundle: appBundle), .mmoll)
    }

    func testResolvesColorSchemeAndForecastNames() {
        XCTAssertEqual(SettingsIdentifier.resolve("Static", in: GlucoseColorScheme.self, sourceName: { $0.displayName }, bundle: appBundle), .staticColor)
        XCTAssertEqual(SettingsIdentifier.resolve("Dynamic", in: GlucoseColorScheme.self, sourceName: { $0.displayName }, bundle: appBundle), .dynamicColor)
        XCTAssertEqual(SettingsIdentifier.resolve("Cone", in: ForecastDisplay.self, sourceName: { $0.presentable }, bundle: appBundle), .cone)
        XCTAssertEqual(SettingsIdentifier.resolve("Lines", in: ForecastDisplay.self, sourceName: { $0.presentable }, bundle: appBundle), .lines)
    }

    // MARK: - Unusable input

    func testUnknownValueResolvesToNil() {
        XCTAssertNil(resolveProvider("Banana"))
        XCTAssertNil(resolveProvider(""))
    }

    func testLocalizedFormsIncludeEveryShippedLanguageName() {
        let forms = SettingsIdentifier.localizedForms(of: "Simulator", in: appBundle)
        XCTAssertTrue(forms.contains("Simulator"))
        XCTAssertTrue(forms.contains("Simulador"))
        XCTAssertTrue(forms.contains("Simulateur"))
        XCTAssertGreaterThan(forms.count, 2, "expected translations to be found in the app bundle")
    }
}
