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
