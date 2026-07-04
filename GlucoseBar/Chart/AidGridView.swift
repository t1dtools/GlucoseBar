//
//  Trio.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-05-31.
//

import Foundation
import SwiftUI

struct AidGridView: View {
    @ObservedObject var g: Glucose
    @EnvironmentObject var s: SettingsStore
    let hoveredBasalRate: Double?

    var body: some View {
        let aid = g.provider.GlucoseSourceExtras.aid
        let isControlIQ = aid == .controliq

        VStack {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    if s.aidChartShowIOB, let iob = g.provider.GlucoseSourceExtras.iob {
                        HStack {
                            Image(systemName: "syringe.fill").foregroundColor(.blue)
                            Text(formatIOBForDisplay(iob: iob) + " U")
                        }.help("Insulin On Board")
                    }
                    if s.aidChartShowCOB, let cob = g.provider.GlucoseSourceExtras.cob {
                        HStack {
                            Image(systemName: "fork.knife").foregroundColor(.orange)
                            Text(formatCOBForDisplay(cob: cob) + " g")
                        }.help("Carbs On Board")
                    }
                }
                GridRow {
                    if s.aidChartShowLoopStatus, let enactedAt = g.provider.GlucoseSourceExtras.enactedAt {
                        HStack {
                            Image(systemName: "circle").foregroundColor(getLoopColor(enactedAt)).fontWeight(.heavy)
                            Text("\(relativeTime(time: enactedAt))")
                        }.frame(alignment: .leading).padding(.bottom, 5).padding(.top, 3)
                            .help("Loop Status and time since last loop")
                    }
                    if isControlIQ, s.aidChartShowBasalRate {
                        let rate = hoveredBasalRate ?? g.provider.GlucoseSourceExtras.basalRate
                        if let rate = rate {
                            HStack {
                                Image(systemName: "gauge.with.dots.needle.33percent").foregroundColor(.blue)
                                Text(String(format: "%.2f U/h", rate))
                            }.help("Basal Rate")
                        }
                    }
                    if !isControlIQ, s.aidChartShowEventualGlucose, let eventualGlucose = g.provider.GlucoseSourceExtras.eventualGlucose {
                        HStack {
                            Image(systemName: "arrow.right.circle").fontWeight(.heavy)
                            Text(formatGlucoseForDisplay(settings: s, glucose: eventualGlucose))
                        }.help("Eventual Glucose")
                    }
                }

            }.padding(.trailing, 25).padding(.top, 10).multilineTextAlignment(.leading)

            if g.provider.GlucoseSourceExtras.error != nil {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                    Text("\(String(describing: g.provider.GlucoseSourceExtras.error))").foregroundStyle(.red)
                }
            }
        }
    }
}
