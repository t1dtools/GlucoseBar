//
//  MenuBarCoordinator.swift
//
//  Created by Andreas Stokholm on 2026-06-10.
//

import AppKit
import OSLog

/// Fixes the double-click-to-open bug that occurs when switching between
/// menu bar sources.
///
/// Root cause: when the user clicks icon M while source N is open, the
/// MenuBarExtraAccess library's `didResignKey` handler calls `window.close()`
/// directly on window N, bypassing `toggleWindow:`. This leaves
/// `WindowMenuBarExtraBehavior.isPresented` stuck at `true` for source N.
/// The next click on icon N toggles `true→false` (no-op close) instead of
/// opening, requiring a second click.
///
/// Fix: observe `NSWindow.didResignKeyNotification`. Our observer is registered
/// synchronously in `init()`, before the library's Combine-based observer (which
/// is registered inside a `Task { @MainActor }` block — asynchronously). FIFO
/// delivery guarantees we fire first. When a `MenuBarExtraWindow` fires the
/// notification while still visible (the switch case), we call `performClick` on
/// that source's status item button. This invokes `toggleWindow:` which properly
/// sets `isPresented = false`. The library's subsequent `if window.isVisible`
/// guard then evaluates to `false` and skips its `window.close()` call.
///
/// Discriminator: `window.isVisible`
/// - Switch case → window still visible when notification fires → guard passes
/// - User-toggle-close → `toggleWindow:` calls `window.close()` which hides the
///   window before `didResignKeyNotification` fires → `isVisible = false` → guard
///   rejects → no action
@MainActor
final class MenuBarCoordinator: ObservableObject {

    /// Index of the currently open source. Kept in sync by `GlucoseBarApp`
    /// whenever `activeSourceIndex` changes.
    var activeSourceIndex: Int? = nil

    /// Status items by slot index. Kept in sync by `GlucoseBarApp` from the
    /// `menuBarExtraAccess` `statusItemIntrospection` callbacks.
    var menuBarStatusItems: [Int: NSStatusItem] = [:]

    private let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "MenuBarCoordinator")
    // nonisolated(unsafe) avoids Swift 6 warning: deinit is nonisolated so it
    // cannot access @MainActor-isolated stored properties.
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        // Register synchronously so this observer fires before the library's
        // Combine-based observer (registered asynchronously via Task).
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // queue: .main guarantees main-thread execution, so assumeIsolated is safe.
            // Extract object before crossing into actor isolation to avoid Sendable warning.
            let object = notification.object as AnyObject?
            MainActor.assumeIsolated {
                self?.handleWindowDidResignKey(object)
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleWindowDidResignKey(_ object: AnyObject?) {
        guard
            let window = object as? NSWindow,
            window.isVisible,
            window.className.contains("MenuBarExtraWindow"),
            let idx = activeSourceIndex,
            let btn = menuBarStatusItems[idx]?.button
        else { return }

        logger.debug("didResignKey: fixing isPresented via performClick on slot \(idx)")
        btn.performClick(btn)
    }
}
