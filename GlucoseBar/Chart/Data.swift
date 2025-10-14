//
//  Data.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-05-31.
//

import Foundation
import SwiftUI

struct GraphEntry {
    var date: Date
    var value: Double
    var trend: GlucoseEntry.GlucoseTrend
    var delta: Double
    var color: Color
    var forecastType: ForecastType
    var glucoseType: GlucoseEntry.GlucoseType?
}

public enum ForecastType: String, CaseIterable, Identifiable {
    case none
    case zt
    case uam
    case iob
    case cob
    public var id: String { self.rawValue }
    public var presentable: String {
        switch self {
        case .none:
            return ""
        case .zt:
            return String(localized: "Zero Temp", comment: "Zero temporary basal rate from the oref algorithmic output, used for the legend when choosing forecast lines (not necessarily translated in Trio)")
        case .uam:
            return String(localized: "Unannounced Meal", comment: "Unannounced meal from the oref algorithmic output, used for the legend when choosing forecast lines (not necessarily translated in Trio)")
        case .iob:
            return String(localized: "Insulin On Board", comment: "Insulin on board from the oref algorithmic output, used for the legend when choosing forecast lines (not necessarily translated in Trio)")
        case .cob:
            return String(localized: "Carbs On Board", comment: "Carbohydrates on board from the oref algorithmic output, used for the legend when choosing forecast lines (not necessarily translated in Trio)")
        }
    }
    public var int: Int {
        switch self {
        case .none:
            return 0
        case .zt:
            return 1
        case .uam:
            return 2
        case .iob:
            return 3
        case .cob:
            return 4
        }
    }
}

struct ConeData: Identifiable {
    var id = UUID()
    var d: Date
    var v: Double
}

func calculateConeData(entries: [GraphEntry]) -> ([ConeData], [ConeData]) {
    var minForTime: [Date: Double] = [:]
    var maxForTime: [Date: Double] = [:]

    var counters: [ForecastType: Int] = [:]
    for entry in entries {
        if entry.forecastType != .none {
            if counters.contains(where: {$0.key == entry.forecastType}) {
                counters[entry.forecastType, default: 0] += 1
            } else {
                counters[entry.forecastType] = 1
            }
        }
    }

    let shortestType = (counters.min(by: {$0.value < $1.value})?.key) ?? .none
    let localForecastDuration = Double(counters[shortestType] ?? 0) * 5 * 60

    for entry in entries {
        if entry.forecastType != .none && entry.date <= Date(timeIntervalSinceNow: TimeInterval(localForecastDuration)) {
            if entry.value < minForTime[entry.date] ?? .greatestFiniteMagnitude {
                minForTime[entry.date] = entry.value
            }
            if entry.value > maxForTime[entry.date] ?? -.greatestFiniteMagnitude {
                maxForTime[entry.date] = entry.value
            }
        }
    }

    var minEntries = [ConeData]()
    for entry in minForTime {
        minEntries.append(.init(d: entry.key, v: entry.value))
    }

    var maxEntries = [ConeData]()
    for entry in maxForTime {
        maxEntries.append(.init(d: entry.key, v: entry.value))
    }

    // Sort both arrays by date ascending
    minEntries.sort { $0.d < $1.d }
    maxEntries.sort { $0.d < $1.d }

    // Ensure both arrays are the same length
    if minEntries.count > maxEntries.count {
        maxEntries.removeLast(minEntries.count - maxEntries.count)
    } else if maxEntries.count > minEntries.count {
        minEntries.removeLast(maxEntries.count - minEntries.count)
    }

    if minEntries.count > 1 {
        minEntries.removeLast(1)
    }
    if maxEntries.count > 1 {
        maxEntries.removeLast(1)
    }

    return (minEntries, maxEntries)
}
