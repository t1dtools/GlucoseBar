//
//  StatusItemManager.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-13.
//
// The entirety of this file is initially sourced from a great blog post here: https://multi.app/blog/pushing-the-limits-nsstatusitem
// It has since been changed slightly to fit with the needs of GlucoseBar instead of those of Remotion
//


import Combine
import SwiftUI

@MainActor
final class StatusItemManager: ObservableObject {
    private var hostingView: NSHostingView<StatusItem>?
    private var statusItem: NSStatusItem?
    var popover: NSPopover?

    private var sizePassthrough = PassthroughSubject<CGSize, Never>()
    private var sizeCancellable: AnyCancellable?

    func createStatusItem(popover: NSPopover) {
        self.popover = popover
        let statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let hostingView = NSHostingView(rootView: StatusItem(sizePassthrough: sizePassthrough))
        hostingView.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        statusItem.view?.frame = hostingView.frame
        statusItem.view?.addSubview(hostingView)
        statusItem.button?.action = #selector(statusBarButtonClicked(_:))
        statusItem.button?.target = self

        self.statusItem = statusItem
        self.hostingView = hostingView

        sizeCancellable = sizePassthrough.sink { [weak self] size in
            let frame = NSRect(origin: .zero, size: .init(width: size.width, height: 24))
            self?.hostingView?.frame = frame
            self?.statusItem?.view?.frame = frame
        }
    }

    @MainActor
    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        if let btn = self.statusItem!.button {
            if self.popover!.isShown {
                self.popover?.performClose(sender)
            } else {
                self.popover?.show(relativeTo: btn.bounds, of: btn, preferredEdge: NSRectEdge.minY)
            }
        }
    }
}

private struct SizePreferenceKey: @preconcurrency PreferenceKey {
    @MainActor static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct StatusItem: View {
    var sizePassthrough: PassthroughSubject<CGSize, Never>

    @ViewBuilder
    var mainContent: some View {
        Text("Hello, world!").padding(.horizontal, 7)
            .fixedSize()
    }

    var body: some View {
        mainContent
            .overlay(
                GeometryReader { geometryProxy in
                    Color.clear
                        .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
                }
            )
            .onPreferenceChange(SizePreferenceKey.self, perform: { size in
                sizePassthrough.send(size)
            })
    }
}
