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

    @ObservedObject var viewSettings: MenuBarItemContainer

    @ViewBuilder
    var body: some View {

        HStack(spacing: s.menuBarItemSpacing) {
            if viewSettings.get(.icon) != .iconColorHidden && viewSettings.get(.iconPlacement) == .iconPlacementLeading {
                drawIcon()
            }

            Text("\(formatGlucoseForDisplay(settings: s, glucose: g.glucose))")
                .fontWeight(getFontWeight())
                .foregroundStyle(getForegroundStyle())
                .strikethrough(g.glucoseTime.timeIntervalSinceNow < -360, color: .red)

            if viewSettings.get(.icon) != .iconColorHidden && viewSettings.get(.iconPlacement) == .iconPlacementTrailing {
                drawIcon()
            }
        }
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

    func drawIcon() -> some View {
        let iconColor = viewSettings.get(.icon)
        var color: Color = .black

        if iconColor == .iconColorSingle {
            if colorScheme == .dark {
                color = .white
            }
        } else if iconColor == .iconColorDynamicGlucose {
            color = getDynamicGlucoseColor(glucoseValue: Decimal(g.glucose), highGlucoseColorValue: Decimal(s.highThreshold), lowGlucoseColorValue: Decimal(s.lowThreshold), targetGlucose: Decimal(s.glucoseTarget), glucoseColorScheme: .dynamicColor)
        } else if iconColor == .iconColorStaticGlucose {
            color = getDynamicGlucoseColor(glucoseValue: Decimal(g.glucose), highGlucoseColorValue: Decimal(s.highThreshold), lowGlucoseColorValue: Decimal(s.lowThreshold), targetGlucose: Decimal(s.glucoseTarget), glucoseColorScheme: .staticColor)
        }

        var image = "drop.halffull"
        if g.glucose >= s.highThreshold {
            image = "drop.fill"
        } else if g.glucose <= s.lowThreshold {
            image = "drop"
        }

        return Image(systemName: image).foregroundStyle(color)
    }
}
