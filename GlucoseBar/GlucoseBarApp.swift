//
//  GlucoseBarApp.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-09-23.
//

import SwiftUI
import NightscoutKit
import OSLog
import AppKit
import Network

class ViewState: ObservableObject, @unchecked Sendable {
    @Published var isPanePresented: Bool = false
    @Published var isOnline: Bool = false

    // This exists to filter out VPNs since they give false positives
    // when network isn't available
    func isOnlyOtherInterface(_ path: NWPath) -> Bool {
        if path.usesInterfaceType(.other) {
            if !path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi) && !path.usesInterfaceType(.wiredEthernet) && !path.usesInterfaceType(.loopback) {
                return true
            }
        }

        return false
    }

    init() {
        let networkMonitor = NWPathMonitor()
        networkMonitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                if path.status == .satisfied && !self.isOnlyOtherInterface(path) {
                    self.isOnline = true
                } else {
                    self.isOnline = false
                }
            }
        }

        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
    }
}

func formatGlucoseForDisplay(settings: SettingsStore, glucose: Double) -> String {
    if (settings.glucoseUnit == .mmoll) {
        return String(format: "%.1f", glucose/18)
    }

    return String(format: "%.0f", glucose)
}

func formatDeltaForDisplay(settings: SettingsStore, delta: Double) -> String {
    if (settings.glucoseUnit == .mmoll) {
        return delta > 0 ? String(format: "+%.1f", delta/18) : String(format: "%.1f", delta/18)
    }

    return delta > 0 ? String(format: "+%.0f", delta) : String(format: "%.0f", delta)
}

func printFormattedGlucose(settings: SettingsStore, glucose: Double) -> String {
    if (settings.glucoseUnit == .mmoll) {
        return String(format: "%.1f mmol/L", glucose)
    }

    return String(format: "%.0f mg/dL", glucose)
}

@main
struct GlucoseBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.colorScheme) private var colorScheme

    @State private var title: Text = Text("GlucoseBar")
    @State private var hasSettings: Bool = true

    let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "main")

    @StateObject var s: SettingsStore = SettingsStore()
    @StateObject var g: Glucose = Glucose()
    @StateObject var vs: ViewState = ViewState()

    func CreateTitleText() -> String {
        var t = formatGlucoseForDisplay(settings: s, glucose: g.glucose) + " " + g.trend

        if s.showDelta {
            t += " " + formatDeltaForDisplay(settings: s, delta: g.delta)
        }

        if s.showTimeSince && vs.isOnline {
            t += " (\(g.glucoseAge))"

        // Always show value age if over 5 minutes
        } else if g.glucoseTime.timeIntervalSinceNow * -1 > (5 * 60) + 15 {
            if vs.isOnline {
                t += " (\(g.glucoseAge))"
            } else {
                t += " (Offline)"
            }

        // Show just "Offline" if value age is over 10 minutes
        } else if g.glucoseTime.timeIntervalSinceNow * -1 > (10 * 60) + 15 {
            t = "Offline"
        }

        return t
    }

    func CreateTitleImage() -> NSImage {
        var color = NSColor.white
        var applyColor = false
        var accessibilityDescription = "In range"
        var symbol = "drop.halffull"
        if g.glucose > s.highThreshold {
            color = NSColor.yellow
            accessibilityDescription = "Above range"
            symbol = "drop.fill"
            applyColor = true
        } else if g.glucose < s.lowThreshold {
            color = NSColor.red
            accessibilityDescription = "Below range"
            symbol = "drop"
            applyColor = true
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .light)
        if applyColor {
            configuration.applying(.init(paletteColors: [color]))
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription)
        let titleImage = image?.withSymbolConfiguration(configuration) ?? NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription)!

        return titleImage
    }

    var body: some Scene {
        MenuBarExtra {
            MainAppView()
                .environmentObject(g)
                .environmentObject(s)
                .environmentObject(vs)
        } label: {
            if !s.validSettings {
                Label(
                    title: { Text("Configure") },
                    icon: { Image(systemName: "book.and.wrench.fill") }
                ).labelStyle(.titleAndIcon)
            } else if g.error != "" && s.validSettings && vs.isOnline {
                Label(
                    title: { Text("Error") },
                    icon: { Image(systemName: "exclamationmark.octagon.fill") }
                ).labelStyle(.titleAndIcon)
            } else if g.fetchedGlucose {
                if s.showMenuBarIcon {
                    Label(
                        title: { Text(" \(CreateTitleText())") },
                        icon: { Image(nsImage: CreateTitleImage()) }
                    ).labelStyle(.titleAndIcon)
                } else {
                    Text(CreateTitleText())
                }
            } else {
                if !vs.isOnline {
                    Image(
                        nsImage: NSImage(systemSymbolName: "bolt.horizontal", accessibilityDescription: "Can not start GlucoseBar while offline")!)
                } else {
                    Image(nsImage: NSImage(systemSymbolName: "drop.halffull", accessibilityDescription: "Starting GlucoseBar")!.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .light))!)
                }
            }
        }
        .menuBarExtraStyle(.window)
//        .menuBarExtraAccess(isPresented: $vs.isPanePresented) { _ in
//        }

        Settings {
            SettingsView().onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { newValue in
                DispatchQueue.main.async {
                    vs.isPanePresented = false
                }
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.orderFrontRegardless()
            }.onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { newValue in
                NSApp.deactivate()
                NSApp.setActivationPolicy(.prohibited)
            }.environmentObject(s).environmentObject(g)
        }.handlesExternalEvents(matching: Set(arrayLiteral: "SettingsView"))
    }
}

@available(macOS 10.15, *)
class AppDelegate: NSObject, NSApplicationDelegate {

    let notificationCenter = NotificationCenter.default

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleepListener(_:)),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func sleepListener(_ aNotification: Notification) {
        if aNotification.name == NSWorkspace.didWakeNotification {
            self.notificationCenter.post(.makeComputerSleepEventNotification(forName: .computerDidWakeUp))
        }
    }
}

extension Notification {
    static func makeComputerSleepEventNotification(forName name: Notification.Name) -> Notification {
        return Notification(name: name)
    }
}

extension Notification.Name {
    static let computerDidWakeUp = Notification.Name("computerDidWakeUp")
}

extension Bundle {
    public var appName: String           { getInfo("CFBundleName") }
    public var displayName: String       { getInfo("CFBundleDisplayName") }
    public var language: String          { getInfo("CFBundleDevelopmentRegion") }
    public var identifier: String        { getInfo("CFBundleIdentifier") }
    public var copyright: String         { getInfo("NSHumanReadableCopyright").replacingOccurrences(of: "\\\\n", with: "\n") }

    public var appBuild: String          { getInfo("CFBundleVersion") }
    public var appVersionLong: String    { getInfo("CFBundleShortVersionString") }

    fileprivate func getInfo(_ str: String) -> String { infoDictionary?[str] as? String ?? "⚠️" }
}
