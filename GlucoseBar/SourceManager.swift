import Foundation
import SwiftUI

/// App-level coordinator that owns the list of active `SourceState` instances.
///
/// Persists the source order as a JSON array of UUID strings under the
/// `UserDefaults` key `"sourceIds"`. Each source's settings are stored under
/// per-source namespaced keys managed by the source's `SettingsStore`.
@MainActor
final class SourceManager: ObservableObject {
    @Published var sources: [SourceState] = []

    private let defaults = UserDefaults.standard
    private let sourceIdsKey = "sourceIds"
    private let migrationFlagKey = "migratedToMultiSource"

    // All flat UserDefaults keys that existed before multi-source support.
    private let legacyKeys: [String] = [
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
        let state = SourceState(id: newId)
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
        sources.removeAll { $0.id == id }
        removeUserDefaultsKeys(for: id)
        persistSourceIds()
    }

    // MARK: - Private helpers

    private func loadSources() {
        let ids = loadSourceIds()
        sources = ids.map { SourceState(id: $0) }

        // Guard: always maintain at least one source.
        if sources.isEmpty {
            let newId = UUID()
            sources = [SourceState(id: newId)]
            persistSourceIds()
        }
    }

    private func loadSourceIds() -> [UUID] {
        guard
            let data = defaults.data(forKey: sourceIdsKey),
            let strings = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return strings.compactMap { UUID(uuidString: $0) }
    }

    private func persistSourceIds() {
        let strings = sources.map { $0.id.uuidString }
        if let data = try? JSONEncoder().encode(strings) {
            defaults.set(data, forKey: sourceIdsKey)
        }
    }

    /// Removes all `"\(id).*"` UserDefaults keys belonging to a deleted source.
    private func removeUserDefaultsKeys(for id: UUID) {
        let prefix = "\(id.uuidString)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
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
        // Already migrated, or sourceIds already written by a previous run.
        guard !defaults.bool(forKey: migrationFlagKey) else { return }
        guard defaults.data(forKey: sourceIdsKey) == nil else {
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        let newId = UUID()
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
    }
}
