//
//  ChartSettings.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-03.
//

import Foundation
import SwiftUI

struct ChartSettingsView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    var body: some View {
        ScrollView {
            VStack {
                Text("Chart View Options").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            }.padding()

            GraphView(glucose: g).frame(width: 400, height: 500)

            

        }
    }
}
