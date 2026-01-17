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
    private let networkMonitor = NWPathMonitor()

    private let queue = DispatchQueue(label: "tools.t1d.GlucoseBar.ViewState", attributes: .concurrent)

    init() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            Task { @MainActor in
                self.isOnline = path.status == .satisfied
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
    @State private var keepAliveActivity: NSObjectProtocol?

    @StateObject var s: SettingsStore = SettingsStore()
    @StateObject var g: Glucose = Glucose(SettingsStore())
    @StateObject var vs: ViewState = ViewState()

    init() {
        _ = KeepAliveManager.shared
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
                    Image(nsImage: NSImage(systemSymbolName: "drop.halffull", accessibilityDescription: "Starting GlucoseBar")!)
                }
            }
        }
        .menuBarExtraStyle(.window)

//        .menuBarExtraAccess(isPresented: $vs.isPanePresented) { _ in
//        }

        Settings {
            SettingsView().onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { newValue in
                Task {
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
    private var keepAliveWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        createHiddenWindow()
        installWakeObserver()

    }

    deinit {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }

    @MainActor
    private func createHiddenWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.orderOut(nil)
        window.collectionBehavior = [.stationary, .ignoresCycle]
        self.keepAliveWindow = window
    }

    private func installWakeObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { _ in
            NotificationCenter.default.post(
                .makeComputerSleepEventNotification(forName: .computerDidWakeUp)
            )
        }
    }

    private static func sleepListener() {
        NotificationCenter.default.post(.makeComputerSleepEventNotification(forName: .computerDidWakeUp))
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
