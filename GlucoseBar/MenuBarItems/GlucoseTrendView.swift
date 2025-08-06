//
//  GlucoseTrendView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import SwiftUI

struct GlucoseTrendView: View {
    @EnvironmentObject var g: Glucose
    @EnvironmentObject var s: SettingsStore

    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewSettings: MenuBarItemContainer

    @ViewBuilder
    var body: some View {
        Text("\(g.trend)")
            .fontWeight(getFontWeight())
            .foregroundStyle(getForegroundStyle())
    }

    func getFontWeight() -> Font.Weight {
        if viewSettings.get(.fontWeight) == .fontWeightLight {
            return .light
        }

        if viewSettings.get(.fontWeight) == .fontWeightBold {
            return .bold
        }


        return .regular
    }

    func getForegroundStyle() -> Color {
        if viewSettings.get(.textColor) == .textColorStaticGlucose {
            return getDynamicGlucoseColor(glucoseValue: Decimal(g.glucose), highGlucoseColorValue: Decimal(s.highThreshold), lowGlucoseColorValue: Decimal(s.lowThreshold), targetGlucose: Decimal(s.glucoseTarget), glucoseColorScheme: .staticColor)
        }

        if viewSettings.get(.textColor) == .textColorDynamicGlucose {
            return getDynamicGlucoseColor(glucoseValue: Decimal(g.glucose), highGlucoseColorValue: Decimal(s.highThreshold), lowGlucoseColorValue: Decimal(s.lowThreshold), targetGlucose: Decimal(s.glucoseTarget), glucoseColorScheme: .dynamicColor)
        }

        if colorScheme == .dark {
            return .white
        }

        return .black
    }
}
