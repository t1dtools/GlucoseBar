//
//  SymbolPickerView.swift
//  GlucoseBar
//

import SwiftUI

/// A curated grid of SF Symbol names plus preset colour swatches for the source icon.
///
/// Reads and writes directly to the injected `SettingsStore`, calling `s.save()`
/// after each change so the menu bar label updates immediately.
struct SymbolPickerView: View {
    @EnvironmentObject var s: SettingsStore

    private let symbols: [String] = [
        "person.fill", "person.2.fill", "figure.walk", "figure.child",
        "figure.child.circle.fill", "heart.fill", "heart.circle.fill",
        "drop.fill", "drop.circle.fill", "star.fill", "moon.fill",
        "sun.max.fill", "bolt.fill", "pawprint.fill", "leaf.fill",
        "flame.fill", "waveform.path.ecg", "cross.case.fill",
        "medical.thermometer.fill", "bandage.fill",
    ]

    private struct PresetColor {
        let name: String
        let codable: CodableColor
    }

    private let presetColors: [PresetColor] = [
        PresetColor(name: "White",      codable: CodableColor(red: 1.000, green: 1.000, blue: 1.000)),
        PresetColor(name: "Light Gray", codable: CodableColor(red: 0.750, green: 0.750, blue: 0.750)),
        PresetColor(name: "Red",        codable: CodableColor(red: 1.000, green: 0.231, blue: 0.188)),
        PresetColor(name: "Orange",     codable: CodableColor(red: 1.000, green: 0.584, blue: 0.000)),
        PresetColor(name: "Yellow",     codable: CodableColor(red: 1.000, green: 0.800, blue: 0.000)),
        PresetColor(name: "Green",      codable: CodableColor(red: 0.204, green: 0.780, blue: 0.349)),
        PresetColor(name: "Teal",       codable: CodableColor(red: 0.353, green: 0.784, blue: 0.784)),
        PresetColor(name: "Blue",       codable: CodableColor(red: 0.000, green: 0.478, blue: 1.000)),
        PresetColor(name: "Purple",     codable: CodableColor(red: 0.686, green: 0.322, blue: 0.871)),
        PresetColor(name: "Pink",       codable: CodableColor(red: 1.000, green: 0.176, blue: 0.333)),
    ]

    private let symbolColumns = [GridItem(.adaptive(minimum: 36, maximum: 36), spacing: 8)]
    private let colorColumns  = [GridItem(.adaptive(minimum: 28, maximum: 28), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Live preview at menu bar icon size
            HStack(spacing: 8) {
                Image(systemName: s.iconSymbol)
                    .font(.system(size: 22))
                    .foregroundStyle(s.iconColor.color)
                Text("Preview")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            // Symbol grid
            LazyVGrid(columns: symbolColumns, alignment: .leading, spacing: 8) {
                ForEach(symbols, id: \.self) { symbol in
                    Button {
                        s.iconSymbol = symbol
                        s.save()
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 18))
                            .frame(width: 32, height: 32)
                            .background(
                                s.iconSymbol == symbol
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        s.iconSymbol == symbol ? Color.accentColor : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Colour swatches
            Text("Icon colour")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: colorColumns, alignment: .leading, spacing: 8) {
                ForEach(presetColors, id: \.name) { preset in
                    Button {
                        s.iconColor = preset.codable
                        s.save()
                    } label: {
                        ZStack {
                            // Selection ring
                            Circle()
                                .stroke(
                                    s.iconColor == preset.codable ? Color.accentColor : Color.clear,
                                    lineWidth: 2
                                )
                                .frame(width: 28, height: 28)

                            // Colour fill + subtle border for light colours
                            Circle()
                                .fill(preset.codable.color)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                        }
                        .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }
            }
        }
    }
}
