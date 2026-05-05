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

            case MenuBarItem.separator:
                SeparatorView(viewSettings: item).environmentObject(s).environmentObject(g)
            }
        }.environment(\.colorScheme, colorScheme == .light ? .light : .dark)
    }

    var menuStack: any View {
        return HStack(spacing: s.menuBarItemSpacing) {
            ForEach(menuBarItems, id: \.id) { item in
                // aid integration only works with nightscout, so don't draw it's views for other providers
                if (s.cgmProvider != .nightscout || !s.aidEnableIntegration) && [.loopstatus, .eventualglucose, .cob, .iob].contains(item.type) {
                    EmptyView()
                // loop doesn't have quite as many bells and whistles as oref, so filter out the things we can't render
                } else if (s.cgmProvider == .nightscout && s.aidEnableIntegration && g.provider.GlucoseSourceExtras.aid == .loop && [.loopstatus, .eventualglucose].contains(item.type)) {
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

    var zenMode: any View {
        ZenModeView().environmentObject(s).environmentObject(g)
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
                // Refresh zen mode image when glucose or trend changes
                Task {
                    await MainActor.run {
                        self.cachedZenImage = generateZenModeImage()
                    }
                }
            }.onReceive(g.provider.objectWillChange) { _ in
                let now = Date()
                if now.timeIntervalSince(lastUpdateTime) > 1.0 {
                    lastUpdateTime = now
                    Task {
                        await MainActor.run {
                            self.cachedMenuImage = generateMenuBarImage()
                        }
                    }
                }
            }.onReceive(s.$menuBarItemSpacing) { _ in
                Task {
                    await MainActor.run {
                        self.cachedMenuImage = generateMenuBarImage()
                    }
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
                loadMenuBarItems()
                Task {
                    await MainActor.run {
                        self.cachedMenuImage = generateMenuBarImage()
                    }
                }
            }
            .onReceive(g.$glucose.combineLatest(g.$delta, g.$trend)) { _, _, _ in
                // Refresh menu image when glucose data changes
                let now = Date()
                if now.timeIntervalSince(lastUpdateTime) > 1.0 { // Throttle updates to max 1 per second
                    lastUpdateTime = now
                    Task {
                        await MainActor.run {
                            self.cachedMenuImage = generateMenuBarImage()
                        }
                    }
                }
            }
        }
    }
}
