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
            Text("Automatically detected by GlucoseBar", comment: "Explaining text that GlucoseBar automatically detects the AID system in use").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal)
    }

    func chartDataView() -> some View {
        Group {
            VStack {
                Text("Chart Data", comment: "Heading for settings for chart data on the AID integration settings view").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                Text("This is the data you see in and around the chart when you open GlucoseBar", comment: "Explaining text for what the chart data is on the AID integration settings view").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.bottom).padding(.horizontal)

            GroupBox {
                VStack {
                    HStack {
                        Text("Show Forecast")
                        Spacer()
                        Toggle(isOn: $s.aidChartShowForecast, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowForecast, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                    Divider()

                    if s.aidChartShowForecast && g.provider.GlucoseSourceExtras.aid != .loop {
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
                        Divider()
                    }

                    HStack {
                        Text("Show Insulin On Board")
                        Spacer()
                        Toggle(isOn: $s.aidChartShowIOB, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowIOB, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }

                    Divider()
                    HStack {
                        Text("Show Carbs On Board")
                        Spacer()
                        Toggle(isOn: $s.aidChartShowCOB, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowCOB, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }

                    if [.trio, .openaps, .aaps].contains(g.provider.GlucoseSourceExtras.aid) {
                        Divider()
                        HStack {
                            Text("Show Loop Status")
                            Spacer()
                            Toggle(isOn: $s.aidChartShowLoopStatus, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowLoopStatus, initial: false) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }

                        Divider()
                        HStack {
                            Text("Show Eventual Glucose")
                            Spacer()
                            Toggle(isOn: $s.aidChartShowEventualGlucose, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.aidChartShowEventualGlucose, initial: false) {
                                s.save()
                            }.fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                        }
                    }
                }.padding()
            }.padding(.bottom).padding(.horizontal)
        }
    }

    var body: some View {
        ScrollView {
            VStack {
                Text("AID Integration", comment: "Heading for the AID integration settings view").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Text("You have enabled the AID integration, which allows GlucoseBar to show you extra data.", comment: "subheader for AID integration settings view explaining that you have enalbed AID and that GlucoseBar can now show you extra information").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal).padding(.top)

            if g.provider.GlucoseSourceExtras.aid == .null {
                loadingView()
            } else if g.provider.GlucoseSourceExtras.aid == .unknown {
                unknownView()
            } else {
                aidView()
                chartDataView()
            }
        }
    }
}
