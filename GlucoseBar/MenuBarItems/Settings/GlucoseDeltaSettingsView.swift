//
//  GlucoseDeltaSettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-08-05.
//

import SwiftUI

struct GlucoseDeltaSettingsView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    @State private var color: settingValue?
    @State private var fontWeight: settingValue?

    @ObservedObject var itemSettings: MenuBarItemContainer

    init(viewSettings: MenuBarItemContainer?) {

        if let viewSettings = viewSettings {
            _itemSettings = ObservedObject(initialValue: viewSettings)
        } else {
            let container = MenuBarItemContainer(type: .glucosedelta)
            _itemSettings = ObservedObject(initialValue: container)
        }

        _color = State(initialValue: itemSettings.get(.textColor))
        _fontWeight = State(initialValue: itemSettings.get(.fontWeight))
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
        }
    }
}

