//
//  Trio.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-05-31.
//

import Foundation
import SwiftUI

struct TrioGridView: View {
    @ObservedObject var g: Glucose
    @EnvironmentObject var s: SettingsStore

    let loopColor: Color = .green

    func relativeTime(time: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.formattingContext = .middleOfSentence

        if time.timeIntervalSinceNow > -60 {
            return "< 1 min. ago"
        }

        return formatter.localizedString(for: time, relativeTo: Date())
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 15, verticalSpacing: 15) {
            GridRow {
                if g.provider.GlucoseSourceExtras.iob != nil {
                    HStack {
                        Image(systemName: "syringe.fill").foregroundColor(.blue)
                        Text(formatIOBForDisplay(iob: g.provider.GlucoseSourceExtras.iob!) + " U")
                    }
                }
                if g.provider.GlucoseSourceExtras.cob != nil {
                    HStack {
                        Image(systemName: "fork.knife").foregroundColor(.orange)
                        Text(formatCOBForDisplay(cob: g.provider.GlucoseSourceExtras.cob!) + " g")
                    }
                }
            }
            GridRow {
                if g.provider.GlucoseSourceExtras.enactedAt != nil {
                    HStack {
                        Image(systemName: "circle").foregroundColor(loopColor)
                        Text("\(relativeTime(time: g.provider.GlucoseSourceExtras.enactedAt!))")
                    }.frame(alignment: .leading).padding(.bottom, 5).padding(.top, 3)
                }
                if g.provider.GlucoseSourceExtras.eventualGlucose != nil {
                    HStack {
                        Image(systemName: "arrow.right.circle")
                        Text(formatGlucoseForDisplay(settings: s, glucose: g.provider.GlucoseSourceExtras.eventualGlucose!))
                    }
                }
            }
        }.padding(.trailing, 25).padding(.top, 15).multilineTextAlignment(.leading)
    }
}
