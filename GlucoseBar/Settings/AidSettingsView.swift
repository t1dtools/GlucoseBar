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

    var body: some View {
        ScrollView {
            VStack {
                Text("AID Integration").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Text("You have enabled the AID integration, which allows GlucoseBar to show you extra data.").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal).padding(.top)

            VStack {
                Text("Chart Data").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                Text("This is the data you see in and around the chart when you open GlucoseBar").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
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

                    if s.aidChartShowForecast {
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
                }.padding()
            }.padding(.bottom).padding(.horizontal)
        }
    }
}
