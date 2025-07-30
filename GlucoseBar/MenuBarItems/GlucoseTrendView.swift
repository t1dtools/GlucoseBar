//
//  GlucoseTrendView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import SwiftUI

struct GlucoseTrendView: View {
    @EnvironmentObject var g: Glucose

    @ViewBuilder
    var body: some View {
        Text("\(g.trend)")
    }
}
