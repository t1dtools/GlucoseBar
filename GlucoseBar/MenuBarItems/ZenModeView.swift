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
            drawIcon()
        }.frame(alignment: .leading)
    }

    func drawIcon() -> some View {
        let glucoseColor = getDynamicGlucoseColor(glucoseValue: Decimal(g.glucose), highGlucoseColorValue: Decimal(s.highThreshold), lowGlucoseColorValue: Decimal(s.lowThreshold), targetGlucose: Decimal(s.glucoseTarget), glucoseColorScheme: .dynamicColor)
        var strikeColor = glucoseColor
        var icon = "circle.fill"
        if g.glucoseTime.timeIntervalSinceNow < -360 {
            icon = "circle.slash"
            strikeColor = .red
        }

        return Image(systemName: icon)
            .foregroundStyle(strikeColor, glucoseColor)
            .font(.system(size: 26))
            .fontWeight(.heavy)
            .offset(y: 1)
    }
}

