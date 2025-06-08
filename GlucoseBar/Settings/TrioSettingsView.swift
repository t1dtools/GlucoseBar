//
//  TrioSettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-03.
//

import Foundation
import SwiftUI

struct TrioSettingsView: View {
    @EnvironmentObject var s: SettingsStore

    var body: some View {
        ScrollView {
            VStack {
                Text("Trio Integration").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    Text("GlucoseBar has detected Trio data in your Nightscout instance, and is able to show you some of the data from there.").font(.footnote)
            }.padding(.horizontal).padding(.top)

            VStack {
                Text("Menu Bar Data").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Text("This is the data you see in the macOS menu bar").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            }.padding()

            GroupBox {
                VStack {

                    HStack {
                        Text("Show Insulin On Board")
                        Spacer()
                        Toggle(isOn: $s.trioBarShowIOB, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.trioBarShowIOB, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                    Divider()

                    HStack {
                        Text("Show Carbs On Board when > 0g")
                        Spacer()
                        Toggle(isOn: $s.trioBarShowCOB, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.trioBarShowCOB, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                    Divider()

                    HStack {
                        Text("Show Eventual Glucose")
                        Spacer()
                        Toggle(isOn: $s.trioBarShowEventualGlucose, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.trioBarShowEventualGlucose, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                }.padding()
            }.padding(.bottom).padding(.horizontal)

            VStack {
                Text("Chart Data").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                Text("This is the data you in and around the chart when you open GlucoseBar").font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.bottom).padding(.horizontal)

            GroupBox {
                VStack {
                    HStack {
                        Text("Show Forecast")
                        Spacer()
                        Toggle(isOn: $s.trioChartShowForecast, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.trioChartShowForecast, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                    Divider()

                    if s.trioChartShowForecast {
                        HStack {
                            Text("Forecast Kind")
                            Spacer()
                            Picker("", selection: $s.trioChartForecastDisplay) {
                                Text("\(ForecastDisplay.lines.presentable)").tag(ForecastDisplay.lines)
                                Text("\(ForecastDisplay.cone.presentable)").tag(ForecastDisplay.cone)
                            }.frame(width: 100).onChange(of: s.trioChartForecastDisplay) {
                                s.save()
                            }
                        }
                        Divider()
                    }

                    HStack {
                        Text("Show Insulin On Board")
                        Spacer()
                        Toggle(isOn: $s.trioChartShowIOB, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.trioChartShowIOB, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                    Divider()

                    HStack {
                        Text("Show Carbs On Board")
                        Spacer()
                        Toggle(isOn: $s.trioChartShowCOB, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.trioChartShowCOB, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                    Divider()

                    HStack {
                        Text("Show Loop Status")
                        Spacer()
                        Toggle(isOn: $s.trioChartShowLoopStatus, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.trioChartShowLoopStatus, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                    Divider()

                    HStack {
                        Text("Show Eventual Glucose")
                        Spacer()
                        Toggle(isOn: $s.trioChartShowEventualGlucose, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.trioChartShowEventualGlucose, initial: false) {
                            s.save()
                        }.fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                }.padding()
            }.padding(.bottom).padding(.horizontal)
        }
    }
}
