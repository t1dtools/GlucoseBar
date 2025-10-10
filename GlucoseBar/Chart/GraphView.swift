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
    @State private var legends: [String : Color] = [:]
    @State private var isLoading: Bool = false

    var gse: GlucoseSourceExtraProperties = GlucoseSourceExtraProperties()

    init(glucose: Glucose) {
        self.g = glucose
        self.gse = glucose.provider.GlucoseSourceExtras
    }

    func getGraphData() -> [GraphEntry] {

        let highThresholdRuleMark = Decimal(convertGlucose(s, glucose: s.highThreshold))
        let lowThresholdRuleMark = Decimal(convertGlucose(s, glucose: s.lowThreshold))

        var data: [GraphEntry] = [];
        if let entries = g.entries {

            let entryCount = s.graphMinutes/5-1

            for i in 0..<entryCount {
                if (entries.count > i) {
                    let entry = entries[i]
                    let glu = convertGlucose(s, glucose: entry.glucose)

                    var delta = 0.0
                    if let changeRate = entry.changeRate {
                        delta = changeRate
                    }

                    var glucoseTarget = s.glucoseTarget
                    if let fetchedGlucoseTarget = g.provider.GlucoseSourceExtras.glucoseTarget {
                        glucoseTarget = fetchedGlucoseTarget
                    }

                    let color = getDynamicGlucoseColor(glucoseValue: Decimal(convertGlucose(s, glucose: entry.glucose)), highGlucoseColorValue: highThresholdRuleMark, lowGlucoseColorValue: lowThresholdRuleMark, targetGlucose: Decimal(convertGlucose(s, glucose: glucoseTarget)), glucoseColorScheme: s.glucoseColorScheme)

                    data.append(GraphEntry(date: entry.date, value: glu, trend: entry.trend ?? .notComputable, delta: delta, color: color, forecastType: .none, glucoseType: entry.glucoseType))
                }
            }
        }

        let forecastStartDate = gse.enactedAt ?? Date()

        if let zt = gse.forecasts.zt {
            for i in 0..<zt.count {
                let entry = zt[i]
                let glu = convertGlucose(s, glucose: Double(entry))

                let date = Calendar.current.date(byAdding: .minute, value: i * 5, to: forecastStartDate)!

                data.append(GraphEntry(date: date, value: glu, trend: .notComputable, delta: 0.0, color: .purple, forecastType: .zt))
            }
        }

        if let uam = gse.forecasts.uam {
            for i in 0..<uam.count {
                let entry = uam[i]
                let glu = convertGlucose(s, glucose: Double(entry))

                let date = Calendar.current.date(byAdding: .minute, value: i * 5, to: forecastStartDate)!

                data.append(GraphEntry(date: date, value: glu, trend: .notComputable, delta: 0.0, color: .orange, forecastType: .uam))
            }
        }

        if let cob = gse.forecasts.cob {
            for i in 0..<cob.count {
                let entry = cob[i]
                let glu = convertGlucose(s, glucose: Double(entry))

                let date = Calendar.current.date(byAdding: .minute, value: i * 5, to: forecastStartDate)!

                data.append(GraphEntry(date: date, value: glu, trend: .notComputable, delta: 0.0, color: .yellow, forecastType: .cob))
            }
        }

        if let iob = gse.forecasts.iob {
            for i in 0..<iob.count {
                let entry = iob[i]
                let glu = convertGlucose(s, glucose: Double(entry))

                let date = Calendar.current.date(byAdding: .minute, value: i * 5, to: forecastStartDate)!

                data.append(GraphEntry(date: date, value: glu, trend: .notComputable, delta: 0.0, color: .blue, forecastType: .iob))
            }
        }

        return data
    }

    func reloadData() {
        Task {
            isLoading = true
            await g.provider.fetch()
            isLoading = false
        }
    }

    func changeTimeFrame(minutes: Int) -> [GraphEntry] {
        s.graphMinutes = minutes
        s.save()
        return getGraphData()
    }

    func getMinMaxY(data: [GraphEntry]) -> (Double, Double, Double, Double) {
        let defaultMaxGlucose = convertGlucose(s, glucose: 216.0)
        let defaultMinGlucose = convertGlucose(s, glucose: 36.0)

        var maxY = 0.0
        var minY = 0.0

        var entries: [GraphEntry] = []
        let coneData = calculateConeData(entries: data)

        for(_, entry) in data.enumerated() {
            if entry.forecastType == .none {
                entries.append(entry)
            }
        }

        if s.aidChartShowForecast {
            if s.aidChartForecastDisplay == .cone {
                // Calculate highest entry from coneData
                let maxConeData = coneData.1.max(by: {$0.v < $1.v})?.v ?? 0
                if maxConeData > 0 {
                    entries.append(GraphEntry(date: Date(), value: maxConeData, trend: GlucoseEntry.GlucoseTrend.flat, delta: 0, color: Color.blue, forecastType: .none))
                }
            }

            if s.aidChartForecastDisplay == .lines {
                for(_, entry) in data.enumerated() {
                    if entry.forecastType != .none && entry.date <= Date(timeIntervalSinceNow: TimeInterval(forecastDuration)) {
                        entries.append(entry)
                    }
                }
            }
        }

        maxY = entries.max(by: {$0.value < $1.value})?.value ?? defaultMaxGlucose
        minY = entries.min(by: {$0.value > $1.value})?.value ?? defaultMinGlucose
        return (minY, maxY, defaultMinGlucose, defaultMaxGlucose)
    }

    @FocusState var buttonFocusState
    @FocusState var zenModeFocusState

    var body: some View {
        var data = getGraphData()
        let (minY, maxY, defaultMinGlucose, defaultMaxGlucose) = getMinMaxY(data: data)

        let maxYMargin = convertGlucose(s, glucose: 36.0)

        let highThresholdRuleMark = convertGlucose(s, glucose: s.highThreshold)
        let lowThresholdRuleMark = convertGlucose(s, glucose: s.lowThreshold)

        let latestGlucoseTime = g.glucoseTime
        let latestGlucose = convertGlucose(s, glucose: g.glucose)
        let latestTrend = GlucoseEntry.GlucoseTrend(direction: g.trend) ?? .notComputable

        let headlineTime = isHovering ? hoveredTime ?? latestGlucoseTime : latestGlucoseTime
        let headlineGlucose = isHovering ? hoveredValue ?? latestGlucose : latestGlucose
        let headlineTrend = isHovering ? hoveredTrend ?? latestTrend : latestTrend

        let graphDataDuration = (-1 * (g.entries?.last?.date.timeIntervalSinceNow ?? 1) / 60 / 60).rounded()

        VStack {
            HStack {
                VStack {
                    Text("\(Text(headlineTime, format: .dateTime.hour().minute()))").font(.subheadline)
                    Text("\(printFormattedGlucose(settings: s, glucose: headlineGlucose)) \(headlineTrend.arrows != "↔" ? headlineTrend.arrows : "")").font(.largeTitle)
                }.padding(.leading, 25).padding(.top, 10)

                // Currently, all three supported AIDs support these options.
                if s.cgmProvider == .nightscout && g.provider.RemoteGlucoseSource != .null {
                    if s.aidChartShowCOB || s.aidChartShowIOB || s.aidChartShowLoopStatus || s.aidChartShowEventualGlucose {
                        Spacer()
                        AidGridView(g: g).environmentObject(s)
                    }
                }
            }.padding()

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
                if data.count > 0 {
                    Spacer()
                    Button(action: {
                        reloadData()
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView().scaleEffect(0.5, anchor: .center).frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }.contentShape(Rectangle())
                    }.help("Refresh all data")
                        .clipShape(Capsule())
                        .buttonStyle(.bordered)
                        .focused($buttonFocusState)
                        .disabled(isLoading)
                }
            }.padding().frame(alignment: .leading)

            Chart {
                if s.glucoseColorScheme == .staticColor {
                    if s.showHighThreshold {
                        RuleMark(y: .value("High", highThresholdRuleMark)).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                    if s.showLowThreshold {
                        RuleMark(y: .value("Low", lowThresholdRuleMark)).foregroundStyle(.red).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                } else if s.glucoseColorScheme == .dynamicColor {
                    if s.showHighThreshold {
                        RuleMark(y: .value("High", highThresholdRuleMark)).foregroundStyle(dynamicPurple).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                    if s.showLowThreshold {
                        RuleMark(y: .value("Low", lowThresholdRuleMark)).foregroundStyle(dynamicRed).lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                }

                if s.showTarget {
                    RuleMark(y: .value("Target", 90)).foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1))
                }


                if s.aidChartShowForecast {
                    DrawForecast(
                        data: data,
                        yMin: minY <= defaultMinGlucose ? minY : defaultMinGlucose,
                        yMax: maxY >= defaultMaxGlucose ? (maxY + maxYMargin) : defaultMaxGlucose,
                        forecastType: s.aidChartForecastDisplay
                    )
                }
                DrawGlucose(data: data)

                if let hoveredTime, let hoveredValue {
                    PointMark(
                        x: .value("Time", hoveredTime),
                        y: .value("Glucose", hoveredValue)
                    )
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
                                    if entry.forecastType == .none {
                                        hoveredValue = entry.value
                                        hoveredTime = entry.date
                                        hoveredTrend = entry.trend
                                        hoveredDelta = entry.delta
                                        isHovering = true
                                    } else {
                                        hoveredTime = nil
                                        isHovering = false
                                    }
                                }
                            }

                        case .ended:
                            hoveredTime = nil
                            isHovering = false
                        }
                    }
            }.chartForegroundStyleScale(["UAM": .orange, "ZT": .purple, "IOB": .blue, "COB": .yellow]
            ).chartLegend(s.aidChartShowForecast && s.aidChartForecastDisplay == .lines ? .visible : .hidden)
            .padding()
        }
    }
}

#Preview {
    GraphView(glucose: Glucose(SettingsStore())).environmentObject(SettingsStore())
}
