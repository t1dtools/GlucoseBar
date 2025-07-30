//
//  GlucoseValueSettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-26.
//

import SwiftUI

struct GlucoseValueSettingsView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    @State private var color: String = "Default"
    @State private var fontWeight: String = "Regular"
    @State private var showIcon: String = "no"
    @State private var iconPlacement: String = "before"

    @MainActor @ViewBuilder
    var body: some View {
        Grid {
            GridRow {
                Text("Text Color").frame(width: 200, alignment: .leading)
                Spacer()
                Picker("", selection: $color) {
                    Text("Default").tag("Default")
                    Text("Static Glucose Color").tag("Static Glucose Color")
                    Text("Dynamic Glucose Color").tag("Dynamic Glucose Color")
                }.frame(width: 200)
            }
            GridRow {
                Text("Font Weight").frame(width: 200, alignment: .leading)
                Spacer()
                Picker("", selection: $fontWeight) {
                    Text("Light").tag("Light")
                    Text("Regular").tag("Regular")
                    Text("Bold").tag("Bold")
                }.frame(width: 200)
            }
            GridRow {
                Text("Icon").frame(width: 200, alignment: .leading)
                Spacer()
                Picker("", selection: $showIcon) {
                    Text("Hidden").tag("no")
                    Text("Single Color").tag("single")
                    Text("Static Glucose Color").tag("static")
                    Text("Dynamic Glucose Color").tag("dynamic")
                }.frame(width: 200)
            }
            if showIcon != "no" {
                GridRow {
                    Text("Icon Location").frame(width: 200, alignment: .leading)
                    Spacer()
                    Picker("", selection: $iconPlacement) {
                        Text("Before Glucose Value").tag("before")
                        Text("After Glucose Value").tag("after")
                    }.frame(width: 200)
                }
            }
        }
    }
}

