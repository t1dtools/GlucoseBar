//
//  COBView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import SwiftUI

struct COBView: View {
    @EnvironmentObject var g: Glucose

    @ViewBuilder
    var body: some View {
        HStack {
            Image(systemName: "fork.knife").foregroundColor(.orange)
            Text(formatCOBForDisplay(cob: g.provider.GlucoseSourceExtras.cob!) + " g")
        }
    }
}
