//
//  CarbsOnBoardChart.swift
//  GlucoseBar
//

import SwiftUI
import Charts

struct CarbsOnBoardChart: View {
    let bolusHistory: [BolusRecord]
    let graphMinutes: Int
    let absorptionHours: Double
    let isVisible: Bool
    let glucoseStart: Date?
    let glucoseEnd: Date?
    @Binding var hoverTime: Date?

    var body: some View {
        if !isVisible || bolusHistory.isEmpty {
            return AnyView(EmptyView())
        }

        let now = Date()
        let start = Date(timeIntervalSinceNow: TimeInterval(-graphMinutes * 60))
        let dataStart = glucoseStart ?? start
        let end = glucoseEnd ?? now
        let data = computeCOB(start: dataStart, end: end)
        let maxCOB = data.max(by: { $0.value < $1.value })?.value ?? 0

        let yMax = max(maxCOB, 1.0) * 1.1
        let hoverValue: Double? = hoverTime.flatMap { ht in data.first(where: { abs($0.date.timeIntervalSince(ht)) < 150 })?.value }

        return AnyView(
            VStack(spacing: 0) {
                ZStack {
                    Chart {
                        ForEach(data) { pt in
                            AreaMark(
                                x: .value("Time", pt.date),
                                y: .value("COB", pt.value)
                            )
                            .foregroundStyle(.orange.opacity(0.12))
                        }
                        ForEach(data) { pt in
                            LineMark(
                                x: .value("Time", pt.date),
                                y: .value("COB", pt.value)
                            )
                            .foregroundStyle(.orange)
                        }
                        if let ht = hoverTime {
                            RuleMark(x: .value("Hov", ht))
                                .foregroundStyle(.orange.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                        }
                        if let ht = hoverTime, let hv = hoverValue {
                            PointMark(x: .value("Hx", ht), y: .value("Hy", hv))
                                .foregroundStyle(.orange)
                                .symbolSize(30)
                        }
                    }
                    .chartYScale(domain: [0, yMax])
                    .chartXScale(domain: [dataStart, end])
                    .chartXAxis {}
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(String(format: "%.0f", v))").font(.caption2).monospacedDigit().frame(width: 35, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .chartOverlay { chartProxy in
                        Color.clear
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    guard let hTime = chartProxy.value(atX: loc.x, as: Date.self),
                                          hTime >= dataStart, hTime <= end else { return }
                                    hoverTime = hTime
                                case .ended:
                                    hoverTime = nil
                                }
                            }
                    }
                    .frame(height: 60).padding(.horizontal)
                    HStack {
                        VStack {
                            Text("ESTIMATED").font(.caption2).foregroundColor(.secondary).opacity(0.7).padding(.horizontal)
                            Spacer()
                        }
                        Spacer()

                    }
                }
            }
        .frame(height: 70)
        )
    }

    static func cob(at date: Date, bolusHistory: [BolusRecord], absorptionHours: Double) -> Double {
        let absorptionSeconds = absorptionHours * 3600
        var cob: Double = 0
        for bolus in bolusHistory where bolus.date < date {
            guard let carbs = bolus.carbAmount, carbs > 0 else { continue }
            let elapsed = date.timeIntervalSince(bolus.date)
            if elapsed < 0 || elapsed > absorptionSeconds { continue }
            cob += carbs * (1 - elapsed / absorptionSeconds)
        }
        return cob
    }

    private func computeCOB(start: Date, end: Date) -> [COBPoint] {
        let absorptionSeconds = absorptionHours * 3600
        var points: [COBPoint] = []
        var t = start
        while t <= end {
            var cob: Double = 0
            for bolus in bolusHistory where bolus.date < t {
                guard let carbs = bolus.carbAmount, carbs > 0 else { continue }
                let elapsed = t.timeIntervalSince(bolus.date)
                if elapsed < 0 || elapsed > absorptionSeconds { continue }
                cob += carbs * (1 - elapsed / absorptionSeconds)
            }
            points.append(COBPoint(date: t, value: cob))
            t = t.addingTimeInterval(300)
        }
        return points
    }

    private struct COBPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }
}
