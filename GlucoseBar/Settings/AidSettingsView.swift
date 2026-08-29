//
//  TrioSettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-03.
//

import Foundation
import SwiftUI

struct AidSettingsView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    func loadingView() -> some View {
        VStack {
            ProgressView().scaleEffect(1.0, anchor: .center).frame(width: 32, height: 32).padding(.vertical)
            Text("Loading AID data...")
        }.padding(.horizontal)
    }

    func unknownView() -> some View {
        VStack {
            Text("Unknown or unsupported AID system", comment: "Heading for the detected AID system in the AID integration settings view being unknown").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
            Text("Please open a ticket on GitHub with as much detail as possible about your device and the AID system you are using", comment: "Explaining text for what to do when an unknown AID system is detected").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: {
                NSWorkspace.shared.open(URL(string: "https://github.com/t1dtools/GlucoseBar/issues?q=sort%3Aupdated-desc%20state%3Aopen%20label%3Aaid-integration")!)
            }) {
                Text("Open GitHub Issue")
            }
        }.padding(.horizontal)
    }

    func aidView() -> some View {
        VStack {
            Text("AID System: \(g.provider.GlucoseSourceExtras.aid.presentable)", comment: "Heading for the detected AID system in the AID integration settings view").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
            if s.cgmProvider == .tandemsource {
                Text("Provided by Tandem Source CGM provider", comment: "Explaining text that AID data comes from the Tandem Source CGM provider").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Automatically detected by GlucoseBar", comment: "Explaining text that GlucoseBar automatically detects the AID system in use").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.horizontal)
    }

    func aidToggleSection() -> some View {
        VStack {
            GroupBox {
                VStack(spacing: 0) {
                    HStack {
                        Text("Enable AID Integration")
                        Spacer()
                        Toggle("", isOn: $s.aidEnableAID)
                            .toggleStyle(.switch)
                            .tint(.blue)
                            .fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                            .onChange(of: s.aidEnableAID) {
                                s.save()
                                g.reset(s)
                            }
                    }
                    .padding(.vertical, 6)
                }
                .padding()
            }.padding(.horizontal)

            if !s.aidEnableAID {
                VStack {
                    Text("Enable AID integration to see extra data like IOB, COB, Loop Status, and predictions from your Automated Insulin Delivery system.")
                        .font(.footnote)
                }.padding(.horizontal)
            } else {
                if s.cgmProvider == .nightscout {
                    VStack {
                        Text("Supported AIDs are AAPS, Loop, OpenAPS, and Trio.").font(.footnote)
                        Text("Not seeing your AID? Open an issue on GitHub.").font(.footnote)
                        Button(action: {
                            NSWorkspace.shared.open(URL(string: "https://github.com/t1dtools/GlucoseBar/issues?q=sort%3Aupdated-desc%20state%3Aopen%20label%3Aaid-integration")!)
                        }) {
                            Text("Open GitHub Issues")
                        }
                    }.padding(.horizontal)
                }

                if s.cgmProvider == .tandemsource {
                    VStack {
                        Text("Tandem Source provides AID data automatically. IOB, COB, basal rate, and pump status are included.").font(.footnote)
                    }.padding(.horizontal)
                }

                if s.cgmProvider != .nightscout && s.cgmProvider != .tandemsource {
                    VStack {
                        Text("Auto-detect requires a Nightscout or Tandem Source CGM provider. No AID data will be available with the current provider.").font(.footnote).foregroundColor(.orange)
                    }.padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    func detectedAIDView() -> some View {
        let aid = g.provider.GlucoseSourceExtras.aid
        if aid == .null {
            if s.aidEnableAID && s.cgmProvider != .nightscout && s.cgmProvider != .tandemsource {
                VStack {
                    Text("Auto-detect requires a Nightscout or Tandem Source CGM provider.")
                        .foregroundColor(.orange)
                        .padding(.horizontal)
                }
            } else {
                loadingView()
            }
        } else if aid == .unknown {
            unknownView()
        } else {
            aidView()
            dataGridView()
            chartOverlayView()
        }
    }

    @ViewBuilder
    func dataGridView() -> some View {
        let aidType = g.provider.GlucoseSourceExtras.aid
        Group {
            VStack {
                Text("Data Grid", comment: "Heading for the data grid settings on the AID integration settings view").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                Text("Values shown alongside the glucose headline when you open GlucoseBar", comment: "Explaining text for what the data grid is on the AID integration settings view").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.bottom).padding(.horizontal)

            GroupBox {
                VStack {
                    HStack {
                        Text("Show Insulin On Board")
                        Spacer()
                        Toggle(isOn: $s.aidChartShowIOB, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowIOB, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                    Text("Active insulin remaining from recent boluses.").font(.caption).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)

                    Divider()

                    HStack {
                        Text("Show Carbs On Board")
                        Spacer()
                        Toggle(isOn: $s.aidChartShowCOB, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowCOB, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                    Text("Active carbohydrates from recent meals.").font(.caption).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)

                    if aidType == .controliq {
                        Divider()
                        HStack {
                            Text("Show Basal Rate")
                            Spacer()
                            Toggle(isOn: $s.aidChartShowBasalRate, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowBasalRate, initial: false) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }
                        Text("Current basal delivery rate from the pump.").font(.caption).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
                    }

                    if [.trio, .openaps, .aaps, .controliq].contains(aidType) {
                        Divider()
                        HStack {
                            Text("Show Loop Status")
                            Spacer()
                            Toggle(isOn: $s.aidChartShowLoopStatus, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowLoopStatus, initial: false) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }
                        Text("Time since the algorithm last enacted a recommendation.").font(.caption).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)

                        if [.trio, .openaps, .aaps].contains(aidType) {
                            Divider()
                            HStack {
                                Text("Show Eventual Glucose")
                                Spacer()
                                Toggle(isOn: $s.aidChartShowEventualGlucose, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowEventualGlucose, initial: false) {
                                    s.save()
                                }.fixedSize()
                                    .scaleEffect(0.7, anchor: .trailing)
                            }
                            Text("Predicted steady-state glucose if current IOB, COB, and basal persist.").font(.caption).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
                        }
                    }
                }.padding()
            }.padding(.bottom).padding(.horizontal)
        }
    }

    @ViewBuilder
    func chartOverlayView() -> some View {
        let aidType = g.provider.GlucoseSourceExtras.aid
        let hasForecast = ![.loop, .controliq].contains(aidType)
        let hasControlIQ = aidType == .controliq
        Group {
            VStack {
                Text("Chart", comment: "Heading for the chart settings on the AID integration settings view").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                Text("Overlays and panels drawn on the glucose chart itself", comment: "Explaining text for what the chart settings are on the AID integration settings view").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.bottom).padding(.horizontal)

            GroupBox {
                VStack {
                    if hasForecast || !hasControlIQ {
                        HStack {
                            Text("Show Forecast")
                            Spacer()
                            Toggle(isOn: $s.aidChartShowForecast, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowForecast, initial: false) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }
                        Text("Future glucose predictions as colored lines or a shaded cone.").font(.caption).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
                        Divider()
                    }

                    if s.aidChartShowForecast && aidType != .loop {
                        HStack {
                            Text("Forecast Kind")
                            Spacer()
                            Picker("", selection: $s.aidChartForecastDisplay) {
                                Text("\(ForecastDisplay.lines.presentable)").tag(ForecastDisplay.lines)
                                Text("\(ForecastDisplay.cone.presentable)").tag(ForecastDisplay.cone)
                            }.frame(width: 100, alignment: .trailing).onChange(of: s.aidChartForecastDisplay) {
                                s.save()
                            }
                        }
                        Text("Individual prediction lines or a combined min-max cone.").font(.caption).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
                        Divider()
                    }

                    if hasControlIQ {
                        HStack {
                            Text("Show Active Insulin")
                            Spacer()
                            Toggle(isOn: $s.aidChartShowActiveInsulin, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowActiveInsulin, initial: false) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }
                        Text("Modeled IOB decay curve as a chart panel below the main chart.").font(.caption).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
                        Divider()

                        HStack {
                            Text("Show Carbs On Board Chart")
                            Spacer()
                            Toggle(isOn: $s.aidChartShowCOBChart, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowCOBChart, initial: false) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }
                        Text("Modeled COB decay curve as a chart panel below the main chart.").font(.caption).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
                        Divider()

                        HStack {
                            Text("Show Basal Overlay")
                            Spacer()
                            Toggle(isOn: $s.aidChartShowBasalOverlay, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowBasalOverlay, initial: false) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }
                        Text("Basal rate history as a stepped line and area fill on the chart.").font(.caption).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
                        Divider()

                        HStack {
                            Text("Show Bolus History")
                            Spacer()
                            Toggle(isOn: $s.aidShowBolusHistory, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidShowBolusHistory, initial: false) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }
                        Text("Bolus markers on the chart with dose, carb, and type tooltips.").font(.caption).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
                        Divider()

                        HStack {
                            Text("Show Mode Timeline")
                            Spacer()
                            Toggle(isOn: $s.aidChartShowModeTimeline, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowModeTimeline, initial: false) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }
                        Text("Pump mode changes as a colored bar at the chart bottom.").font(.caption).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
                    }
                }.padding()
            }.padding(.bottom).padding(.horizontal)
        }
    }

    var body: some View {
        ScrollView {
            VStack {
                Text("AID Integration", comment: "Heading for the AID integration settings view").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Text("Configure Automated Insulin Delivery data. AID systems can provide extra information like IOB, COB, Loop Status, predictions and more.", comment: "subheader for AID integration settings view").font(.footnote).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
            }.padding(.horizontal).padding(.top)

            aidToggleSection()

            if s.aidEnableAID || s.cgmProvider == .tandemsource {
                Divider().padding(.horizontal).padding(.vertical, 10)
                detectedAIDView()
            }
        }
    }
}
