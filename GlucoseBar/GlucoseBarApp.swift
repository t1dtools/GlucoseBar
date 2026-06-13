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
    private var probe: NWConnection?
    private let probeQueue = DispatchQueue(label: "tools.t1d.GlucoseBar.probe")
    init() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            if path.status == .satisfied {
                self.startProbe()
            } else {
                self.cancelProbe()
                Task { @MainActor in self.isOnline = false }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }
    private func startProbe() {
        cancelProbe()
        let host = NWEndpoint.Host("1.1.1.1")
        let port = NWEndpoint.Port(rawValue: 443)!
        let conn = NWConnection(host: host, port: port, using: .tcp)
        probe = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                Task { @MainActor in self.isOnline = true }
                self.cancelProbe()
            case .failed:
                // retry after 3 seconds if path is still satisfied
                probeQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self = self else { return }
                    if self.networkMonitor.currentPath.status == .satisfied {
                        self.startProbe()
                    }
                }
            default:
                break
            }
        }
        conn.start(queue: probeQueue)
    }
    private func cancelProbe() {
        probe?.cancel()
        probe = nil
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
    @StateObject var uc: UpdateChecker = UpdateChecker()

    // vs and g share the same ViewState so that Glucose's online check and
    // the UI's offline indicator always reflect the same NWPathMonitor.
    @StateObject var vs: ViewState
    @StateObject var g: Glucose

    init() {
        _ = KeepAliveManager.shared
        let sharedVS = ViewState()
        _vs = StateObject(wrappedValue: sharedVS)
        _g = StateObject(wrappedValue: Glucose(SettingsStore(), viewState: sharedVS))
    }

    var body: some Scene {
        MenuBarExtra {
            MainAppView()
                .environmentObject(g)
                .environmentObject(s)
                .environmentObject(vs)
                .environmentObject(uc)
                .onAppear {
                    mainViewPresented = true
                    Task { await uc.checkIfNeeded() }
                }.onDisappear {
                    mainViewPresented = false
                }
        } label: {
            Group {
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
                if g.provider.providerIssue == "Dexcom: No Data" {
                    Label(
                        title: { Text(" No data") },
                        icon: { Image(systemName: "bolt.trianglebadge.exclamationmark")}
                    ).labelStyle(.titleAndIcon)
                } else {
                    Label(
                        title: { Text("Error") },
                        icon: { Image(systemName: "exclamationmark.octagon.fill") }
                    ).labelStyle(.titleAndIcon)
                }
            } else if g.fetchedGlucose {
                MenuBarView().environmentObject(s).environmentObject(g).environmentObject(uc)
            } else {
                if !vs.isOnline {
                    Image(
                        nsImage: NSImage(systemSymbolName: "bolt.horizontal", accessibilityDescription: "Can not start GlucoseBar while offline")!)
                } else {
                    Image(nsImage: NSImage(systemSymbolName: "drop.halffull", accessibilityDescription: "Starting GlucoseBar")!)
                }
            }
            }
            .task { await uc.checkIfNeeded() }
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
              }.environmentObject(s).environmentObject(g).environmentObject(uc)

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

    public var appBuild: Int             { Int(getInfo("CFBundleVersion")) ?? 0 }
    public var appVersionLong: String    { getInfo("CFBundleShortVersionString") }

    fileprivate func getInfo(_ str: String) -> String { infoDictionary?[str] as? String ?? "⚠️" }
}
