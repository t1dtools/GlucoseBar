import Foundation
import SwiftUI

/// Reference-type wrapper giving each CGM source a stable, identifiable lifetime.
///
/// `SourceState` is a **class** (reference type) so that `Glucose` timer and
/// socket connections survive across `body` re-evaluations in `GlucoseBarApp`.
///
/// Each instance owns a per-source `SettingsStore` (namespaced to its UUID) and
/// the `Glucose` object that drives data fetching for that source.
@MainActor
final class SourceState: ObservableObject, Identifiable {
    let id: UUID
    let sourceIndex: Int
    /// `nonisolated` so these can be passed to `.environmentObject()` inside
    /// view-builder closures without requiring an explicit `@MainActor` context.
    nonisolated let settings: SettingsStore
    nonisolated let glucose: Glucose
    /// Tracks whether this source's popover is currently open.
    /// Set by the content view's `.onAppear`/`.onDisappear` and read by
    /// `SourceMenuBarLabel` to guard the auto-open logic.
    @Published var isPanePresented: Bool = false

    /// Creates a source backed by the given UUID.
    init(id: UUID, index: Int) {
        self.id = id
        self.sourceIndex = index
        let settings = SettingsStore(sourceId: id)
        self.settings = settings
        self.glucose = Glucose(settings)
        self.glucose.sourceIndex = index
        self.glucose.provider.sourceIndex = index
        self.glucose.plog("Source \(index) (\(settings.sourceName)) registered", level: .info)
    }
}

@MainActor
extension SourceState: Hashable {
    nonisolated static func == (lhs: SourceState, rhs: SourceState) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
