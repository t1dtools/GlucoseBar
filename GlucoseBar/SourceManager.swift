import Foundation
import OSLog
import SwiftUI

/// App-level coordinator that owns the list of active `SourceState` instances.
///
/// Persists the source order as a JSON array of UUID strings under the
/// `UserDefaults` key `"sourceIds"`. Each source's settings are stored under
/// per-source namespaced keys managed by the source's `SettingsStore`.
@MainActor
final class SourceManager: ObservableObject {
    @Published var sources: [SourceState] = []
    @Published var refreshToken = UUID()
    @Published var pendingSelectedSourceId: UUID? = nil

    private let defaults = UserDefaults.standard

    static let sourceIdsKey = "sourceIds"
    static let migrationFlagKey = "migratedToMultiSource"

    // All flat UserDefaults keys that existed before multi-source support.
    static let legacyFlatKeys: [String] = [
        "nsURL", "nsSecret",
        "dxServer", "dxEmail", "dxPassword",
        "libreServer", "libreUsername", "librePassword", "libreConnectionID",
        "cgmProvider",
        "glucoseUnit",
        "highThreshold", "lowThreshold", "glucoseTarget",
        "graphMinutes",
        "showTimeSince", "showDelta",
        "showMenuBarIcon",
        "menuBarItems", "menuBarItemSpacing",
        "zenMode",
        "glucoseColorScheme",
        "showHighThreshold", "showLowThreshold", "showTarget",
        "trioEnableIntegration",
        "trioBarShowIOB", "trioBarShowCOB", "trioBarShowEventualGlucose",
        "trioChartShowForecast", "trioChartForecastDisplay",
        "trioChartShowIOB", "trioChartShowCOB", "trioChartShowEventualGlucose",
        "trioChartShowLoopStatus",
        "validSettings",
    ]

    init() {
        migrateFromLegacyIfNeeded()
        loadSources()
    }

    // MARK: - Public API

    /// Maximum number of sources that can be active simultaneously.
    /// Enforced here and reflected in the Settings UI.
    static let maxSources = 5

    /// Adds a new blank source and persists the updated source list.
    /// No-ops silently when already at `maxSources`.
    func addSource() -> UUID? {
        guard sources.count < SourceManager.maxSources else { return nil }
        let newId = UUID()
        let state = SourceState(id: newId, index: sources.count)
        sources.append(state)
        persistSourceIds()

        return newId
    }

    /// Removes the source with the given id.
    ///
    /// If this is the last source, it is reset to defaults instead of removed
    /// so there is always at least one source present.
    func removeSource(id: UUID) {
        guard sources.count > 1 else {
            // Reset last source to defaults rather than leaving zero sources.
            sources.first?.settings.resetToDefaults()
            return
        }
        sources.first(where: { $0.id == id })?.glucose.stop()
        sources.removeAll { $0.id == id }
        removeUserDefaultsKeys(for: id)
        persistSourceIds()
    }

    // MARK: - Private helpers

    private func loadSources() {
        let ids = loadSourceIds()
        sources = ids.enumerated().map { SourceState(id: $1, index: $0) }

        // Guard: always maintain at least one source.
        if sources.isEmpty {
            let newId = UUID()
            sources = [SourceState(id: newId, index: 0)]
            persistSourceIds()
        }
    }

    private func loadSourceIds() -> [UUID] {
        guard
            let data = defaults.data(forKey: Self.sourceIdsKey),
            let strings = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return strings.compactMap { UUID(uuidString: $0) }
    }

    private func persistSourceIds() {
        let strings = sources.map { $0.id.uuidString }
        if let data = try? JSONEncoder().encode(strings) {
            defaults.set(data, forKey: Self.sourceIdsKey)
        }
    }

    /// Removes all `"\(id).*"` UserDefaults keys belonging to a deleted source, and
    /// the source's credentials.
    private func removeUserDefaultsKeys(for id: UUID) {
        let prefix = "\(id.uuidString)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }

        // Credentials live in the keychain, a separate store, so they have to be
        // deleted explicitly or they outlive the source that owned them.
        do {
            try KeychainCredentialStore().deleteAll(for: id)
        } catch {
            Logger(subsystem: "tools.t1d.GlucoseBar", category: "credentials")
                .dlog("Could not delete credentials for a removed source: \(error)", category: "credentials", level: .error)
        }
    }

    // MARK: - Migration

    /// Migrates flat legacy UserDefaults keys to the namespaced multi-source
    /// format the first time the app runs after the update.
    ///
    /// - Reads each known flat key and copies it to `"\(newUUID).\(key)"`.
    /// - Writes `sourceIds = [newUUID]` to anchor the migrated source.
    /// - Sets `"migratedToMultiSource"` to prevent re-running on next launch.
    /// - Old flat keys are left in place and can be pruned in a future release.
    private func migrateFromLegacyIfNeeded() {
        Self.migrateLegacyKeys(
            in: defaults,
            legacyKeys: Self.legacyFlatKeys,
            sourceIdsKey: Self.sourceIdsKey,
            migrationFlagKey: Self.migrationFlagKey
        )
    }

    /// The migration itself, taking the `UserDefaults` to operate on so it can be
    /// exercised against a scratch suite without a `SourceManager` (and therefore
    /// without standing up live providers).
    ///
    /// Returns the id of the migrated source, or `nil` when nothing was migrated.
    @discardableResult
    static func migrateLegacyKeys(
        in defaults: UserDefaults,
        legacyKeys: [String],
        sourceIdsKey: String,
        migrationFlagKey: String,
        newId: UUID = UUID()
    ) -> UUID? {
        // Already migrated, or sourceIds already written by a previous run.
        guard !defaults.bool(forKey: migrationFlagKey) else { return nil }
        guard defaults.data(forKey: sourceIdsKey) == nil else {
            defaults.set(true, forKey: migrationFlagKey)
            return nil
        }

        let prefix = "\(newId.uuidString)."

        for key in legacyKeys {
            if let value = defaults.object(forKey: key) {
                defaults.set(value, forKey: "\(prefix)\(key)")
            }
        }

        if let data = try? JSONEncoder().encode([newId.uuidString]) {
            defaults.set(data, forKey: sourceIdsKey)
        }
        defaults.set(true, forKey: migrationFlagKey)

        return newId
    }
}
