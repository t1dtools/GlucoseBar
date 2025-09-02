//
//  IOBView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import SwiftUI

struct IOBView: View {
    @EnvironmentObject var g: Glucose
    @EnvironmentObject var s: SettingsStore

    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewSettings: MenuBarItemContainer

    @MainActor @ViewBuilder
    var body: some View {
        HStack {

            if viewSettings.get(.icon) != .iconColorHidden && viewSettings.get(.iconPlacement) == .iconPlacementLeading {
                drawIcon()
            }

            if let iob = g.provider.GlucoseSourceExtras.iob {
                Text(formatIOBForDisplay(iob: iob) + " U")
                    .foregroundStyle(getForegroundStyle())
                    .fontWeight(getFontWeight())
                    .strikethrough(g.glucoseTime.timeIntervalSinceNow < -360, color: .red)
            } else {
                Text("-")
                    .foregroundStyle(getForegroundStyle())
                    .fontWeight(getFontWeight())
                    .strikethrough(g.glucoseTime.timeIntervalSinceNow < -360, color: .red)
            }

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
        } else if iconColor == .iconColorBlue {
            color = .blue
        }

        return Image(systemName: "syringe.fill").foregroundStyle(color)
    }
}
