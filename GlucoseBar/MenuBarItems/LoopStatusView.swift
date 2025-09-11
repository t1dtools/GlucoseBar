//
//  LoopStatusView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import SwiftUI

struct LoopStatusView: View {
    @EnvironmentObject var g: Glucose
    @EnvironmentObject var s: SettingsStore

    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewSettings: MenuBarItemContainer

    @MainActor @ViewBuilder
    var body: some View {
        HStack {

            if viewSettings.get(.displayTextAndIcon) != .displayText && viewSettings.get(.iconPlacement) == .iconPlacementLeading {
                drawIcon()
            }

            if viewSettings.get(.displayTextAndIcon) != .displayIcon {
                if let enactedAt = g.provider.GlucoseSourceExtras.enactedAt {
                    Text("\(relativeTime(time: enactedAt))")
                        .foregroundStyle(getForegroundStyle())
                        .fontWeight(getFontWeight())
                } else {
                    Text("Unknown")
                        .foregroundStyle(getForegroundStyle())
                        .fontWeight(getFontWeight())
                }
            }

            if viewSettings.get(.displayTextAndIcon) != .displayText && viewSettings.get(.iconPlacement) == .iconPlacementTrailing {
                drawIcon()
            }
        }.frame(alignment: .leading)
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
        var icon: String
        var color: Color
        let enactedAt = g.provider.GlucoseSourceExtras.enactedAt

        if let enactedAt = enactedAt {
            icon = "circle"
            color = getLoopColor(enactedAt)
        } else {
            icon = "questionmark.circle"
            color = .gray
        }

        return Image(systemName: icon)
            .foregroundColor(color)
            .fontWeight(.heavy)
    }
}

