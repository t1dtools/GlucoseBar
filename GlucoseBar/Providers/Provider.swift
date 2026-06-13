//
//  CGMProvider.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-10-16.
//

import Foundation
import OSLog
import SwiftUI

public enum CGMProvider: String, CaseIterable, Identifiable {
    case null
    case simulator
    case nightscout
    case dexcomshare
    public var id: String { self.rawValue }
    public var presentable: String {
        switch self {
        case .null:
            return String(localized: "No provider", comment: "The name for when no CGM data provider has been chosen yet")
        case .simulator:
            return String(localized: "Simulator", comment: "The name for the Simulator CGM data provider")
        case .nightscout:
            return String(localized: "Nightscout", comment: "The name for the Nightscout CGM data provider")
        case .dexcomshare:
            return String(localized: "Dexcom Share", comment: "The name for the Dexcom Share CGM data provider")
        }
    }
}

struct ProviderAuth: Decodable {
    var token: String
    var expiry: Double
}

struct GlucoseSourceExtraProperties {
    var aid: GlucoseSourceDevice = .null
    var iob: Double? = nil
    var cob: Double? = nil
    var eventualGlucose: Double? = nil
    var reason: String? = nil
    var enactedAt: Date? = nil
    var forecasts: AIDForecasts = AIDForecasts(iob: nil, cob: nil, zt: nil, uam: nil)
    var glucoseTarget: Double? = nil
    var error: String? = nil
}

struct AIDForecasts: Decodable {
    var iob: [Int]?
    var cob: [Int]?
    var zt: [Int]?
    var uam: [Int]?
    var loop: [Int]?

    static func fromPredBGs(predBGs: PredBGs?) -> AIDForecasts {
        return AIDForecasts(
            iob: predBGs?.iob,
            cob: predBGs?.cob,
            zt: predBGs?.zt,
            uam: predBGs?.uam
        )
    }

    static func fromLoopPredicted(_ loopPredicted: LoopPredicted?) -> AIDForecasts {
        let loopValues: [Int]? = {
            guard var values = loopPredicted?.values else { return nil }
            values.removeFirst()
            return values.map {
                Int(($0).rounded())
            }
        }()
        return AIDForecasts(loop: loopValues)
    }
}

class Provider: ObservableObject, @unchecked Sendable {

    var type: CGMProvider = .null
    var isBaseProvider: Bool = true
    internal var readingInterval: Double = 300 // Seconds between readings
    internal var logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "provider")
    @Published var RemoteGlucoseSource: GlucoseSourceDevice = .null
    @Published private var _glucoseEntries: [GlucoseEntry] = []
    private let glucoseEntriesQueue = DispatchQueue(label: "tools.t1d.GlucoseBar.glucoseEntries", attributes: .concurrent)
    @Published var GlucoseSourceExtras: GlucoseSourceExtraProperties = GlucoseSourceExtraProperties()
    @Published public var providerIssue: String?
    @Published public var lastFetch: Date = Date().addingTimeInterval(TimeInterval(-5*60))
    @Published public var isAuthenticating: Bool = false
    @Published var auth: ProviderAuth?

    @Published var connectionID: String = ""

    init() {
        if self.isBaseProvider {
            return
        }

        startTimer()
    }

    // Thread-safe getter for GlucoseEntries
    var GlucoseEntries: [GlucoseEntry] {
        get {
            return glucoseEntriesQueue.sync {
                return _glucoseEntries
            }
        }
    }

    // Thread-safe setter for GlucoseEntries - must be called from main thread for UI updates
    func setGlucoseEntries(_ entries: [GlucoseEntry]) {
        glucoseEntriesQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self._glucoseEntries = entries
        }

        // Update UI on main thread
        Task { [weak self] in
            guard let self = self else { return }
            self.objectWillChange.send()
        }
    }

    // Thread-safe method to get a safe copy of entries for UI use
    func getSafeGlucoseEntries() -> [GlucoseEntry] {
        return glucoseEntriesQueue.sync {
            return Array(_glucoseEntries) // Create a copy
        }
    }

    internal func startTimer() {
        let _ = Timer.publish(every: readingInterval, on: .main, in: .default)
    }

    func verifyCredentials() async -> Bool {
        return true
    }

    func getCurrent() -> GlucoseEntry {
        let entries = getSafeGlucoseEntries()
        return entries.count > 0 ? entries[0] : GlucoseEntry(glucose: 1, date: Date(), changeRate: 0.0)
    }

    func getData(completion: @escaping ([GlucoseEntry]) -> Void) {
        completion(getSafeGlucoseEntries())
    }

    func isAuthValid() -> Bool {
        return false
    }

    internal func fetch() async {
        self.logger.dlog("Base fetch function called. This should not happen. Occurrences of this message means that your CGM provider implementation does not have it's own `fetch` implementation, or that no provider is configured.", category: "provider", level: .error)
        // Should be implemented in the discrete providers
    }
}
