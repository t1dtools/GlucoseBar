//
//  GlucoseViewBuilder.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import SwiftUI

struct MenuBarView: View {

    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose
    @EnvironmentObject var uc: UpdateChecker

    @Environment(\.colorScheme) private var colorScheme

    @State private var menuBarItems: [MenuBarItemContainer] = []
    @State private var cachedMenuImage: CGImage?
    @State private var cachedZenImage: CGImage?
    @State private var lastUpdateTime: Date = Date()

    private let imageCache = NSCache<NSString, NSImage>()

    private func loadMenuBarItems() {
        if s.menuBarItems.isEmpty {
            self.menuBarItems = [
                MenuBarItemContainer(type: .glucosedot),
                MenuBarItemContainer(type: .glucosevalue),
                MenuBarItemContainer(type: .glucosetrend),
                MenuBarItemContainer(type: .glucosedelta)
            ]
        } else {
            self.menuBarItems = s.menuBarItems
        }
    }

    private func generateMenuBarImage() -> CGImage? {
        let renderer = ImageRenderer(content: AnyView(menuStack))
        return renderer.cgImage
    }

    private func generateZenModeImage() -> CGImage? {
        let renderer = ImageRenderer(content: AnyView(zenMode))
        return renderer.cgImage
    }

    @ViewBuilder
    func drawMenuBarItem(_ item: MenuBarItemContainer) -> some View {
        Group {
            switch item.type {
            case .glucosevalue:
                GlucoseValueView(viewSettings: item).environmentObject(s).environmentObject(g)
            case .glucosetrend:
                GlucoseTrendView(viewSettings: item).environmentObject(s).environmentObject(g)
            case .glucosedelta:
                GlucoseDeltaView(viewSettings: item).environmentObject(s).environmentObject(g)
            case .glucosedot:
                ZenModeView().environmentObject(s).environmentObject(g)

            case .loopstatus:
                LoopStatusView(viewSettings: item).environmentObject(s).environmentObject(g)
            case .eventualglucose:
                EventualGlucoseView(viewSettings: item).environmentObject(s).environmentObject(g)
            case .cob:
                COBView(viewSettings: item).environmentObject(s).environmentObject(g)
            case .iob:
                IOBView(viewSettings: item).environmentObject(s).environmentObject(g)

            case .basalrate:
                BasalRateView(viewSettings: item).environmentObject(s).environmentObject(g)

            case MenuBarItem.separator:
                SeparatorView(viewSettings: item).environmentObject(s).environmentObject(g)
            }
        }.environment(\.colorScheme, colorScheme == .light ? .light : .dark)
    }

    var menuStack: any View {
        return HStack(spacing: s.menuBarItemSpacing) {
            if s.showSourceIcon {
                Image(systemName: s.iconSymbol)
                    .foregroundStyle(s.iconColor.color)
                    .font(.system(size: 22))
                    .padding(.horizontal, 4)
            }
            updateNotice()
            ForEach(menuBarItems, id: \.id) { item in
                let aid = g.provider.GlucoseSourceExtras.aid
                let hasAIDData = (s.cgmProvider == .nightscout && s.aidEnableIntegration)
                    || s.cgmProvider == .tandemsource
                    || aid != .null

                if !hasAIDData && [.loopstatus, .eventualglucose, .cob, .iob, .basalrate].contains(item.type) {
                    EmptyView()
                } else if hasAIDData && aid == .loop && [.eventualglucose].contains(item.type) {
                    EmptyView()
                } else if hasAIDData && aid == .controliq && [.eventualglucose].contains(item.type) {
                    EmptyView()
                } else if hasAIDData && aid != .controliq && [.basalrate].contains(item.type) {
                    EmptyView()
                } else {
                    drawMenuBarItem(item)
                        .fixedSize()
                        .font(.system(size: 26))
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    func updateNotice() -> some View {
        Group {
            if uc.isOutdated {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.yellow)
            }
        }
    }

    var zenMode: any View {
        HStack(spacing: s.menuBarItemSpacing) {
            updateNotice()
            ZenModeView().environmentObject(s).environmentObject(g)
        }
    }

    var body: some View {
        if s.zenMode {
            Group {
                if let cachedZenImage = cachedZenImage {
                    Image(cachedZenImage, scale: 2, label: Text(""))
                } else {
                    Image(systemName: "questionmark.circle.dashed")
                        .onAppear {
                            Task {
                                await MainActor.run {
                                    self.cachedZenImage = generateZenModeImage()
                                }
                            }
                        }
                }
            }
            .onReceive(g.$glucose.combineLatest(g.$trend)) { _, _ in
                Task { @MainActor in
                    self.cachedZenImage = generateZenModeImage()
                }
            }            .onReceive(g.provider.objectWillChange) { _ in
                Task { @MainActor in
                    let now = Date()
                    if now.timeIntervalSince(lastUpdateTime) > 1.0 {
                        lastUpdateTime = now
                        self.cachedZenImage = generateZenModeImage()
                    }
                }
            }.onReceive(s.$menuBarItemSpacing) { _ in
                Task { @MainActor in
                    self.cachedZenImage = generateZenModeImage()
                }
            }
            .onReceive(g.objectWillChange) { _ in
                Task { @MainActor in
                    self.cachedZenImage = generateZenModeImage()
                }
            }
        } else {
            Group {
                if let cachedMenuImage = cachedMenuImage {
                    Image(cachedMenuImage, scale: 2, label: Text(""))
                } else {
                    Image(systemName: "questionmark.circle.dashed")
                        .onAppear {
                            loadMenuBarItems()
                            Task {
                                await MainActor.run {
                                    self.cachedMenuImage = generateMenuBarImage()
                                }
                            }
                        }
                }
            }
            .onReceive(s.$menuBarItems) { _ in
                Task { @MainActor in
                    loadMenuBarItems()
                    self.cachedMenuImage = generateMenuBarImage()
                }
            }
            .onReceive(g.$glucose.combineLatest(g.$delta, g.$trend)) { _, _, _ in
                Task { @MainActor in
                    let now = Date()
                    if now.timeIntervalSince(lastUpdateTime) > 1.0 {
                        lastUpdateTime = now
                        self.cachedMenuImage = generateMenuBarImage()
                    }
                }
            }
            .onReceive(g.provider.objectWillChange) { _ in
                Task { @MainActor in
                    let now = Date()
                    if now.timeIntervalSince(lastUpdateTime) > 1.0 {
                        lastUpdateTime = now
                        self.cachedMenuImage = generateMenuBarImage()
                    }
                }
            }
            .onReceive(s.$menuBarItemSpacing) { _ in
                Task { @MainActor in
                    self.cachedMenuImage = generateMenuBarImage()
                }
            }
            .onReceive(g.objectWillChange) { _ in
                Task { @MainActor in
                    self.cachedMenuImage = generateMenuBarImage()
                }
            }
        }
    }
}
