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
            return "Zero Temp"
        case .uam:
            return "Unannounced Meal"
        case .iob:
            return "Insulin On Board"
        case .cob:
            return "Carbs On Board"
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
