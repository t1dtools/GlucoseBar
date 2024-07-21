//
//  GraphView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-10-01.
//

import Foundation
import SwiftUI
import Charts

struct GraphView: View {

    @ObservedObject var g: Glucose
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var vs: ViewState

    @State private var hoveredTime: Date?
    @State private var hoveredValue: Double?
    @State private var hoveredTrend: GlucoseEntry.GlucoseTrend?
    @State private var hoveredDelta: Double?
    @State private var isHovering: Bool = false

    init(glucose: Glucose) {
        self.g = glucose
    }
    
    struct GraphEntry {
        var date: Date
        var value: Double
        var trend: GlucoseEntry.GlucoseTrend
        var delta: Double
    }
    
    func getGraphData() -> [GraphEntry] {
        var data: [GraphEntry] = [];
        if (g.entries != nil) {

            let entryCount = s.graphMinutes/5-1

            for i in 0..<entryCount {
                if (g.entries!.count > i) {
                    let entry = g.entries![i]
                    let glu = convertGlucose(s, glucose: entry.glucose)

                    var delta = 0.0
                    if entry.changeRate != nil {
                        delta = entry.changeRate!
                    }

                    data.append(GraphEntry(date: entry.date, value: glu, trend: entry.trend ?? .notComputable, delta: delta))
                }
            }
        }

        return data
    }

    func changeTimeFrame(minutes: Int) -> [GraphEntry] {
        s.graphMinutes = minutes
        s.save()
        return getGraphData()
    }

    func convertGlucose(_ settings: SettingsStore, glucose: Double) -> Double {
        if s.glucoseUnit == .mmoll {
            return glucose / 18
        }

        return glucose
    }

    @FocusState var buttonFocusState

    var body: some View {
        let defaultMaxGlucose = convertGlucose(s, glucose: 216.0)
        let defaultMinGlucose = convertGlucose(s, glucose: 36.0)

        var data = getGraphData()
        let maxY = data.max(by: {$0.value < $1.value})?.value ?? defaultMaxGlucose
        let minY = data.min(by: {$0.value > $1.value})?.value ?? defaultMinGlucose

        let maxYMargin = convertGlucose(s, glucose: 36.0)

        let highThresholdRuleMark = convertGlucose(s, glucose: s.highThreshold)
        let lowThresholdRuleMark = convertGlucose(s, glucose: s.lowThreshold)

        let headlineTime = isHovering ? hoveredTime! : g.glucoseTime
        let headlineGlucose = isHovering ? hoveredValue! : convertGlucose(s, glucose: g.glucose)
        let headlineTrend = isHovering ? hoveredTrend! : GlucoseEntry.GlucoseTrend(direction: g.trend) ?? .notComputable

        let graphDataDuration = (-1 * (g.entries?.last?.date.timeIntervalSinceNow ?? 1) / 60 / 60).rounded()

        VStack {
            if s.hoverableGraph {
                VStack {
                    Text("\(Text(headlineTime, format: .dateTime.hour().minute()))").font(.subheadline)
                    Text("\(printFormattedGlucose(settings: s, glucose: headlineGlucose)) \(headlineTrend.arrows != "?" ? headlineTrend.arrows : "")").font(.largeTitle)
                }.padding(.top, 15)
            }

            HStack {
                if graphDataDuration >= 3 {
                    Button(s.graphMinutes == 180 ? "3 Hours" : "3") {
                        data = changeTimeFrame(minutes: 180)
                        buttonFocusState = false
                    }.clipShape(Capsule()).buttonStyle(.bordered).focused($buttonFocusState)
                }
                if graphDataDuration >= 6 {
                    Button(s.graphMinutes == 360 ? "6 Hours" : "6") {
                        data = changeTimeFrame(minutes: 360)
                        buttonFocusState = false
                    }.clipShape(Capsule()).buttonStyle(.bordered).focused($buttonFocusState)
                }
                if graphDataDuration >= 12 {
                    Button(s.graphMinutes == 720 ? "12 Hours" : "12") {
                        data = changeTimeFrame(minutes: 720)
                        buttonFocusState = false
                    }.clipShape(Capsule()).buttonStyle(.bordered).focused($buttonFocusState)
                }
                if graphDataDuration >= 24 {
                    Button(s.graphMinutes == 1440 ? "24 Hours" : "24") {
                        data = changeTimeFrame(minutes: 1440)
                        buttonFocusState = false
                    }.clipShape(Capsule()).buttonStyle(.bordered).focused($buttonFocusState)
                }
            }.padding().frame(alignment: .leading)

            Chart {
                RuleMark(y: .value("High", highThresholdRuleMark)).foregroundStyle(.yellow).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                RuleMark(y: .value("Low", lowThresholdRuleMark)).foregroundStyle(.red).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                ForEach(data, id: \.date) { point in
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("Glucose", point.value)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2.0))
                    .foregroundStyle(point.value > highThresholdRuleMark ? .yellow : point.value < lowThresholdRuleMark ? .red : .green)
                    .interpolationMethod(.cardinal)
                    .symbolSize(30)
                    .interpolationMethod(.catmullRom)
                }
                if s.hoverableGraph {
                    if let hoveredTime, let hoveredValue {
                        PointMark(
                            x: .value("Time", hoveredTime),
                            y: .value("Glucose", hoveredValue)
                        )
                    }
                }
            }
            .chartYScale(domain: [minY <= defaultMinGlucose ? minY : defaultMinGlucose, maxY >= defaultMaxGlucose ? (maxY + maxYMargin) : defaultMaxGlucose])
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount:8)) {
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount:6)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            VStack(alignment: .leading) {
                                Text(date, format: .dateTime.hour().minute())
                            }
                        }

                        AxisGridLine()
                        AxisTick()
                    }
                }
            }.chartOverlay { (chartProxy: ChartProxy) in
                Color.clear
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let hoverLocation):
                            let hTime = chartProxy.value(
                                atX: hoverLocation.x, as: Date.self
                            )

                            // Do we have a minute that has a value in the data?
                            data.forEach { entry in
                                let date = entry.date
                                let timeDiff = date.timeIntervalSince(hTime!)
                                if timeDiff < 60 && timeDiff > 0 {
                                    hoveredValue = entry.value
                                    hoveredTime = entry.date
                                    hoveredTrend = entry.trend
                                    hoveredDelta = entry.delta
                                    isHovering = true
                                }
                            }

                        case .ended:
                            hoveredTime = nil
                            isHovering = false
                        }
                    }
            }
            .padding()
        }
    }
}

#Preview {
    GraphView(glucose: Glucose()).environmentObject(SettingsStore())
}
