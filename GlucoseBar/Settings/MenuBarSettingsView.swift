//
//  MenuBarSettings.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-03.
//

import Foundation
import SwiftUI
import OSLog

struct MenuBarSettingsView: View {

    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose
    @Environment(\.colorScheme) private var colorScheme

    @State private var focusedMenuBarItem: MenuBarItemContainer? = nil
    @State private var menuBarItems: [MenuBarItemContainer] = []
    @State private var menuBarItemsInverse: [MenuBarItemContainer] = []

    private func loadMenuBarItems() {

        if s.menuBarItems.count > 0 {
            var seenItems: [MenuBarItem] = []
            for item in s.menuBarItems {
                if !self.menuBarItems.contains(where: { $0 == item }) {
                    self.menuBarItems.append(item)
                    seenItems.append(item.type)
                }
            }

            for p in MenuBarItem.allCases {
                if !seenItems.contains(where: { $0 == p }) && p != .separator {
                    self.menuBarItemsInverse.append(MenuBarItemContainer.init(type: p))
                }
            }
            return
        }

        let defaultItems = [
            MenuBarItemContainer.init(type: .glucosevalue),
            MenuBarItemContainer.init(type: .glucosetrend),
            MenuBarItemContainer.init(type: .glucosedelta)
        ]
        var defaultItemsInverse: [MenuBarItemContainer] = []

        if s.trioEnableIntegration && s.cgmProvider == .nightscout {
            defaultItemsInverse.append(MenuBarItemContainer.init(type: .loopstatus))
            defaultItemsInverse.append(MenuBarItemContainer.init(type: .eventualglucose))
            defaultItemsInverse.append(MenuBarItemContainer.init(type: .cob))
            defaultItemsInverse.append(MenuBarItemContainer.init(type: .iob))
        }

        self.menuBarItems = defaultItems
        self.menuBarItemsInverse = defaultItemsInverse
    }

    private func addViewToMenuBar(item: MenuBarItem) {
        let container = MenuBarItemContainer(type: item)
        menuBarItems.append(container)
        menuBarItemsInverse.count > 0 ? menuBarItemsInverse.removeAll { $0.type == item } : ()
        focusedMenuBarItem = container
    }

    private func focusMenuBarItem(_ item: MenuBarItemContainer) {
        if focusedMenuBarItem == item {
            focusedMenuBarItem = nil
        } else {
            focusedMenuBarItem = item
        }
    }

    private func removeViewFromMenuBar(_ item: MenuBarItemContainer) {
        menuBarItems.count > 0 ? menuBarItems.removeAll { $0 == item } : ()
        if item.type != .separator {
            menuBarItemsInverse.append(item)
        }
        focusedMenuBarItem = nil
    }

    @ViewBuilder
    func drawMenuBarItem(_ item: MenuBarItemContainer) -> some View {
        VStack {
            switch item.type {
            case .glucosevalue:
                GlucoseValueView(viewSettings: item)
                    .opacity(focusedMenuBarItem != nil && focusedMenuBarItem != item ? 0.4 : 1)
            case .glucosetrend:
                GlucoseTrendView(viewSettings: item)
                    .opacity(focusedMenuBarItem != nil && focusedMenuBarItem != item ? 0.4 : 1)
            case .glucosedelta:
                GlucoseDeltaView(viewSettings: item)
                    .opacity(focusedMenuBarItem != nil && focusedMenuBarItem != item ? 0.4 : 1)

            case .loopstatus:
                LoopStatusView(viewSettings: item)
                    .opacity(focusedMenuBarItem != nil && focusedMenuBarItem != item ? 0.4 : 1)
            case .eventualglucose:
                EventualGlucoseView(viewSettings: item)
                    .opacity(focusedMenuBarItem != nil && focusedMenuBarItem != item ? 0.4 : 1)
            case .cob:
                COBView(viewSettings: item)
                    .opacity(focusedMenuBarItem != nil && focusedMenuBarItem != item ? 0.4 : 1)
            case .iob:
                IOBView(viewSettings: item)
                    .opacity(focusedMenuBarItem != nil && focusedMenuBarItem != item ? 0.4 : 1)

            case MenuBarItem.separator:
                SeparatorView(viewSettings: item)
                    .opacity(focusedMenuBarItem != nil && focusedMenuBarItem != item ? 0.4 : 1)
            }

            if focusedMenuBarItem == item {
                Image(systemName: "arrowtriangle.up.fill").foregroundStyle(.blue).frame(width: 10, height: 10)
            }
        }.padding(.top, focusedMenuBarItem == item ? 17 : 0)
    }

