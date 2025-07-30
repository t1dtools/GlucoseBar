//
//  IOBView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import SwiftUI

struct IOBView: View {
    @EnvironmentObject var g: Glucose

    @MainActor @ViewBuilder
    var body: some View {
        HStack {
            Image(systemName: "syringe.fill").foregroundColor(.blue)
            Text(formatIOBForDisplay(iob: g.provider.GlucoseSourceExtras.iob!) + " U")
        }
    }
}
