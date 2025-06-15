//
//  LoopColor.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import Foundation
import SwiftUI

func getLoopColor(_ time: Date) -> Color {
    let timeSinceNow = time.timeIntervalSinceNow
    if timeSinceNow > -60 * 6 {
        return .green
    }

    if timeSinceNow > -60 * 10 {
        return .yellow
    }

    return .red
}
