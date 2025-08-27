//
//  DrawGlucose.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-05-31.
//

import Foundation
import SwiftUI
import Charts

struct DrawGlucose: ChartContent {
    let data: [GraphEntry]

    var body: some ChartContent {
        ForEach(data, id: \.date) { point in
            if point.forecastType == .none {
                if point.glucoseType == .sensor {
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("Glucose", point.value)
                    ).lineStyle(StrokeStyle(lineWidth: 2.0))
                        .foregroundStyle(point.color)
                        .interpolationMethod(.cardinal)
                        .symbolSize(30)
                        .interpolationMethod(.catmullRom)
                } else {
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("Glucose", point.value)
                    ).lineStyle(StrokeStyle(lineWidth: 2.0))
                        .foregroundStyle(point.color)
                        .interpolationMethod(.cardinal)
                        .symbolSize(30)
                        .interpolationMethod(.catmullRom)
                        .symbol {
                            Image(systemName: "drop.fill")
                                .foregroundColor(point.color)
                        }
                }
            }
        }
    }
}
