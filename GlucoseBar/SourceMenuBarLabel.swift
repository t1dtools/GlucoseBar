import SwiftUI

/// Menu bar label for a single CGM source.
///
/// Handles the four display states:
/// - **Configure** — no valid settings yet; auto-opens popover after 2 s
/// - **Error / No data** — provider returned an error while online
/// - **Normal** — `MenuBarView` with live glucose data
/// - **Loading / Offline** — waiting for first fetch or no network
struct SourceMenuBarLabel: View {
    /// The source whose presentation state is tracked for the auto-open guard.
    @ObservedObject var source: SourceState
    /// Set to `false` for `NSStatusItem`-hosted instances (sources 1+) to
    /// suppress the Settings auto-open that fires on first launch.
    var autoOpen: Bool = true

    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose
    @EnvironmentObject var vs: ViewState
    @EnvironmentObject var uc: UpdateChecker

    var body: some View {
        Group {
            if !s.validSettings {
                Label(
                    title: { Text("Configure") },
                    icon: { Image(systemName: "book.and.wrench.fill") }
                )
                .labelStyle(.titleAndIcon)
                .onAppear {
                    guard autoOpen else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if !source.isPanePresented {
                            let statusItem = NSApp.windows.first?.value(forKey: "statusItem") as? NSStatusItem
                            statusItem?.button?.performClick(nil)
                        }
                    }
                }
            } else if g.error != "" && s.validSettings && vs.isOnline {
                if g.provider.providerIssue == "Dexcom: No Data" {
                    Label(
                        title: { Text(" No data") },
                        icon: { Image(systemName: "bolt.trianglebadge.exclamationmark") }
                    ).labelStyle(.titleAndIcon)
                } else {
                    Label(
                        title: { Text("Error") },
                        icon: { Image(systemName: "exclamationmark.octagon.fill") }
                    ).labelStyle(.titleAndIcon)
                }
            } else if g.fetchedGlucose {
                MenuBarView()
                    .environmentObject(s)
                    .environmentObject(g)
                    .environmentObject(uc)
            } else {
                if !vs.isOnline {
                    Image(nsImage: NSImage(
                        systemSymbolName: "bolt.horizontal",
                        accessibilityDescription: "Can not start GlucoseBar while offline")!)
                } else {
                    Image(nsImage: NSImage(
                        systemSymbolName: "drop.halffull",
                        accessibilityDescription: "Starting GlucoseBar")!)
                }
            }
        }
        .task { await uc.checkIfNeeded() }
    }
}
