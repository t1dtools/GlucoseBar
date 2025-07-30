//
//  EventualGlucoseView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import SwiftUI

struct EventualGlucoseView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    @ViewBuilder
    var body: some View {
        HStack {
            Image(systemName: "arrow.right.circle")
            Text(formatGlucoseForDisplay(settings: s, glucose: convertGlucose(s, glucose: g.provider.GlucoseSourceExtras.eventualGlucose!)))
        }
    }
}
