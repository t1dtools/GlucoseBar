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
    @Binding var hoveredInsulinIOB: Double?
    @Binding var sharedHoverTime: Date?

    @State private var hoveredTime: Date?
    @State private var hoveredValue: Double?
    @State private var hoveredTrend: GlucoseEntry.GlucoseTrend?
    @State private var hoveredDelta: Double?
    @Binding var basalRate: Double?
    @State private var hoveredActualY: Double?
    @State private var hoveredBolusId: UUID?
    @State private var hoveredBolus: BolusOverlayEntry?
    @State private var isHovering: Bool = false
    @State private var legends: [String : Color] = [:]
    @State private var isLoading: Bool = false

    var gse: GlucoseSourceExtraProperties = GlucoseSourceExtraProperties()

    init(glucose: Glucose, hoveredInsulinIOB: Binding<Double?> = .constant(nil), sharedHoverTime: Binding<Date?> = .constant(nil), basalRate: Binding<Double?> = .constant(nil)) {
        self.g = glucose
        self.gse = glucose.provider.GlucoseSourceExtras
        self._hoveredInsulinIOB = hoveredInsulinIOB
        self._sharedHoverTime = sharedHoverTime
        self._basalRate = basalRate
    }

    func getGraphData() -> [GraphEntry] {

        let highThresholdRuleMark = Decimal(convertGlucose(s, glucose: s.highThreshold))
        let lowThresholdRuleMark = Decimal(convertGlucose(s, glucose: s.lowThreshold))

        var data: [GraphEntry] = [];
        if let entries = g.entries {
            let earliestToInclude = Date(timeIntervalSinceNow: TimeInterval(-s.graphMinutes*60))

            for entry in entries {
                if entry.date.timeIntervalSince(earliestToInclude) < 0 {
                    continue
                }

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

        if let loop = gse.forecasts.loop {
            for i in 0..<loop.count {
                let entry = loop[i]
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
        let targetRuleMark = convertGlucose(s, glucose: s.glucoseTarget)

        let latestGlucoseTime = g.glucoseTime
        let latestGlucose = convertGlucose(s, glucose: g.glucose)
        let latestTrend = GlucoseEntry.GlucoseTrend(direction: g.trend) ?? .notComputable

        let headlineTime = isHovering ? hoveredTime ?? latestGlucoseTime : latestGlucoseTime
        let headlineGlucose = isHovering ? hoveredValue ?? latestGlucose : latestGlucose
        let headlineTrend = isHovering ? hoveredTrend ?? latestTrend : latestTrend

        let graphDataDuration = (-1 * (g.entries?.last?.date.timeIntervalSinceNow ?? 1) / 60 / 60).rounded()

        let basalEntries = GraphView.basalOverlayEntries(g: g, s: s, maxY: maxY, defaultMaxGlucose: defaultMaxGlucose, maxYMargin: maxYMargin, minY: minY, defaultMinGlucose: defaultMinGlucose)
        let bolusEntries = GraphView.bolusOverlayEntries(g: g, s: s, data: data)
        let basalChartTop = maxY >= defaultMaxGlucose ? (maxY + maxYMargin) : defaultMaxGlucose
        let basalChartMin = minY <= defaultMinGlucose ? minY : defaultMinGlucose
        let basalVisibleOffset = max(0.0, (200.0 / 350.0) * (basalChartTop - basalChartMin))
        let basalMaxRate: Double = 5.0

        // Loop only has one forecast, so a cone doesn't make sense
        let forecastDisplay = g.provider.GlucoseSourceExtras.aid == .loop ? .lines : s.aidChartForecastDisplay
        let legendList: KeyValuePairs<String, Color> = g.provider.GlucoseSourceExtras.aid == .loop ? ["Forecast": Color.blue] : ["UAM": Color.orange, "ZT": Color.purple, "IOB": Color.blue, "COB": Color.yellow]

        VStack {
            HStack {
                VStack {
                    Text("\(Text(headlineTime, format: .dateTime.hour().minute()))").font(.subheadline)
                    Text("\(printFormattedGlucose(settings: s, glucose: headlineGlucose)) \(headlineTrend.arrows != "↔" ? headlineTrend.arrows : "")").font(.largeTitle)
                }.padding(.leading, 25).padding(.top, 10)

                // Currently, all three supported AIDs support these options.
                if g.provider.RemoteGlucoseSource != .null {
                    if s.aidChartShowCOB || s.aidChartShowIOB || s.aidChartShowLoopStatus || s.aidChartShowEventualGlucose {
                        Spacer()
                        AidGridView(g: g, hoveredBasalRate: basalRate, hoveredInsulinIOB: hoveredInsulinIOB).environmentObject(s)
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
                    RuleMark(y: .value("Target", targetRuleMark)).foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1))
                }


                if s.aidChartShowForecast {
                    DrawForecast(
                        data: data,
                        yMin: minY <= defaultMinGlucose ? minY : defaultMinGlucose,
                        yMax: maxY >= defaultMaxGlucose ? (maxY + maxYMargin) : defaultMaxGlucose,
                        forecastType: forecastDisplay
                    )
                }
                if !basalEntries.isEmpty {
                    ForEach(basalEntries) { e in
                        AreaMark(x: .value("Fx", e.date),
                                 yStart: .value("FyT", basalChartTop),
                                 yEnd: .value("FyR", e.actualY))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue.opacity(0.0), .blue.opacity(0.35)], startPoint: .bottom, endPoint: .top)
                        )
                        .interpolationMethod(.stepStart)
                    }
                    ForEach(basalEntries) { e in
                        LineMark(x: .value("Lx", e.date), y: .value("Ly", e.actualY))
                            .foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 1)).interpolationMethod(.stepStart)
                    }
                }
                DrawGlucose(data: data)

                if let ht = sharedHoverTime {
                    RuleMark(x: .value("HovRX", ht))
                        .foregroundStyle(.blue.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }

                if let ht = hoveredTime, let hy = hoveredActualY {
                    PointMark(x: .value("HovBX", ht), y: .value("HovBY", hy))
                        .foregroundStyle(.blue)
                        .symbolSize(40)
                }

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
                    .background {
                        if !bolusEntries.isEmpty {
                            Canvas { context, size in
                                for b in bolusEntries {
                                    guard let pt = chartProxy.position(for: (b.date, b.glucoseY)) else { continue }
                                    let isHL = b.id == hoveredBolusId
                                    let r = isHL ? 7.0 : 3.5 + min(b.insulinDelivered * 1.6, 4.0)
                                    context.fill(
                                        Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                                        with: .color(isHL ? .blue : .blue.opacity(0.45))
                                    )
                                    if isHL {
                                        context.stroke(
                                            Path(ellipseIn: CGRect(x: pt.x - r - 1, y: pt.y - r - 1, width: (r + 1) * 2, height: (r + 1) * 2)),
                                            with: .color(.white.opacity(0.6)),
                                            lineWidth: 1.5
                                        )
                                    }
                                }
                                if let hb = hoveredBolus, let pt = chartProxy.position(for: (hb.date, hb.glucoseY)) {
                                    let r = 7.0 + min(hb.insulinDelivered * 1.6, 4.0)
                                    let text: String = {
                                        var parts = ["\(String(format: "%.1f", hb.insulinDelivered))U"]
                                        if let c = hb.carbAmount, c > 0 { parts.append("\(String(format: "%.0f", c))g") }
                                        if let t = hb.bolusType { parts.append(t) }
                                        return parts.joined(separator: " ")
                                    }()
                                    let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
                                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                                    let textSize = (text as NSString).size(withAttributes: attrs)
                                    let pad: CGFloat = 6
                                    let tipH: CGFloat = textSize.height + pad * 2
                                    let tipW: CGFloat = textSize.width + pad * 2 + 10
                                    let tipX = min(max(pt.x - tipW / 2, 4), size.width - tipW - 4)
                                    let tipY = pt.y - r - tipH - 6
                                    let bgRect = CGRect(x: tipX, y: tipY, width: tipW, height: tipH)
                                    let bgPath = Path(roundedRect: bgRect, cornerRadius: 4)
                                    context.fill(bgPath, with: .color(Color(nsColor: .windowBackgroundColor)))
                                    context.stroke(bgPath, with: .color(.secondary.opacity(0.4)), lineWidth: 1)
                                    context.draw(
                                        Text(text).foregroundColor(.primary).font(.system(size: 10, design: .monospaced)),
                                        at: CGPoint(x: tipX + tipW / 2, y: tipY + tipH / 2)
                                    )
                                }
                            }
                        }
                    }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let hoverLocation):
                                let hTime = chartProxy.value(atX: hoverLocation.x, as: Date.self)
                                data.forEach { entry in
                                    let date = entry.date
                                    let timeDiff = date.timeIntervalSince(hTime!)
                                    if timeDiff < 60 && timeDiff > 0 {
                                        if entry.forecastType == .none {
                                            hoveredValue = entry.value
                                            hoveredTime = entry.date
                                            hoveredTrend = entry.trend
                                            hoveredDelta = entry.delta
                                            basalRate = (g.provider as? TandemSource)?.basalSegments.filter { $0.date <= hTime! }.last?.actualRate
                                            if let br = basalRate { hoveredActualY = basalChartTop - (br / basalMaxRate) * basalVisibleOffset }
                                            let boluses = (g.provider as? TandemSource)?.bolusHistory ?? []
                                            hoveredInsulinIOB = ActiveInsulinChart.iob(at: hTime!, bolusHistory: boluses, diaHours: s.activeInsulinDIA)
                                            sharedHoverTime = hTime
                                            if let match = bolusEntries.first(where: { abs($0.date.timeIntervalSince(hTime!)) < 120 }) {
                                                hoveredBolusId = match.id
                                                hoveredBolus = match
                                            } else {
                                                hoveredBolusId = nil
                                                hoveredBolus = nil
                                            }
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
                                basalRate = nil
                                hoveredActualY = nil
                                hoveredBolusId = nil
                                hoveredBolus = nil
                                hoveredInsulinIOB = nil
                                sharedHoverTime = nil
                            }
                        }
            }.chartForegroundStyleScale(legendList
            ).chartLegend(s.aidChartShowForecast && s.aidChartForecastDisplay == .lines ? .visible : .hidden)
            .padding()
        }
        .onChange(of: sharedHoverTime) { ht in
            if let ht = ht {
                basalRate = (g.provider as? TandemSource)?.basalSegments.filter { $0.date <= ht }.last?.actualRate
            } else {
                basalRate = nil
            }
        }
    }
}

