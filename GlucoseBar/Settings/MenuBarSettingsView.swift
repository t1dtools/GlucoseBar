//
//  MenuBarSettings.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-03.
//

import Foundation
import SwiftUI

struct MenuBarSettingsView: View {

    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose
    @Environment(\.colorScheme) private var colorScheme

    @State private var focusedMenuBarItemID: MenuBarItemContainer.ID? = nil
    @State private var menuBarItems: [MenuBarItemContainer] = []
    @State private var menuBarItemsInverse: [MenuBarItemContainer] = []
    @State private var menuBarItemSpacing: CGFloat = 8

    private func loadMenuBarItems() {
        menuBarItemSpacing = s.menuBarItemSpacing

        if s.menuBarItems.count > 0 {
            var seen: Set<MenuBarItem> = []
            self.menuBarItems = []
            for item in s.menuBarItems {
                if item.type == .separator {
                    self.menuBarItems.append(item)
                } else if !seen.contains(item.type) {
                    self.menuBarItems.append(item)
                    seen.insert(item.type)
                }
            }
        } else {
            // Defaults
            let defaultItems = [
                MenuBarItemContainer.init(type: .glucosevalue),
                MenuBarItemContainer.init(type: .glucosetrend),
                MenuBarItemContainer.init(type: .glucosedelta)
            ]


            self.menuBarItems = defaultItems

        }

        // Always rebuild inverse list from current menuBarItems
        self.menuBarItemsInverse.removeAll()
        let currentTypes: Set<MenuBarItem> = Set(self.menuBarItems.map { $0.type })
        for p in MenuBarItem.allCases where p != .separator {
            // Filter out fields we don't have if aid integration or nightscout is false
            if (!s.aidEnableIntegration || s.cgmProvider != .nightscout) && [.loopstatus, .eventualglucose, .cob, .iob].contains(p) {
                continue
            }

            // Filter out fields we don't know about from Loop
            if g.provider.GlucoseSourceExtras.aid == .loop && [.loopstatus, .eventualglucose].contains(p) {
                continue
            }

            if !currentTypes.contains(p) {
                self.menuBarItemsInverse.append(MenuBarItemContainer(type: p))
            }
        }
    }

    private func addViewToMenuBar(item: MenuBarItem) {
        let container = MenuBarItemContainer(type: item)
        menuBarItems.append(container)
        menuBarItemsInverse.count > 0 ? menuBarItemsInverse.removeAll { $0.type == item } : ()
        focusedMenuBarItemID = container.id
    }

    private func focusMenuBarItem(_ item: MenuBarItemContainer) {
        if focusedMenuBarItemID == item.id {
            focusedMenuBarItemID = nil
        } else {
            focusedMenuBarItemID = item.id
        }
    }

    private func removeViewFromMenuBar(_ item: MenuBarItemContainer) {
        menuBarItems.count > 0 ? menuBarItems.removeAll { $0 == item } : ()
        if item.type != .separator && !menuBarItemsInverse.contains(where: { $0.type == item.type }) {
            menuBarItemsInverse.append(MenuBarItemContainer(type: item.type))
        }
        focusedMenuBarItemID = nil
    }

    private func focusedContainer() -> MenuBarItemContainer? {
        guard let id = focusedMenuBarItemID else { return nil }
        return menuBarItems.first(where: { $0.id == id })
    }

