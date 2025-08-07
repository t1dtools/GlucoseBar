//
//  GeneralSettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-03.
//

import Foundation
import SwiftUI
import LaunchAtLogin
import Charts

struct GeneralSettingsView: View {
    @EnvironmentObject var s: SettingsStore

    func createMockGlucoseData(scheme: GlucoseColorScheme) -> [GraphEntry] {
        let range = 0..<60
        let amplitude: Double = 75     // Half of the peak-to-peak range (e.g., (200 - 70) / 2)
        let midline: Double = 125      // Midpoint of the range (e.g., (200 + 70) / 2)
        let frequency: Double = 2.0    // Number of complete sine wave cycles

        var entries: [GraphEntry] = []
        for i in range {
            let date = Date().addingTimeInterval(TimeInterval(i * 5 * 60))

            let x = Double(i) / Double(range.count) // Normalized 0 to 1
            let sine = sin(2 * .pi * frequency * x) // 2 full sine cycles
            let value = midline + amplitude * sine  // Scale to desired glucose range

            let color = getDynamicGlucoseColor(glucoseValue: Decimal(value), highGlucoseColorValue: 180, lowGlucoseColorValue: 70, targetGlucose: Decimal(90), glucoseColorScheme: scheme)
            entries.append(GraphEntry(date: date, value: value, trend: .notComputable, delta: 0, color: color, forecastType: .none))
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

        var body: some View {
            Chart {
                if scheme == .staticColor {
                    RuleMark(y: .value("High", 180)).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    RuleMark(y: .value("Low", 70)).foregroundStyle(.red).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                } else if scheme == .dynamicColor {
                    RuleMark(y: .value("High", 180)).foregroundStyle(dynamicPurple).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    RuleMark(y: .value("Low", 70)).foregroundStyle(dynamicRed).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
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
                Text("Glucose Options").font(.headline).frame(maxWidth: .infinity, alignment: .leading)

                GroupBox {
                    VStack {
                        HStack {
                            Text("Glucose Unit").frame(width: 120, alignment: .leading)
                            Spacer()
                            Picker("", selection: $s.glucoseUnit) {
                                ForEach(GlucoseUnit.allCases) { unit in
                                    Text(unit.presentable).tag(unit)
                                }
                            }
                        }

                        HStack {
                            Text("High Threshold").frame(width: 120, alignment: .leading)
                            Spacer()
                            VStack {
                                Slider(value: Binding(
                                    get: { s.highThreshold },
                                    set: {
                                        if $0 > s.lowThreshold {
                                            s.highThreshold = $0
                                        } else {
                                            s.highThreshold = (s.lowThreshold + 1)
                                        }
                                    }
                                ), in: 40...400) {
                                } minimumValueLabel: {
                                    Text("\(formatGlucoseForDisplay(settings: s, glucose: 40))")
                                } maximumValueLabel: {
                                    Text("\(formatGlucoseForDisplay(settings: s, glucose: 400))")
                                }.onChange(of: s.highThreshold) {
                                    s.save()
                                }
                            }.frame(width:220, alignment: .leading)
                            Spacer()
                            Text(formatGlucoseForDisplay(settings: s, glucose: s.highThreshold)).frame(width:50, alignment: .trailing)
                        }

                        HStack {
                            Text("Low Threshold").frame(width: 120, alignment: .leading)
                            Spacer()
                            VStack {
                                Slider(value: Binding(
                                    get: { s.lowThreshold },
                                    set: {
                                        if $0 < s.highThreshold {
                                            s.lowThreshold = $0
                                        } else {
                                            s.lowThreshold = (s.highThreshold - 1)
                                        }
                                    }
                                ), in: 40...400) {
                                } minimumValueLabel: {
                                    Text("\(formatGlucoseForDisplay(settings: s, glucose: 40))")
                                } maximumValueLabel: {
                                    Text("\(formatGlucoseForDisplay(settings: s, glucose: 400))")
                                }.onChange(of: s.lowThreshold) {
                                    s.save()
                                }
                            }.frame(width:220, alignment: .leading)
                            Spacer()
                            Text(formatGlucoseForDisplay(settings: s, glucose: s.lowThreshold)).frame(width:50, alignment: .trailing)
                        }

                        HStack {
                            Text("Target").frame(width: 120, alignment: .leading)
                            Spacer()
                            VStack {
                                Slider(value: Binding(
                                    get: { s.glucoseTarget },
                                    set: { s.glucoseTarget = $0 }
                                ), in: 40...400) {
                                } minimumValueLabel: {
                                    Text("\(formatGlucoseForDisplay(settings: s, glucose: 40))")
                                } maximumValueLabel: {
                                    Text("\(formatGlucoseForDisplay(settings: s, glucose: 400))")
                                }.onChange(of: s.glucoseTarget) {
                                    s.save()
                                }
                            }.frame(width:220, alignment: .leading)
                            Spacer()
                            Text(formatGlucoseForDisplay(settings: s, glucose: s.glucoseTarget)).frame(width:50, alignment: .trailing)
                        }
                        HStack {
                            Text("The target is used to correctly color the glucose values in the chart when you have it set to use dynamic colors.").font(.footnote).foregroundStyle(.gray)
                            Spacer()
                        }
                    }.padding()
                }

                Text("Glucose Chart Color Scheme").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top)
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
                                        exampleChart(data: mockGlucoseDataDynamic, scheme: .dynamicColor).frame(height: 100)
                                    }
                                }.tag(GlucoseColorScheme.dynamicColor)
                                Group {
                                    VStack {
                                        HStack {
                                            Text("\(GlucoseColorScheme.staticColor.displayName)").frame(alignment: .leading).padding(.leading, 4)
                                            Spacer()
                                        }
                                        exampleChart(data: mockGlucoseDataStatic, scheme: .staticColor).frame(height: 100)
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

                Text("Launch Behavior").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                GroupBox {
                    HStack {
                        Text("Launch at Login").frame(width: 260, alignment: .leading)
                        Spacer()
                        LaunchAtLogin.Toggle("").toggleStyle(.switch).tint(.blue).fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }.padding()
                }
            }.padding()
        }
    }
}
