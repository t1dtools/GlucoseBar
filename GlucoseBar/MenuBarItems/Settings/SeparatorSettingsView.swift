//
//  SeparatorSettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-08-05.
//

import SwiftUI

struct SeparatorSettingsView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    @State private var color: settingValue?
    @State private var fontWeight: settingValue?
    @State private var character: settingValue?

    @ObservedObject var itemSettings: MenuBarItemContainer

    init(viewSettings: MenuBarItemContainer?) {

        if let viewSettings = viewSettings {
            _itemSettings = ObservedObject(initialValue: viewSettings)
        } else {
            let container = MenuBarItemContainer(type: .separator)
            _itemSettings = ObservedObject(initialValue: container)
        }

        _color = State(initialValue: itemSettings.get(.textColor))
        _fontWeight = State(initialValue: itemSettings.get(.fontWeight))
        _character = State(initialValue: itemSettings.get(.character))
    }

    @MainActor @ViewBuilder
    var body: some View {
        Grid {
            GridRow {
                Text("Symbol").frame(width: 150, alignment: .leading)
                Spacer()
                Picker("", selection: $character) {
                    Text("|").tag(settingValue.separatorCharPipe)
                    Text("-").tag(settingValue.separatorCharDash)
                    Text("•").tag(settingValue.separatorCharDot)
                    Text("/").tag(settingValue.separatorCharSlash)
                    Text("\\").tag(settingValue.separatorCharBackslash)
                }.onChange(of: character ?? .separatorCharPipe) { _, newVal in
                    itemSettings.set(.character, newVal)
                }.frame(width: 200).pickerStyle(SegmentedPickerStyle())
            }
            GridRow {
                Text("Separator Color").frame(width: 150, alignment: .leading)
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
                Text("Weight").frame(width: 150, alignment: .leading)
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
    }
}
