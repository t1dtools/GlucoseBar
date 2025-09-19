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
    private var renderer: ImageRenderer<AnyView>?

    init() {
        loadRenderer()
    }

    private func loadMenuBarItems() {
        if s.menuBarItems.isEmpty {
            self.menuBarItems = [
                MenuBarItemContainer(type: .glucosevalue),
                MenuBarItemContainer(type: .glucosetrend),
                MenuBarItemContainer(type: .glucosedelta)
            ]
        } else {
            self.menuBarItems = s.menuBarItems
        }
    }

    private mutating func loadRenderer() {
        self.renderer = ImageRenderer(content: AnyView(menuStack))
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
        HStack {
            ForEach(menuBarItems, id: \.id) { item in
                // trio integration only works with nightscout, so don't draw it's views for other providers
                if s.cgmProvider != .nightscout && [.loopstatus, .eventualglucose, .cob, .iob].contains(item.type) {
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
            let r = ImageRenderer(content: AnyView(zenMode))
            let menuBarImage = r.cgImage
            Group {
                if menuBarImage != nil {
                    Image(menuBarImage!, scale: 2, label: Text(""))
                } else {
                    Image(systemName: "questionmark.circle.dashed")
                }
            }
        } else {
            let r = ImageRenderer(content: AnyView(menuStack))
            let menuBarImage = r.cgImage
            Group {
                if menuBarImage != nil {
                    Image(menuBarImage!, scale: 2, label: Text(""))
                } else {
                    Image(systemName: "questionmark.circle.dashed")
                }
            }.onAppear {
                loadMenuBarItems()
            }.onReceive(s.$menuBarItems) {_ in
                loadMenuBarItems()
            }
        }
    }
}
