//
//  LoopStatusSettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-26.
//

import SwiftUI

struct LoopStatusSettingsView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    @State private var display: settingValue?
    @State private var color: settingValue?
    @State private var fontWeight: settingValue?
    @State private var showIcon: settingValue?
    @State private var iconPlacement: settingValue?

    @ObservedObject var itemSettings: MenuBarItemContainer

    init(viewSettings: MenuBarItemContainer?) {

        if viewSettings != nil {
            _itemSettings = ObservedObject(initialValue: viewSettings!)
        } else {
            let container = MenuBarItemContainer(type: .loopstatus)
            _itemSettings = ObservedObject(initialValue: container)
        }

        _display = State(initialValue: itemSettings.get(.displayTextAndIcon))
        _color = State(initialValue: itemSettings.get(.textColor))
        _fontWeight = State(initialValue: itemSettings.get(.fontWeight))
        _showIcon = State(initialValue: itemSettings.get(.icon))
        _iconPlacement = State(initialValue: itemSettings.get(.iconPlacement))
    }

    @MainActor @ViewBuilder
    var body: some View {
        Grid {
            GridRow {
                Text("Display").frame(width: 150, alignment: .leading)
                Spacer()
                Picker("", selection: $display) {
                    Text("Time Since Loop Only").tag(settingValue.displayText)
                    Text("Loop Icon Only").tag(settingValue.displayIcon)
                    Text("Loop Icon and Time Since Loop").tag(settingValue.displayBoth)
                }.onChange(of: display ?? .displayBoth) { _, newVal in
                    itemSettings.set(.displayTextAndIcon, newVal)
                }.frame(width: 200)
            }

            if display == .displayBoth || display == .displayText {
                GridRow {
                    Text("Text Color").frame(width: 150, alignment: .leading)
                    Spacer()
                    Picker("", selection: $color) {
                        Text("Default").tag(settingValue.textColorDefault)
                        Text("Static Glucose Color").tag(settingValue.textColorStaticGlucose)
                        Text("Dynamic Glucose Color").tag(settingValue.textColorDynamicGlucose)
                    }.onChange(of: color ?? .textColorDefault) { _, newVal in
                        itemSettings.set(.textColor, newVal)
                    }.frame(width: 200)
                }
                GridRow {
                    Text("Font Weight").frame(width: 150, alignment: .leading)
                    Spacer()
                    Picker("", selection: $fontWeight) {
                        Text("Light").tag(settingValue.fontWeightLight)
                        Text("Regular").tag(settingValue.fontWeightRegular)
                        Text("Bold").tag(settingValue.fontWeightBold)
                    }.onChange(of: fontWeight ?? .fontWeightRegular) { _, newVal in
                        itemSettings.set(.fontWeight, newVal)
                    }.frame(width: 200)
                }
            }

            if display == .displayBoth || display == .displayIcon {
                GridRow {
                    Text("Icon Location").frame(width: 150, alignment: .leading)
                    Spacer()
                    Picker("", selection: $iconPlacement) {
                        Text("Before Glucose Value").tag(settingValue.iconPlacementLeading)
                        Text("After Glucose Value").tag(settingValue.iconPlacementTrailing)
                    }.onChange(of: iconPlacement ?? .iconPlacementLeading) { _, newVal in
                        itemSettings.set(.iconPlacement, newVal)
                    }.frame(width: 200)
                }
            }
        }
    }
}

