//
//  GlucoseDeltaView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import SwiftUI

struct GlucoseDeltaView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    @ViewBuilder
    var body: some View {
        Text("\(formatDeltaForDisplay(settings: s, delta: g.delta))")
    }
}
