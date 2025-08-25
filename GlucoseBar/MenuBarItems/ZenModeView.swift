//
//  ZenModeView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-08-22.
//


import SwiftUI

struct ZenModeView: View {
    @EnvironmentObject var g: Glucose
    @EnvironmentObject var s: SettingsStore

    @Environment(\.colorScheme) private var colorScheme


    @MainActor @ViewBuilder
    var body: some View {
        HStack {
            drawIcon().padding(.top, 3)
        }.frame(alignment: .leading)
    }

    func drawIcon() -> some View {
        let color = getDynamicGlucoseColor(glucoseValue: Decimal(g.glucose), highGlucoseColorValue: Decimal(s.highThreshold), lowGlucoseColorValue: Decimal(s.lowThreshold), targetGlucose: Decimal(s.glucoseTarget), glucoseColorScheme: .dynamicColor)

        return Image(systemName: "circle.fill")
            .foregroundColor(color)
            .fontWeight(.heavy)
    }
}

