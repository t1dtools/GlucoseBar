//
//  LoopStatusView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import SwiftUI

struct LoopStatusView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    @ViewBuilder
    var body: some View {
        if g.provider.GlucoseSourceExtras.enactedAt != nil {
            HStack {
                Image(systemName: "circle").foregroundColor(getLoopColor(g.provider.GlucoseSourceExtras.enactedAt!)).fontWeight(.heavy)
                Text("\(relativeTime(time: g.provider.GlucoseSourceExtras.enactedAt!))")
            }.frame(alignment: .leading)//.padding(.bottom, 5).padding(.top, 3)
        } else {
            HStack {
                Image(systemName: "questionmark.circle").foregroundColor(.gray).fontWeight(.heavy)
                Text("Unknown")
            }.frame(alignment: .leading)
        }
    }
}
