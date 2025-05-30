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
    case librelinkup
    public var id: String { self.rawValue }
    public var presentable: String {
        switch self {
        case .null:
            return "No provider"
        case .simulator:
            return "Simulator"
        case .nightscout:
            return "Nightscout"
        case .dexcomshare:
            return "Dexcom Share"
        case .librelinkup:
            return "Libre LinkUp"
        }
    }
}

struct ProviderAuth: Decodable {
    var token: String
    var expiry: Double
}

struct GlucoseSourceExtraProperties {
    var iob: Double? = nil
    var cob: Double? = nil
    var eventualGlucose: Double? = nil
    var reason: String? = nil
    var forecasts: OpenAPSForecasts = OpenAPSForecasts(iob: nil, cob: nil, zt: nil, uam: nil)
}

struct OpenAPSForecasts: Decodable {
    var iob: [Int]?
    var cob: [Int]?
    var zt: [Int]?
    var uam: [Int]?
}

class Provider: ObservableObject, @unchecked Sendable {

    var type: CGMProvider = .null
    var isBaseProvider: Bool = true
    internal var readingInterval: Double = 300 // Seconds between readings
    internal var logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "provider")
    @Published var RemoteGlucoseSource: GlucoseSourceDevice = .null
    @Published var GlucoseEntries: [GlucoseEntry] = []
    @Published var GlucoseSourceExtras: GlucoseSourceExtraProperties = GlucoseSourceExtraProperties()
    @Published public var providerIssue: String?
    @Published public var lastFetch: Date = Date().addingTimeInterval(TimeInterval(-5*60))

    // TODO: How to move this out of this file and keep it accessible for Settings UI?
//    @Published var connections: [LibreLinkUp.LibreLinkUpConnectionsResponse] = []
    @Published var connectionID: String = ""

    init() {
        if self.isBaseProvider {
            return
        }
        
        Task {
            await self.fetch()
        }
        startTimer()
    }
    
    internal func startTimer() {
        let _ = Timer.publish(every: readingInterval, on: .main, in: .default)
    }
    
    func verifyCredentials() async -> Bool {
        return true
    }
    
    func getCurrent() -> GlucoseEntry {
        return GlucoseEntries.count > 0 ? GlucoseEntries[0] : GlucoseEntry(glucose: 1, date: Date(), changeRate: 0.0)
    }
    
    func getData(completion: @escaping ([GlucoseEntry]) -> Void) {
        completion(GlucoseEntries)
    }

    func isAuthValid() -> Bool {
        return false
    }

//    @MainActor @ViewBuilder
//    func getConnectionView(s: SettingsStore) -> some View {
//        @ObservedObject var settings: SettingsStore = s
//
//        Picker("", selection: $settings.libreConnectionID) {
//            ForEach(self.connections, id: \.patientID) {
//                Text("\($0.firstName) \($0.lastName)").tag($0.patientID)
//            }
//        }
//    }
    
    internal func fetch() async {
        self.logger.error("Base fetch function called. This should only happen once. Multiple occurrences of this message means that your CGM provider implementation does not have it's own `fetch` implementation.")
        // Should be implemented in the discrete providers
    }
}
