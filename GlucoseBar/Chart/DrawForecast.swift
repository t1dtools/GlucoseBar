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
    let forecastType: ForecastDisplay

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
        if forecastType == .lines {
            DrawLineForecast(data: data)
        }

        if forecastType == .cone {
            DrawConeForecast(data: data)
        }

        // Draw forecast boundry line
        RuleMark(x: .value("Time", getLatestGlucoseDate(data, includeForecasts: false)),
                 yStart: .value("Glucose", yMin),
                 yEnd: .value("Glucose", yMax)).foregroundStyle(.gray.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
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

struct DrawConeForecast: ChartContent {
    let data: [GraphEntry]



    func timeForIndex(_ index: Int, latestEntryDate: Date) -> Date {
        return Calendar.current.date(byAdding: .minute, value: (index + 1) * 5, to: latestEntryDate)!
    }

    func getByDate(_ date: Date, from list: [ConeData]) -> ConeData? {
        return list.first { $0.d == date }
    }

    var body: some ChartContent {
        let (minForecast, maxForecast) = calculateConeData(entries: data)

        ForEach(minForecast) { minEntry in
            ForEach(maxForecast) { maxEntry in
                if minEntry.d == maxEntry.d {
                    let delta = maxEntry.v - minEntry.v
                    if delta == 0 {
                        let minVal = minEntry.v - 1
                        let maxVal = maxEntry.v + 1
                        AreaMark(
                            x: .value("Time", minEntry.d),
                            yStart: .value("Min Value", minVal),
                            yEnd: .value("Max Value", maxVal),
                            series: .value("ForecastSeries", 1)
                        )
                        .foregroundStyle(Color.blue.opacity(0.3))
                        .interpolationMethod(.catmullRom)
                    } else {
                        let minVal = minEntry.v
                        let maxVal = maxEntry.v
                        AreaMark(
                            x: .value("Time", minEntry.d),
                            yStart: .value("Min Value", minVal),
                            yEnd: .value("Max Value", maxVal),
                            series: .value("ForecastSeries", 1)
                        )
                        .foregroundStyle(Color.blue.opacity(0.3))
                        .interpolationMethod(.catmullRom)
                    }
                }
            }

        }
    }
}
