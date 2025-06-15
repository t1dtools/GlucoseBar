//
//  RelativeTime.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import Foundation

func relativeTime(time: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    formatter.formattingContext = .middleOfSentence

    if time.timeIntervalSinceNow > -60 {
        return "< 1 min. ago"
    }

    return formatter.localizedString(for: time, relativeTo: Date())
}