fileprivate struct BasalOverlayEntry: Identifiable {
    var id: UUID
    let date: Date
    let actualY: Double
}

extension GraphView {
    fileprivate static func basalOverlayEntries(g: Glucose, s: SettingsStore, maxY: Double, defaultMaxGlucose: Double, maxYMargin: Double, minY: Double, defaultMinGlucose: Double) -> [BasalOverlayEntry] {
        guard g.provider.type == .tandemsource, s.aidChartShowBasalOverlay else { return [] }
        let segs = (g.provider as? TandemSource)?.basalSegments ?? []
        guard !segs.isEmpty else { return [] }
        let chartMaxY = maxY >= defaultMaxGlucose ? (maxY + maxYMargin) : defaultMaxGlucose
        let chartMinY = minY <= defaultMinGlucose ? minY : defaultMinGlucose
        let visibleOffset = max(0, (200.0 / 350.0) * (chartMaxY - chartMinY))
        let maxBasal: Double = 5.0
        let filtered = segs.filter { $0.date > Date(timeIntervalSinceNow: TimeInterval(-s.graphMinutes * 60)) }
        return filtered.enumerated().map { i, seg in
            let ay = chartMaxY - (seg.actualRate / maxBasal) * visibleOffset
            return BasalOverlayEntry(id: seg.id, date: seg.date, actualY: ay)
        }
    }

