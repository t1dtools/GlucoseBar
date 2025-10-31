//
//  GlucoseBarApp.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-09-23.
//

import SwiftUI
import Network

class ViewState: ObservableObject, @unchecked Sendable {
    @Published var isPanePresented: Bool = false
    @Published var isOnline: Bool = false

    private let queue = DispatchQueue(label: "tools.t1d.GlucoseBar.ViewState", attributes: .concurrent)

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
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
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

    @StateObject var s: SettingsStore = SettingsStore()
    @StateObject var g: Glucose = Glucose(SettingsStore())
    @StateObject var vs: ViewState = ViewState()

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
                    Image(nsImage: NSImage(systemSymbolName: "drop.halffull", accessibilityDescription: "Starting GlucoseBar")!)
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
    private var workspaceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil) { [weak self] _ in
                self?.sleepListener()
        }
    }

    deinit {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }

    private func sleepListener() {
        self.notificationCenter.post(.makeComputerSleepEventNotification(forName: .computerDidWakeUp))
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
