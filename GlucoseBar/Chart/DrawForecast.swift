//
//  Forecast.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-05-31.
//

import Foundation
import SwiftUI
import Charts

let forecastDuration = 2.5 * 60 * 60

struct DrawForecast: ChartContent {
    let data: [GraphEntry]
    let yMin: Double
    let yMax: Double

    func getLatestGlucoseDate(_ data: [GraphEntry], includeForecasts: Bool) -> Date {
        var latestDate: Date? = nil
        data.forEach { entry in
            if latestDate == nil || (latestDate ?? Date()) < entry.date {
                if !includeForecasts && entry.forecastType == .none {
                    latestDate = entry.date
                }

                if includeForecasts && entry.forecastType != .none {
                    latestDate = entry.date
                }
            }
        }

        if latestDate == nil {
            return Date()
        }

        if latestDate! > Date().addingTimeInterval(forecastDuration) {
            latestDate = Date().addingTimeInterval(forecastDuration)
        }

        return latestDate!
    }

    var body: some ChartContent {
        if true {
            DrawLineForecast(data: data)
        }

//        if true {
//            DrawConeForecast(data: data)
//        }

        AreaMark(
            x: .value("Time", getLatestGlucoseDate(data, includeForecasts: false)),
            yStart: .value("Glucose", yMin),
            yEnd: .value("Glucose", yMax)
        ).foregroundStyle(.gray).opacity(0.1)

        AreaMark(
            x: .value("Time", getLatestGlucoseDate(data, includeForecasts: true)),
            yStart: .value("Glucose", yMin),
            yEnd: .value("Glucose", yMax)
        ).foregroundStyle(.gray).opacity(0.1)
    }
}

struct DrawLineForecast: ChartContent {
    let data: [GraphEntry]
    var body: some ChartContent {
        ForEach(data, id: \.date) { point in
            if point.forecastType != .none && point.date <= Date(timeIntervalSinceNow: TimeInterval(forecastDuration)) {
                PointMark(
                    x: .value("Time", point.date),
                    y: .value("Glucose", point.value)
                )
                .lineStyle(StrokeStyle(lineWidth: 1.0))
                .foregroundStyle(point.color)
                .symbolSize(10)
                .interpolationMethod(.cardinal)
            }
        }
    }
}

//struct DrawConeForecast: ChartContent {
//    let data: [GraphEntry]
//    
//    func calculateConeData(entries: [GraphEntry]) -> ([Date: Double], [Date: Double]) {
////        var forecastEntries = [[GraphEntry]]()
//        var minForTime: [Date: Double] = [:]
//        var maxForTime: [Date: Double] = [:]
//
//        for entry in entries {
//            if entry.forecastType != .none {
//                
////                forecastEntries.insert([entry], at: entry.forecastType.int)
//                if entry.value < minForTime[entry.date] ?? .greatestFiniteMagnitude {
//                    minForTime[entry.date] = entry.value
//                }
//                
//                if entry.value > maxForTime[entry.date] ?? -.greatestFiniteMagnitude {
//                    maxForTime[entry.date] = entry.value
//                }
//            }
//        }
//        
//        return (minForTime, maxForTime)
//    }
//    
//    func timeForIndex(_ index: Int, latestEntryDate: Date) -> Date {
//        return Calendar.current.date(byAdding: .minute, value: (index + 1) * 5, to: latestEntryDate)!
//    }
//
//    var body: some ChartContent {
//        let (minForecast, maxForecast) = calculateConeData(entries: data)
//        let maxValue = 200
//
//        let latestEntryDate = data.first?.date ?? Date()
//        ForEach(0 ..< max(minForecast.count, maxForecast.count), id: \.self) { index in
//            if index < minForecast.count, index < maxForecast.count {
//                let xValue = timeForIndex(index, latestEntryDate: latestEntryDate)
//                let yMinMaxDelta = Decimal((minForecast[xValue] ?? 0) - (maxForecast[xValue] ?? 0))
//
//                // if distance between respective min and max is 0, provide a default range
//                if yMinMaxDelta == 0 {
//                    let yMinValue = Decimal(minForecast[index] - 1)
//                    let yMaxValue = Decimal(minForecast[index] + 1)
//
//                    if xValue <= Date(timeIntervalSinceNow: TimeInterval(hours: 2.5)) {
//                        AreaMark(
//                            x: .value("Time", xValue),
//                            yStart: .value("Min Value", yMinValue <= maxValue ? yMinValue : maxValue),
//                            yEnd: .value("Max Value", yMaxValue <= maxValue ? yMaxValue : maxValue)
//                        )
//                        .foregroundStyle(Color.blue.opacity(0.5))
//                        .interpolationMethod(.catmullRom)
//                    }
//                } else {
//                    let yMinValue = minForecast[xValue]
//                    let yMaxValue = maxForecast[xValue]
//
//                    if xValue <= Date(timeIntervalSinceNow: TimeInterval(forecastDuration)) {
//                        AreaMark(
//                            x: .value("Time", xValue),
//                            // maxValue is already parsed to user units, no need to parse
//                            yStart: .value("Min Value", yMinValue <= maxValue ? yMinValue : maxValue),
//                            yEnd: .value("Max Value", yMaxValue <= maxValue ? yMaxValue : maxValue)
//                        )
//                        .foregroundStyle(Color.blue.opacity(0.5))
//                        .interpolationMethod(.catmullRom)
//                    }
//                }
//            }
//        }
//    }
//}
