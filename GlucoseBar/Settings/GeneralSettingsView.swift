//
//  GeneralSettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-03.
//

import Foundation
import SwiftUI


struct GeneralSettingsView: View {
    @EnvironmentObject var s: SettingsStore

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
                            }.onChange(of: s.glucoseUnit) {
                                s.save()
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

            }.padding()
        }
    }
}
