//
//  COBView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import SwiftUI

struct COBView: View {
    @EnvironmentObject var g: Glucose
    @EnvironmentObject var s: SettingsStore

    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewSettings: MenuBarItemContainer
    var isSettings: Bool = false

    @MainActor @ViewBuilder
    var body: some View {
        if isSettings || (viewSettings.get(.hideZero) == .hideZeroFalse || (viewSettings.get(.hideZero) == .hideZeroTrue && g.provider.GlucoseSourceExtras.cob ?? 0 > 0)) {
            HStack {

                if viewSettings.get(.icon) != .iconColorHidden && viewSettings.get(.iconPlacement) == .iconPlacementLeading {
                    drawIcon()
                }

                if let cob = g.provider.GlucoseSourceExtras.cob {
                    Text(formatCOBForDisplay(cob: cob) + " g")
                        .foregroundStyle(getForegroundStyle())
                        .fontWeight(getFontWeight())
                        .strikethrough(g.glucoseTime.timeIntervalSinceNow < -300, color: .red)
                } else {
                    Text("-")
                        .foregroundStyle(getForegroundStyle())
                        .fontWeight(getFontWeight())
                        .strikethrough(g.glucoseTime.timeIntervalSinceNow < -300, color: .red)
                }

                if viewSettings.get(.icon) != .iconColorHidden && viewSettings.get(.iconPlacement) == .iconPlacementTrailing {
                    drawIcon()
                }
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
        } else if iconColor == .iconColorOrange {
            color = .orange
        }

        return Image(systemName: "fork.knife").foregroundStyle(color)
    }
}
