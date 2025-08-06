//
//  IOSettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-08-05.
//

import SwiftUI

struct IOBSettingsView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    @State private var color: settingValue?
    @State private var fontWeight: settingValue?
    @State private var showIcon: settingValue?
    @State private var iconPlacement: settingValue?

    @ObservedObject var itemSettings: MenuBarItemContainer

    init(viewSettings: MenuBarItemContainer?) {

        if viewSettings != nil {
            _itemSettings = ObservedObject(initialValue: viewSettings!)
        } else {
            let container = MenuBarItemContainer(type: .iob)
            _itemSettings = ObservedObject(initialValue: container)
        }

        _color = State(initialValue: itemSettings.get(.textColor))
        _fontWeight = State(initialValue: itemSettings.get(.fontWeight))
        _showIcon = State(initialValue: itemSettings.get(.icon))
        _iconPlacement = State(initialValue: itemSettings.get(.iconPlacement))
    }

    @MainActor @ViewBuilder
    var body: some View {
        Grid {
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
            GridRow {
                Text("Icon").frame(width: 150, alignment: .leading)
                Spacer()
                Picker("", selection: $showIcon) {
                    Text("Hidden").tag(settingValue.iconColorHidden)
                    Text("Default Color").tag(settingValue.iconColorSingle)
                    Text("Insulin Blue Color").tag(settingValue.iconColorSingle)
                    Text("Static Glucose Color").tag(settingValue.iconColorStaticGlucose)
                    Text("Dynamic Glucose Color").tag(settingValue.iconColorDynamicGlucose)
                }.onChange(of: showIcon ?? .iconColorHidden) { _, newVal in
                    itemSettings.set(.icon, newVal)
                }.frame(width: 200)
            }
            if showIcon != .iconColorHidden {
                GridRow {
                    Text("Icon Location").frame(width: 150, alignment: .leading)
                    Spacer()
                    Picker("", selection: $iconPlacement) {
                        Text("Before IOB Value").tag(settingValue.iconPlacementLeading)
                        Text("After IOB Value").tag(settingValue.iconPlacementTrailing)
                    }.onChange(of: iconPlacement ?? .iconPlacementLeading) { _, newVal in
                        itemSettings.set(.iconPlacement, newVal)
                    }.frame(width: 200)
                }
            }
        }
    }
}