    @ViewBuilder
    func drawMenuBarItemSettings(_ item: MenuBarItemContainer) -> some View {
        switch item.type {
        case .glucosevalue:
            GlucoseValueSettingsView(viewSettings: item)
        case .glucosetrend:
            GlucoseTrendSettingsView(viewSettings: item)
        case .glucosedelta:
            GlucoseDeltaSettingsView(viewSettings: item)

        case .loopstatus:
            LoopStatusSettingsView(viewSettings: item)
        case .eventualglucose:
            EventualGlucoseSettingsView(viewSettings: item)
        case .cob:
            COBSettingsView(viewSettings: item)
        case .iob:
            IOBSettingsView(viewSettings: item)

        case MenuBarItem.separator:
            SeparatorSettingsView(viewSettings: item)
        }
    }

    var menu: some View {
        Menu {
            ForEach(menuBarItemsInverse) { item in
                Button(item.type.name, action: {
                    addViewToMenuBar(item: item.type)
                })
            }
            if !menuBarItemsInverse.isEmpty {
                Divider()
            }
            Button("Separator", action: {
                addViewToMenuBar(item: .separator)
            })
        } label: {
            Text("+ Add")
        }
    }

    var menubarPreview: some View {
        Group {
            HStack {
                Spacer()
                ReorderableForEach($menuBarItems) { item, isDragged in
                    let viewImageRenderer = ImageRenderer(content: drawMenuBarItem(item).environmentObject(s).environmentObject(g).environment(\.colorScheme, colorScheme == .light ? .light : .dark))
                    if let viewImage = viewImageRenderer.nsImage {
                        Image(nsImage: viewImage).onTapGesture {
                            focusMenuBarItem(item)
                        }.help(item.type.name)
                    }
                }
                Spacer()
            }
        }
    }

    var body: some View {
        ScrollView {
            Text("Menu Bar Settings").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top)

            GroupBox {
                HStack {
                    Text("Live Preview").font(.headline).padding(.leading)
                    Spacer()
                    menu.frame(width: 100)

                    // TODO: Find better placement for this button
//                    Button("Reset") {
//                        // TODO: Override settings with what's from storage
//                    }
                    Button("Save") {
                        s.menuBarItems = menuBarItems
                        s.save()
                    }
                }.padding(.top, 5).padding(.trailing)

                menubarPreview.frame(height: 24)
                    .padding(.horizontal, 10)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .background(Color.gray).opacity(0.1)
                    ).onTapGesture {
                        if let item = focusedMenuBarItem {
                            focusMenuBarItem(item)
                        }
                    }.padding(5)


                if focusedMenuBarItem != nil {
                    GroupBox {
                        HStack {
                            Text("\(focusedMenuBarItem!.type.name) Settings").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                            Spacer()
                            Button(action: {
                                removeViewFromMenuBar(focusedMenuBarItem!)
                            }) {
                                Image(systemName: "trash.fill")
                            }.help("Remove \(focusedMenuBarItem!.type.name)")
                        }.padding(.horizontal).padding(.top, 5)
                        drawMenuBarItemSettings(focusedMenuBarItem!).padding(.horizontal).padding(.vertical, 10)
                    }.padding(.horizontal).padding(.vertical, 10)
                } else {
                    Text("Click to edit, or drag to reorder items.").font(.footnote).frame(alignment: .trailing)
                }
            }.padding(.horizontal)
        }.onAppear {
            loadMenuBarItems()
        }
    }
}
