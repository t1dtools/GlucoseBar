//
//  GlucoseEntry.swift
//  NightscoutKit
//
//  Created by Pete Schwamb on 4/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//
import Foundation

public struct GlucoseEntry: Hashable {
    typealias RawValue = [String: Any]

    public let id: String?
    public let glucose: Double
    public let date: Date
    public let glucoseType: GlucoseType
    public let trend: GlucoseTrend?
    public let changeRate: Double?
    public let isCalibration: Bool?
    public let condition: Condition?

    public init(
        glucose: Double,
        date: Date,
        glucoseType: GlucoseType = .sensor,
        trend: GlucoseTrend? = nil,
        changeRate: Double?,
        isCalibration: Bool? = false,
        condition: Condition? = nil,
        id: String? = nil)
    {
        self.glucose = glucose
        self.date = date
        self.glucoseType = glucoseType
        self.trend = trend
        self.changeRate = changeRate
        self.isCalibration = isCalibration
        self.condition = condition
        self.id = id
    }

    public enum Condition: String {
        case belowRange
        case aboveRange
    }

    public enum GlucoseType: String {
        case meter
        case sensor
    }

    public enum GlucoseTrend: Int, CaseIterable {
        case upUpUp         = 1
        case upUp           = 2
        case up             = 3
        case flat           = 4
        case down           = 5
        case downDown       = 6
        case downDownDown   = 7
        case notComputable  = 8
        case rateOutOfRange = 9
        
        init?(direction: String) {
            for trend in GlucoseTrend.allCases {
                if direction == trend.direction {
                    self = trend
                    return
                }
            }
            return nil
        }
        
        public var arrows: String {
            switch self {
            case .upUpUp:
                return "↑↑"
            case .upUp:
                return "↑"
            case .up:
                return "↗︎"
            case .flat:
                return "→"
            case .down:
                return "↘︎"
            case .downDown:
                return "↓"
            case .downDownDown:
                return "↓↓"
            case .notComputable:
                return "?"
            case .rateOutOfRange:
                return "?"
            }
        }

        public var direction: String {
            switch self {
            case .upUpUp:
                return "DoubleUp"
            case .upUp:
                return "SingleUp"
            case .up:
                return "FortyFiveUp"
            case .flat:
                return "Flat"
            case .down:
                return "FortyFiveDown"
            case .downDown:
                return "SingleDown"
            case .downDownDown:
                return "DoubleDown"
            case .notComputable:
                return "NotComputable"
            case .rateOutOfRange:
                return "RateOutOfRange"
            }
        }
    }

    public var dictionaryRepresentation: [String: Any] {
        var representation: [String: Any] = [
            "date": date.timeIntervalSince1970 * 1000,
            "dateString": ISO8601DateFormatter().string(from: date)
        ]

        representation["_id"] = id

        switch glucoseType {
        case .meter:
            representation["type"] = "mbg"
            representation["mbg"] = glucose
        case .sensor:
            representation["type"] = "sgv"
            representation["sgv"] = glucose
        }

        if let trend {
            representation["trend"] = trend.rawValue
            representation["direction"] = trend.direction
        }

        if let condition {
            representation["condition"] = condition.rawValue
        }

        representation["trendRate"] = changeRate
        representation["isCalibration"] = isCalibration

        return representation
    }

    init?(rawValue: RawValue) {

        guard
            let id = rawValue["_id"] as? String,
            let epoch = rawValue["date"] as? Double
        else {
            return nil
        }

        self.id = id
        self.date = Date(timeIntervalSince1970: epoch / 1000.0)

        //Dexcom changed the format of trend in 2021 so we accept both String/Int types
        if let intTrend = rawValue["trend"] as? Int {
            self.trend = GlucoseTrend(rawValue: intTrend)
        } else if let stringTrend = rawValue["trend"] as? String, let intTrend = Int(stringTrend) {
            self.trend = GlucoseTrend(rawValue: intTrend)
        } else if let directionString = rawValue["direction"] as? String {
            self.trend = GlucoseTrend(direction: directionString)
        } else {
            self.trend = nil
        }

        if let sgv = rawValue["sgv"] as? Double {
            self.glucose = sgv
            self.glucoseType = .sensor
        } else if let mbg = rawValue["mbg"] as? Double {
            self.glucose = mbg
            self.glucoseType = .meter
        } else {
            return nil
        }

        if let rawCondition = rawValue["condition"] as? String {
            self.condition = Condition(rawValue: rawCondition)
        } else {
            self.condition = nil
        }

        self.changeRate = rawValue["trendRate"] as? Double
        self.isCalibration = rawValue["isCalibration"] as? Bool
    }
}

extension Sequence where Iterator.Element: Hashable {
    func unique() -> [Iterator.Element] {
        var seen: Set<Iterator.Element> = []
        return filter { seen.insert($0).inserted }
    }
}
