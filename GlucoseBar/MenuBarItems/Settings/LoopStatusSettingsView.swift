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

    @State private var display: String = "both"
    @State private var color: String = "Default"
    @State private var fontWeight: String = "Regular"
    @State private var showIcon: String = "no"
    @State private var iconPlacement: String = "before"

    @MainActor @ViewBuilder
    var body: some View {
        Grid {

            GridRow {
                Text("Display").frame(width: 200, alignment: .leading)
                Spacer()
                Picker("", selection: $display) {
                    Text("Time Since Loop Only").tag("text")
                    Text("Loop Icon Only").tag("icon")
                    Text("Loop Icon and Time Since Loop").tag("both")
                }.frame(width: 200)
            }

            if display == "both" || display == "text" {
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
            }
        }
    }
}

