//
//  ChartSettings.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-03.
//

import Foundation
import SwiftUI
import Charts

struct ChartSettingsView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    func createMockGlucoseData(scheme: GlucoseColorScheme) -> [GraphEntry] {
        let range = 0..<60
        let amplitude: Double = 75     // Half of the peak-to-peak range (e.g., (200 - 70) / 2)
        let midline: Double = 125      // Midpoint of the range (e.g., (200 + 70) / 2)
        let frequency: Double = 2    // Number of complete sine wave cycles

        var entries: [GraphEntry] = []
        for i in range {
            let date = Date().addingTimeInterval(TimeInterval(i * 5 * 60))

            let x = Double(i) / Double(range.count) // Normalized 0 to 1
            let sine = sin(2 * .pi * frequency * x) // 2 full sine cycles
            let value = midline + amplitude * sine  // Scale to desired glucose range

            let color = getDynamicGlucoseColor(glucoseValue: Decimal(value), highGlucoseColorValue: 180, lowGlucoseColorValue: 70, targetGlucose: Decimal(90), glucoseColorScheme: scheme)
            entries.append(GraphEntry(date: date, value: value, trend: .notComputable, delta: 0, color: color, forecastType: .none, glucoseType: .sensor))
        }

        return entries
    }

    var mockGlucoseDataStatic: [GraphEntry] = []
    var mockGlucoseDataDynamic: [GraphEntry] = []

    init() {
        mockGlucoseDataStatic = createMockGlucoseData(scheme: .staticColor)
        mockGlucoseDataDynamic = createMockGlucoseData(scheme: .dynamicColor)
    }

    struct exampleChart: View {
        let data: [GraphEntry]
        let scheme: GlucoseColorScheme
        let showTarget: Bool
        let showHighThreshold: Bool
        let showLowThreshold: Bool

        var body: some View {
            Chart {
                if scheme == .staticColor {
                    if showHighThreshold {
                        RuleMark(y: .value("High", 180)).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                    if showLowThreshold {
                        RuleMark(y: .value("Low", 70)).foregroundStyle(.red).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                } else if scheme == .dynamicColor {
                    if showHighThreshold {
                        RuleMark(y: .value("High", 180)).foregroundStyle(dynamicPurple).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                    if showLowThreshold {
                        RuleMark(y: .value("Low", 70)).foregroundStyle(dynamicRed).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                }

                if showTarget {
                    RuleMark(y: .value("Target", 100)).foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1))
                }

                DrawGlucose(data: data)
            }.chartLegend(.hidden)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .padding()
                .padding(.bottom, -20)
        }
    }

    var body: some View {
        ScrollView {
            VStack {
                Text("Glucose Chart Color Scheme", comment: "The headline used for selecting chart color scheme in the chart settings view").font(.headline).frame(maxWidth: .infinity, alignment: .leading)

                GroupBox {
                    HStack {
                        VStack {
                            Picker("", selection: $s.glucoseColorScheme) {
                                Group {
                                    VStack {
                                        HStack {
                                            Text("\(GlucoseColorScheme.dynamicColor.displayName)").frame(alignment: .leading).padding(.leading, 4)
                                            Spacer()
                                        }
                                        exampleChart(data: mockGlucoseDataDynamic, scheme: .dynamicColor, showTarget: s.showTarget, showHighThreshold: s.showHighThreshold, showLowThreshold: s.showLowThreshold).frame(height: 100)
                                    }
                                }.tag(GlucoseColorScheme.dynamicColor)
                                Group {
                                    VStack {
                                        HStack {
                                            Text("\(GlucoseColorScheme.staticColor.displayName)").frame(alignment: .leading).padding(.leading, 4)
                                            Spacer()
                                        }
                                        exampleChart(data: mockGlucoseDataStatic, scheme: .staticColor, showTarget: s.showTarget, showHighThreshold: s.showHighThreshold, showLowThreshold: s.showLowThreshold).frame(height: 100)
                                    }
                                }.tag(GlucoseColorScheme.staticColor)
                            }.pickerStyle(.radioGroup)
                                .horizontalRadioGroupLayout()
                                .onChange(of: s.glucoseColorScheme) {
                                    s.save()
                                }
                        }.padding()
                        Spacer()
                    }
                }

                Text("Chart Options", comment: "The headline used for the box containing chart options").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top)
                GroupBox {
                    VStack {
                        HStack {
                            Text("Show High Threshold Line", comment: "Label of the toggle to show the high glucose threshold line on the chart")
                            Spacer()
                            Toggle(isOn: $s.showHighThreshold, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.showHighThreshold, initial: true) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }
                        Divider()
                        HStack {
                            Text("Show Low Threshold Line", comment: "Label of the toggle to show the low glucose threshold line on the chart")
                            Spacer()
                            Toggle(isOn: $s.showLowThreshold, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.showLowThreshold, initial: true) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }
                        Divider()
                        HStack {
                            Text("Show Target Line", comment: "Label of the toggle to show target line on the chart")
                            Spacer()
                            Toggle(isOn: $s.showTarget, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.showTarget, initial: true) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }
                    }.padding()
                }
            }.padding()
        }
    }
}
