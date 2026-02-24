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

    var body: some View {
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
                    if s.aidChartShowEventualGlucose, let eventualGlucose = g.provider.GlucoseSourceExtras.eventualGlucose {
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
