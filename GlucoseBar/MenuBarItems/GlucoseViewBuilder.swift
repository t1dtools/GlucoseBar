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
                GlucoseValueView().environmentObject(s).environmentObject(g)
            case .glucosetrend:
                GlucoseTrendView().environmentObject(s).environmentObject(g)
            case .glucosedelta:
                GlucoseDeltaView().environmentObject(s).environmentObject(g)

            case .loopstatus:
                LoopStatusView().environmentObject(s).environmentObject(g)
            case .eventualglucose:
                EventualGlucoseView().environmentObject(s).environmentObject(g)
            case .cob:
                COBView().environmentObject(s).environmentObject(g)
            case .iob:
                IOBView().environmentObject(s).environmentObject(g)

            case MenuBarItem.separator:
                SeparatorView().environmentObject(s)
            }
        }.environment(\.colorScheme, colorScheme == .light ? .light : .dark)
    }

    var menuStack: any View {
        HStack {
            ForEach(menuBarItems, id: \.id) { item in
                drawMenuBarItem(item)
            }
        }
    }

    var body: some View {
        let r = ImageRenderer(content: AnyView(menuStack))
        let menuBarImage = r.nsImage
        Group {
            if menuBarImage != nil {
                Image(nsImage: menuBarImage!)
            } else {
                Image(systemName: "questionmark.circle.dashed")
            }
        }.onAppear {
            loadMenuBarItems()
        }
    }
}
