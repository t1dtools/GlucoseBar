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

    @State private var isTesting: Bool = false
    @State private var testResult: Bool? = nil

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
            if s.aidSource == .tandemSource {
                Text("Connected via Tandem Source", comment: "Explaining text that AID data comes from Tandem Source").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Automatically detected by GlucoseBar", comment: "Explaining text that GlucoseBar automatically detects the AID system in use").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.horizontal)
    }

    // MARK: - AID Source Configuration

    func aidSourceSection() -> some View {
        VStack {
            Text("AID Data Source")
                .font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top)
            GroupBox {
                HStack {
                    Text("Select Source")
                    Spacer()
                    Picker("", selection: $s.aidSource) {
                        ForEach(AIDSource.allCases) { source in
                            Text(source.presentable).tag(source)
                        }
                    }.frame(width: 300, alignment: .trailing).onChange(of: s.aidSource) {
                        s.save()
                        g.reset(s)
                    }
                }.padding()
            }.padding(.horizontal)


            if s.aidSource == .tandemSource {
                GroupBox {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Email").frame(width: 130, alignment: .leading)
                            Spacer()
                            TextField("", text: $s.tandemEmail).autocorrectionDisabled(true)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        .padding(.vertical, 4)
                        HStack {
                            Text("Password").frame(width: 130, alignment: .leading)
                            Spacer()
                            SecureField("", text: $s.tandemPassword).textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        .padding(.vertical, 4)

                        HStack {
                            Spacer()
                            if testResult == true {
                                HStack {
                                    Text("Connection OK").foregroundColor(.green)
                                    Image(systemName: "checkmark.circle").foregroundColor(.green)
                                }
                            }
                            if testResult == false {
                                HStack {
                                    Text("Invalid credentials or service unreachable").foregroundColor(.orange)
                                    Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                                }
                            }
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .padding(.leading, 2)
                            }
                            Button("Test Connection") {
                                isTesting = true
                                testResult = nil
                                Task {
                                    let ok = await s.testCGMProvider()
                                    testResult = ok
                                    isTesting = false
                                }
                            }.disabled(isTesting)
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                }.padding(.horizontal).padding(.bottom)
            }

            if s.aidSource == .autoDetect && s.cgmProvider != .nightscout {
                VStack {
                    Text("Auto-detect only works with Nightscout CGM provider. No AID data will be available with the current provider.").font(.footnote).foregroundColor(.orange)
                }.padding(.horizontal).padding(.bottom)
            }
        }
    }

    // MARK: - Chart Data

    @ViewBuilder
    func chartDataView() -> some View {
        let aidType = g.provider.GlucoseSourceExtras.aid
        let hasForecast = ![.loop, .controliq].contains(aidType)
        let hasControlIQ = aidType == .controliq
        Group {
            VStack {
                Text("Chart Data", comment: "Heading for settings for chart data on the AID integration settings view").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                Text("This is the data you see in and around the chart when you open GlucoseBar", comment: "Explaining text for what the chart data is on the AID integration settings view").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
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
                    Divider()
                    }

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
                Text("Configure Automated Insulin Delivery data. AID systems can provide extra information like IOB, COB, Loop Status, predictions and more.", comment: "subheader for AID integration settings view").font(.footnote).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
            }.padding(.horizontal).padding(.top)

            aidSourceSection()

            if s.aidSource != .none {
                Divider().padding(.horizontal).padding(.vertical, 10)

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
}
