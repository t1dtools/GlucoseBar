//
//  KeepAliveManager.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-11-30.
//

import AppKit

@MainActor
final class KeepAliveManager {
    static let shared = KeepAliveManager()

    private var keepAliveActivity: NSObjectProtocol?
    private var keepAliveWindow: NSWindow?

    private init() {
        createOffscreenVisibleWindow()
        startActivityAssertion()
        disableSuddenTermination()
    }

    private func createOffscreenVisibleWindow() {
        // Place the window off-screen so it never appears but is still a "real" window
        let offscreenRect = NSRect(x: -10000, y: -10000, width: 1, height: 1)
        let window = NSWindow(
            contentRect: offscreenRect,
            styleMask: [],
            backing: .buffered,
            defer: false
        )

        // Important: make the window visible and keep a strong reference
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.001   // effectively invisible, but visible to AppKit
        window.level = .statusBar
        window.collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        window.makeKeyAndOrderFront(nil)

        // Keep a strong reference
        self.keepAliveWindow = window
    }

    private func startActivityAssertion() {
        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.background, .latencyCritical],
            reason: "Continuous glucose monitoring"
        )
    }

    private func disableSuddenTermination() {
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    func teardown() {
        if let activity = keepAliveActivity {
            ProcessInfo.processInfo.endActivity(activity)
            keepAliveActivity = nil
        }
        keepAliveWindow?.orderOut(nil)
        keepAliveWindow = nil
        ProcessInfo.processInfo.enableSuddenTermination()
    }
}