    @ViewBuilder
    func drawMenuBarItem(_ item: MenuBarItemContainer) -> some View {
        Group {
            switch item.type {
            case .glucosevalue:
                GlucoseValueView(viewSettings: item)
                    .opacity(focusedMenuBarItemID != nil && focusedMenuBarItemID != item.id ? 0.4 : 1)
            case .glucosetrend:
                GlucoseTrendView(viewSettings: item)
                    .opacity(focusedMenuBarItemID != nil && focusedMenuBarItemID != item.id ? 0.4 : 1)
            case .glucosedelta:
                GlucoseDeltaView(viewSettings: item)
                    .opacity(focusedMenuBarItemID != nil && focusedMenuBarItemID != item.id ? 0.4 : 1)
            case .glucosedot:
                ZenModeView()
                    .opacity(focusedMenuBarItemID != nil && focusedMenuBarItemID != item.id ? 0.4 : 1)

            case .loopstatus:
                LoopStatusView(viewSettings: item)
                    .opacity(focusedMenuBarItemID != nil && focusedMenuBarItemID != item.id ? 0.4 : 1)
            case .eventualglucose:
                EventualGlucoseView(viewSettings: item)
                    .opacity(focusedMenuBarItemID != nil && focusedMenuBarItemID != item.id ? 0.4 : 1)
            case .cob:
                COBView(viewSettings: item, isSettings: true)
                    .opacity(focusedMenuBarItemID != nil && focusedMenuBarItemID != item.id ? 0.4 : 1)
            case .iob:
                IOBView(viewSettings: item)
                    .opacity(focusedMenuBarItemID != nil && focusedMenuBarItemID != item.id ? 0.4 : 1)

            case MenuBarItem.separator:
                SeparatorView(viewSettings: item)
                    .opacity(focusedMenuBarItemID != nil && focusedMenuBarItemID != item.id ? 0.4 : 1)
            }
        }
            .frame(height: 24)
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
        case .glucosedot:
            ZenModeSettingsView()

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
            HStack(spacing: menuBarItemSpacing) {
                Spacer()
                ReorderableForEach($menuBarItems) { item, isDragged in
                    let viewImageRenderer = ImageRenderer(content: drawMenuBarItem(item)
                        .fixedSize()
                        .font(.system(size: 26))
                        .padding(.horizontal, 4)
                        .environmentObject(s)
                        .environmentObject(g)
                        .environment(\.colorScheme, colorScheme == .light ? .light : .dark)
                    )
                    if let viewImage = viewImageRenderer.cgImage {
                        Image(viewImage, scale: 2, label: Text("")).onTapGesture {
                            focusMenuBarItem(item)
                        }.help(item.type.name)
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.init("menuitemsettingchange"))) { _ in
                            loadMenuBarItems()
                        }
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

                    Button("Save") {
                        s.menuBarItems = menuBarItems
                        s.menuBarItemSpacing = menuBarItemSpacing
                        s.save()
                    }
                }.padding(.top, 5).padding(.trailing)

                menubarPreview.frame(height: 24)
                    .padding(.horizontal, 10)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .background(Color.gray).opacity(0.1)
                    ).onTapGesture {
                        if let item = focusedContainer() {
                            focusMenuBarItem(item)
                        }
                    }.padding(5)


                if let fc = focusedContainer() {
                    GroupBox {
                        HStack {
                            Text("\(fc.type.name) Settings").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                            Spacer()
                            Button(action: {
                                removeViewFromMenuBar(fc)
                            }) {
                                Image(systemName: "trash.fill")
                            }.help("Remove \(fc.type.name)")
                        }.padding(.horizontal).padding(.top, 5)
                        drawMenuBarItemSettings(fc)
                            .id(fc.id)
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                    }.padding(.horizontal).padding(.vertical, 10)
                } else {
                    Text("Click to edit, or drag to reorder items.").font(.footnote).frame(alignment: .trailing)
                }

            }.padding(.horizontal)

            Text("Global Settings").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top)
            GroupBox {
                HStack {
                    Text("Item Spacing")
                    Spacer()
                    Picker("", selection: $menuBarItemSpacing) {
                        Text("Very Narrow").tag(CGFloat(-2))
                        Text("Narrow").tag(CGFloat(3))
                        Text("Default").tag(CGFloat(8))
                        Text("Wide").tag(CGFloat(13))
                        Text("Very Wide").tag(CGFloat(18))
                    }.frame(width: 200, alignment: .trailing)
                }.padding(.horizontal).padding(.vertical, 10)
            }.padding(.horizontal)
        }.onAppear {
            loadMenuBarItems()
        }
    }
}
