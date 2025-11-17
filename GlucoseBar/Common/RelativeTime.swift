//
//  RelativeTime.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import Foundation
import SwiftUI

func relativeTime(time: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    formatter.formattingContext = .middleOfSentence

    if time.timeIntervalSinceNow > -60 {
        return String(localized: "< 1 min. ago", comment: "Used for relative time throughout the application when the elapsed time is less than a minute")
    }

    return formatter.localizedString(for: time, relativeTo: Date())
}
