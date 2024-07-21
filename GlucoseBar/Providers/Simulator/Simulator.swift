//
//  Simulator.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-10-16.
//

import Foundation

class Simulator: Provider {

    init(_ input: String?) {
        super.init()
        self.type = .simulator
    }

    override internal func fetch() async {

        self.lastFetch = Date()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            var previousEntry: GlucoseEntry? = nil
            if !self.GlucoseEntries.isEmpty {
                previousEntry = self.GlucoseEntries.first
            }

            if self.GlucoseEntries.isEmpty {
                while self.GlucoseEntries.count < 288 {

                    if !self.GlucoseEntries.isEmpty {
                        previousEntry = self.GlucoseEntries.first
                    }
                    //                    DispatchQueue.main.async {
                    self.GlucoseEntries.insert(self.generateGlucoseEntry(previousEntry: previousEntry), at: 0)
                    //                    }
                }
            } else {
                //                DispatchQueue.main.async {
                self.GlucoseEntries.insert(self.generateGlucoseEntry(previousEntry: previousEntry), at: 0)
                //                }
            }

            if self.GlucoseEntries.count > 288 {
                //                DispatchQueue.main.async {
                self.GlucoseEntries.remove(at: self.GlucoseEntries.count - 1)
                //                }
            }
        }
    }

    private func generateGlucoseEntry(previousEntry: GlucoseEntry?) -> GlucoseEntry {
        var base = 100.0
        var trend = GlucoseEntry.GlucoseTrend.flat
        var date = Date()
        var delta = 0.0
        var range = -20...20
        if previousEntry != nil {
            trend = previousEntry!.trend!
            base = previousEntry!.glucose
            date = previousEntry!.date.addingTimeInterval(300)

            switch trend {
            case GlucoseEntry.GlucoseTrend.downDownDown:
                range = -20 ... -10
            case GlucoseEntry.GlucoseTrend.downDown:
                range = -15 ... -5
            case GlucoseEntry.GlucoseTrend.down:
                range = -10...0
            case GlucoseEntry.GlucoseTrend.flat:
                range = -5...5
            case GlucoseEntry.GlucoseTrend.up:
                range = 0...10
            case GlucoseEntry.GlucoseTrend.upUp:
                range = 5...15
            case GlucoseEntry.GlucoseTrend.upUpUp:
                range = 10...20
            default:
                range = -20...20
            }

            trend = getValidTrend(trend)

            self.logger.info("Range based on previousEntry: \(range) - \(trend.arrows)")
        }


        let change = Double(Int.random(in: range))
        var glucose = base + change
        if glucose < 40 {
            glucose = base
            trend = .upUpUp
        }

        if glucose > 300 {
            glucose = base
            trend = .downDownDown
        }
        
        if previousEntry != nil {
            delta = glucose - previousEntry!.glucose
        }

        return GlucoseEntry(glucose: glucose, date: date, trend: trend, changeRate: delta)
    }

    override internal func verifyCredentials() async -> Bool {
        return true
    }

    func getValidTrend(_ trend: GlucoseEntry.GlucoseTrend) -> GlucoseEntry.GlucoseTrend {
        var validTrends: [GlucoseEntry.GlucoseTrend] = []
        switch (trend) {
        case .downDownDown:
            validTrends.append(.downDown)
        case .downDown:
            validTrends.append(.downDownDown)
            validTrends.append(.downDown)
            validTrends.append(.down)
        case .down:
            validTrends.append(.down)
            validTrends.append(.downDown)
            validTrends.append(.flat)
        case .flat:
            validTrends.append(.down)
            validTrends.append(.flat)
            validTrends.append(.up)
        case .up:
            validTrends.append(.flat)
            validTrends.append(.up)
            validTrends.append(.upUp)
        case .upUp:
            validTrends.append(.up)
            validTrends.append(.upUp)
            validTrends.append(.upUpUp)
        case .upUpUp:
            validTrends.append(.upUp)

        default:
            validTrends.append(.flat)
        }

        return validTrends.randomElement()!
    }

}
