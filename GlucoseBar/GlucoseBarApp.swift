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

@main
struct GlucoseBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.colorScheme) private var colorScheme

    @State private var title: Text = Text("GlucoseBar")
    @State private var hasSettings: Bool = true
    @State private var mainViewPresented: Bool = false

    let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "main")

    @StateObject var s: SettingsStore = SettingsStore()
    @StateObject var g: Glucose = Glucose(SettingsStore())
    @StateObject var vs: ViewState = ViewState()

//    init() {
//        _s = StateObject(wrappedValue: SettingsStore(g.settings))
//    }

    func CreateTitleText() -> String {
        var t = formatGlucoseForDisplay(settings: s, glucose: g.glucose) + " " + g.trend

        if s.showDelta {
            t += " " + formatDeltaForDisplay(settings: s, delta: g.delta)
        }

        if g.provider.RemoteGlucoseSource == .trio {
            if s.trioBarShowIOB, let iob = g.provider.GlucoseSourceExtras.iob {
                t += " " + formatIOBForDisplay(iob: iob) + "u"
            }

            if s.trioBarShowCOB, let cob = g.provider.GlucoseSourceExtras.cob, cob > 0 {
                t += " " + formatCOBForDisplay(cob: cob) + "g"
            }

            if s.trioBarShowEventualGlucose, let eventualGlucose = g.provider.GlucoseSourceExtras.eventualGlucose {
                t += " (" + formatGlucoseForDisplay(settings: s, glucose: eventualGlucose) + ")"
            }
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
        var accessibilityDescription = "In range"
        var symbol = "drop.halffull"
        if g.glucose > s.highThreshold {
            accessibilityDescription = "Above range"
            symbol = "drop.fill"
        } else if g.glucose < s.lowThreshold {
            accessibilityDescription = "Below range"
            symbol = "drop"
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .light)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription)
        let titleImage = image?.withSymbolConfiguration(configuration)!

        return titleImage!
    }

    var body: some Scene {
        MenuBarExtra {
            MainAppView()
                .environmentObject(g)
                .environmentObject(s)
                .environmentObject(vs)
                .onAppear {
                    mainViewPresented = true
                }.onDisappear {
                    mainViewPresented = false
                }
        } label: {
            if !s.validSettings {
                Label(
                    title: { Text("Configure") },
                    icon: { Image(systemName: "book.and.wrench.fill") }
                ).labelStyle(.titleAndIcon).onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if !mainViewPresented {
                            let statusItem = NSApp.windows.first?.value(forKey: "statusItem") as? NSStatusItem
                            statusItem?.button?.performClick(nil)
                        }
                    }
                }
            } else if g.error != "" && s.validSettings && vs.isOnline {
                Label(
                    title: { Text("Error") },
                    icon: { Image(systemName: "exclamationmark.octagon.fill") }
                ).labelStyle(.titleAndIcon)
            } else if g.fetchedGlucose {
                MenuBarView().environmentObject(s).environmentObject(g)
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
            }
            .onDisappear {
                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
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