    fileprivate struct BolusOverlayEntry {
        let id: UUID
        let date: Date
        let glucoseY: Double
        let insulinDelivered: Double
        let carbAmount: Double?
        let bolusType: String?
    }

    fileprivate static func bolusOverlayEntries(g: Glucose, s: SettingsStore, data: [GraphEntry]) -> [BolusOverlayEntry] {
        guard g.provider.type == .tandemsource, s.aidShowBolusHistory else { return [] }
        let boluses = (g.provider as? TandemSource)?.bolusHistory ?? []
        guard !boluses.isEmpty else { return [] }
        let start = Date(timeIntervalSinceNow: TimeInterval(-s.graphMinutes * 60))
        let filtered = boluses.filter { $0.date >= start }
        let cgm = data.filter { $0.forecastType == .none }.sorted(by: { $0.date < $1.date })
        guard !cgm.isEmpty else { return [] }
        let offsetY = convertGlucose(s, glucose: 25)
        return filtered.compactMap { bolus -> BolusOverlayEntry? in
            let gy: Double
            if let idx = cgm.firstIndex(where: { $0.date >= bolus.date }) {
                let e = cgm[idx]
                if idx > 0 {
                    let prev = cgm[idx - 1]
                    let dur = e.date.timeIntervalSince(prev.date)
                    gy = dur > 0 && dur < 600
                        ? prev.value + (e.value - prev.value) * (bolus.date.timeIntervalSince(prev.date) / dur)
                        : e.value
                } else { gy = e.value }
            } else { gy = cgm.last!.value }
            return BolusOverlayEntry(id: bolus.id, date: bolus.date, glucoseY: gy - offsetY, insulinDelivered: bolus.insulinDelivered, carbAmount: bolus.carbAmount, bolusType: bolus.bolusType)
        }
    }
}

#Preview {
    GraphView(glucose: Glucose(SettingsStore())).environmentObject(SettingsStore())
}
