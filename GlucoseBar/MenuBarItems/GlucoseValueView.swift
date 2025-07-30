//
//  GlucoseValueView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import SwiftUI

struct GlucoseValueView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    @Environment(\.colorScheme) private var colorScheme

    var viewSettings: [String: Any]?

    @ViewBuilder
    var body: some View {

        HStack {
            if viewSettings?["icon"] as? String != "hidden" && viewSettings?["iconLocation"] as? String == "beforeGlucoseValue" {
                drawIcon()
            }

            Text("\(formatGlucoseForDisplay(settings: s, glucose: g.glucose))")
                .fontWeight(getFontWeight())
                .foregroundStyle(getForegroundStyle())

            if viewSettings?["icon"] as? String != "hidden" && viewSettings?["iconLocation"] as? String == "afterGlucoseValue" {
                drawIcon()
            }
        }
    }

    func getFontWeight() -> Font.Weight {
        if viewSettings?["fontWeight"] as? String == "light" {
            return .light
        }

        if viewSettings?["fontWeight"] as? String == "bold" {
            return .bold
        }


        return .regular
    }

    func getForegroundStyle() -> Color {
        if viewSettings?["textColor"] as? String == "Static Glucose Color" {
            return getDynamicGlucoseColor(glucoseValue: Decimal(g.glucose), highGlucoseColorValue: 180, lowGlucoseColorValue: 70, targetGlucose: Decimal(90), glucoseColorScheme: .dynamicColor)
        }

        if viewSettings?["textColor"] as? String == "Dynamic Glucose Color" {
            return getDynamicGlucoseColor(glucoseValue: Decimal(g.glucose), highGlucoseColorValue: 180, lowGlucoseColorValue: 70, targetGlucose: Decimal(90), glucoseColorScheme: .staticColor)
        }

        if colorScheme == .dark {
            return .white
        }

        return .black
    }

    func drawIcon() -> some View {
        let iconColor = viewSettings?["icon"] as? String
        var color: Color = .black

        if iconColor == "singleColor" {
            if colorScheme == .dark {
                color = .white
            }
        } else if iconColor == "dynamicColor" {
            color = getDynamicGlucoseColor(glucoseValue: Decimal(g.glucose), highGlucoseColorValue: 180, lowGlucoseColorValue: 70, targetGlucose: Decimal(90), glucoseColorScheme: .dynamicColor)
        } else if iconColor == "staticColor" {
            color = getDynamicGlucoseColor(glucoseValue: Decimal(g.glucose), highGlucoseColorValue: 180, lowGlucoseColorValue: 70, targetGlucose: Decimal(90), glucoseColorScheme: .staticColor)
        }

        var image = "drop.halffull"
        if g.glucose > 180 {
            image = "drop.fill"
        } else if g.glucose < 70 {
            image = "drop"
        }

        return Image(systemName: image).foregroundStyle(color)
    }
}
