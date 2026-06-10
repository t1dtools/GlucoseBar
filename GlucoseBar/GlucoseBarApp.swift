//
//  GlucoseBarApp.swift
//
//  Created by Andreas Stokholm on 2023-09-23.
//

import SwiftUI
import Network
import MenuBarExtraAccess

class ViewState: ObservableObject, @unchecked Sendable {
    @Published var isPanePresented: Bool = false
    @Published var isOnline: Bool = false
    private let networkMonitor = NWPathMonitor()
    private var probe: NWConnection?
    private let probeQueue = DispatchQueue(label: "tools.t1d.GlucoseBar.probe")

    // Fallback hosts tried in order. Using two independent services avoids
    // false-offline when a single host (e.g. 1.1.1.1) is blocked by a firewall.
    private let probeHosts: [(String, UInt16)] = [
        ("1.1.1.1", 443),
        ("8.8.8.8", 443),
    ]
    private var probeHostIndex: Int = 0

    init() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            if path.status == .satisfied {
                self.probeHostIndex = 0
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
        let (hostStr, portVal) = probeHosts[probeHostIndex]
        let host = NWEndpoint.Host(hostStr)
        let port = NWEndpoint.Port(rawValue: portVal)!
        let conn = NWConnection(host: host, port: port, using: .tcp)
        probe = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                Task { @MainActor in self.isOnline = true }
                self.cancelProbe()
            case .failed:
                // Try the next fallback host, retry after 3s
                probeQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self = self else { return }
                    guard self.networkMonitor.currentPath.status == .satisfied else { return }
                    self.probeHostIndex = (self.probeHostIndex + 1) % self.probeHosts.count
                    self.startProbe()
                }
            case .waiting:
                // Probe is waiting (e.g. transient DNS/firewall block); retry after 5s
                probeQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self = self else { return }
                    guard self.networkMonitor.currentPath.status == .satisfied else { return }
                    self.probeHostIndex = (self.probeHostIndex + 1) % self.probeHosts.count
                    self.startProbe()
                }
            case .cancelled:
                // Cancelled intentionally by startProbe/cancelProbe — no action needed
                break
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

    @StateObject var sourceManager: SourceManager = SourceManager()
    @StateObject var vs: ViewState = ViewState()
    @StateObject var uc: UpdateChecker = UpdateChecker()
    @StateObject var coordinator: MenuBarCoordinator = MenuBarCoordinator()

    @State var activeSourceIndex: Int? = nil
    @State private var menuBarStatusItems: [Int: NSStatusItem] = [:]

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

    // MARK: - Scene body
    //
    // `@SceneBuilder` does not support bare `if` blocks (buildOptional) without
    // triggering a Swift type-checker crash ("failed to produce diagnostic").
    // Instead, slots 1–4 are declared unconditionally and gated with
    // `isInserted: Binding<Bool>` so SwiftUI hides them when unused.

    var body: some Scene {
        // Slot 0 — always present; receives autoOpen click handling.
        MenuBarExtra {
            menuBarContent(for: sourceManager.sources[0])
        } label: {
            menuBarLabel(for: sourceManager.sources[0], autoOpen: true)
        }
        .menuBarExtraAccess(index: 0, isPresented: activeSource(for: 0)) { item in
            menuBarStatusItems[0] = item
            coordinator.menuBarStatusItems[0] = item
        }
        .menuBarExtraStyle(.window)

        // Slots 1–4 — shown only when a source at that index exists.
        MenuBarExtra(isInserted: isInsertedBinding(for: 1)) {
            if let src = sourceManager.sources[safe: 1] { menuBarContent(for: src) }
        } label: {
            if let src = sourceManager.sources[safe: 1] { menuBarLabel(for: src) }
        }
        .menuBarExtraAccess(index: 1, isPresented: activeSource(for: 1)) { item in
            menuBarStatusItems[1] = item
            coordinator.menuBarStatusItems[1] = item
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: isInsertedBinding(for: 2)) {
            if let src = sourceManager.sources[safe: 2] { menuBarContent(for: src) }
        } label: {
            if let src = sourceManager.sources[safe: 2] { menuBarLabel(for: src) }
        }
        .menuBarExtraAccess(index: 2, isPresented: activeSource(for: 2)) { item in
            menuBarStatusItems[2] = item
            coordinator.menuBarStatusItems[2] = item
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: isInsertedBinding(for: 3)) {
            if let src = sourceManager.sources[safe: 3] { menuBarContent(for: src) }
        } label: {
            if let src = sourceManager.sources[safe: 3] { menuBarLabel(for: src) }
        }
        .menuBarExtraAccess(index: 3, isPresented: activeSource(for: 3)) { item in
            menuBarStatusItems[3] = item
            coordinator.menuBarStatusItems[3] = item
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: isInsertedBinding(for: 4)) {
            if let src = sourceManager.sources[safe: 4] { menuBarContent(for: src) }
        } label: {
            if let src = sourceManager.sources[safe: 4] { menuBarLabel(for: src) }
        }
        .menuBarExtraAccess(index: 4, isPresented: activeSource(for: 4)) { item in
            menuBarStatusItems[4] = item
            coordinator.menuBarStatusItems[4] = item
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { _ in
                    Task { vs.isPanePresented = false }
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.orderFrontRegardless()
                }
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                    NSApp.deactivate()
                }
                .environmentObject(sourceManager)
                .environmentObject(uc)
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "SettingsView"))
    }

    // MARK: - Per-source view helpers

    @ViewBuilder
    private func menuBarContent(for source: SourceState) -> some View {
        MainAppView()
            .environmentObject(source.glucose)
            .environmentObject(source.settings)
            .environmentObject(vs)
            .environmentObject(uc)
            .onAppear   { Task { @MainActor in source.isPanePresented = true  } }
            .onDisappear { Task { @MainActor in source.isPanePresented = false } }
    }

    @ViewBuilder
    private func menuBarLabel(for source: SourceState, autoOpen: Bool = false) -> some View {
        SourceMenuBarLabel(source: source, autoOpen: autoOpen)
            .environmentObject(source.glucose)
            .environmentObject(source.settings)
            .environmentObject(vs)
            .environmentObject(uc)
    }

    // MARK: - isInserted binding helpers

    /// Returns a `Binding<Bool>` that is `true` when a source exists at `index`.
    /// The setter is a no-op — visibility is driven entirely by `sourceManager`.
    private func isInsertedBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { sourceManager.sources.count > index },
            set: { _ in }
        )
    }

    private func activeSource(for index: Int) -> Binding<Bool> {
        Binding(
            get: { activeSourceIndex == index },
            set: { isActive in
                if isActive {
                    if let prev = activeSourceIndex, prev != index {
                        let btn = menuBarStatusItems[prev]?.button
                        btn?.isHighlighted = false
                        btn?.state = .off
                    }
                    activeSourceIndex = index
                    coordinator.activeSourceIndex = index
                } else {
                    let btn = menuBarStatusItems[index]?.button
                    btn?.isHighlighted = false
                    btn?.state = .off
                    if activeSourceIndex == index {
                        activeSourceIndex = nil
                        coordinator.activeSourceIndex = nil
                    }
                }
            }
        )
    }
}

// MARK: - Array safe subscript

private extension Array {
    /// Returns the element at `index`, or `nil` if the index is out of bounds.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - AppDelegate

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
