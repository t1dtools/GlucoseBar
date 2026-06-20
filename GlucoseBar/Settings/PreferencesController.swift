import SwiftUI

@MainActor
final class PreferencesController {
    static let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("Tools.T1D.GlucoseBar.SettingsWindow")

    init() {
        setupWindowObserver()
    }

    private func setupWindowObserver() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            let window = notification.object as? NSWindow
            Task { @MainActor in
                guard let window else { return }
                if self.isSettingsWindow(window) {
                    self.configureSettingsWindow(window)
                }
            }
        }
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier == Self.settingsWindowIdentifier ||
        String(describing: type(of: window)).contains("AppKitWindow")
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        window.collectionBehavior = [.moveToActiveSpace]
        window.identifier = Self.settingsWindowIdentifier
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}
