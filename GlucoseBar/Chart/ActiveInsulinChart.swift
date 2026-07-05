//
//  ActiveInsulinChart.swift
//  GlucoseBar
//

import SwiftUI
import Charts

struct ActiveInsulinChart: View {
    let bolusHistory: [BolusRecord]
    let graphMinutes: Int
    let diaHours: Double
    let isVisible: Bool
    let glucoseStart: Date?
    let glucoseEnd: Date?
    @Binding var hoveredIOB: Double?
    @Binding var hoverTime: Date?

    static func iob(at date: Date, bolusHistory: [BolusRecord], diaHours: Double) -> Double {
        let tau = diaHours * 3600 / log(2)
        var iob: Double = 0
        for bolus in bolusHistory where bolus.date < date {
            let elapsed = date.timeIntervalSince(bolus.date)
            if elapsed < 0 { continue }
            iob += bolus.insulinDelivered * exp(-elapsed / tau)
        }
        return iob
    }

    var body: some View {
        if !isVisible || bolusHistory.isEmpty { return AnyView(EmptyView()) }

        let now = Date()
        let tau = diaHours * 3600 / log(2)
        let start = Date(timeIntervalSinceNow: TimeInterval(-graphMinutes * 60))
        let dataStart = glucoseStart ?? start
        let end = glucoseEnd ?? now
        let data = computeIOB(now: now, tau: tau, start: dataStart, end: end)

        guard let maxIOB = data.max(by: { $0.value < $1.value })?.value, maxIOB > 0 else {
            return AnyView(EmptyView())
        }

        let yMax = max(maxIOB, 1.0) * 1.1
        let hoverValue: Double? = hoverTime.flatMap { ht in data.first(where: { abs($0.date.timeIntervalSince(ht)) < 150 })?.value }

        return AnyView(
            VStack(spacing: 0) {
                Divider().padding(.horizontal)
                Chart {
                    ForEach(data) { pt in
                        AreaMark(
                            x: .value("Time", pt.date),
                            y: .value("IOB", pt.value)
                        )
                        .foregroundStyle(.blue.opacity(0.12))
                        .interpolationMethod(.cardinal)
                    }
                    ForEach(data) { pt in
                        LineMark(
                            x: .value("Time", pt.date),
                            y: .value("IOB", pt.value)
                        )
                        .foregroundStyle(.blue)
                    }
                    if let ht = hoverTime {
                        RuleMark(x: .value("Hov", ht))
                            .foregroundStyle(.blue.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                    if let ht = hoverTime, let hv = hoverValue {
                        PointMark(x: .value("Hx", ht), y: .value("Hy", hv))
                            .foregroundStyle(.blue)
                            .symbolSize(30)
                    }
                }
                .chartYScale(domain: [0, yMax])
                .chartXScale(domain: [dataStart, end])
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.hour().minute()).font(.caption2)
                            }
                            AxisGridLine()
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(String(format: "%.1f", v))").font(.caption2)
                            }
                        }
                    }
                }
                .chartOverlay { chartProxy in
                    Color.clear
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                guard let hTime = chartProxy.value(atX: loc.x, as: Date.self) else { return }
                                if let pt = data.first(where: { abs($0.date.timeIntervalSince(hTime)) < 150 }) {
                                    hoveredIOB = pt.value
                                    hoverTime = pt.date
                                }
                            case .ended:
                                hoveredIOB = nil
                                hoverTime = nil
                            }
                        }
                }
                .frame(height: 60).padding(.horizontal)
            }
        .frame(height: 70)
        )
    }

    private func computeIOB(now: Date, tau: Double, start: Date, end: Date) -> [IOBPoint] {
        var points: [IOBPoint] = []
        var t = start
        while t <= end {
            var iob: Double = 0
            for bolus in bolusHistory where bolus.date < t {
                let elapsed = t.timeIntervalSince(bolus.date)
                if elapsed < 0 { continue }
                iob += bolus.insulinDelivered * exp(-elapsed / tau)
            }
            points.append(IOBPoint(date: t, value: iob))
            t = t.addingTimeInterval(300)
        }
        return points
    }

    private struct IOBPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }
}
