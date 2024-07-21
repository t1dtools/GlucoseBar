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

class Provider: ObservableObject, @unchecked Sendable {

    var type: CGMProvider = .null
    internal var readingInterval: Double = 300 // Seconds between readings
    internal var logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "provider")
    @Published var GlucoseEntries: [GlucoseEntry] = []
    @Published public var providerIssue: String?
    @Published public var lastFetch: Date = Date().addingTimeInterval(TimeInterval(-5*60))

    // TODO: How to move this out of this file and keep it accessible for Settings UI?
    @Published var connections: [LibreLinkUp.LibreLinkUpConnectionsResponse] = []
    @Published var connectionID: String = ""

    init() {
        Task {
            await self.fetch()
        }
        startTimer()
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

    @ViewBuilder
    func getConnectionView(s: SettingsStore) -> some View {
        @ObservedObject var settings: SettingsStore = s

        Picker("", selection: $settings.libreConnectionID) {
            ForEach(self.connections, id: \.patientID) {
                Text("\($0.firstName) \($0.lastName)").tag($0.patientID)
            }
        }
    }

    internal func startTimer() {
        let _ = Timer.publish(every: readingInterval, on: .main, in: .default)
    }
    
    internal func fetch() async {
        self.logger.error("Base fetch function called. This should only happen once. Multiple occurrences of this message means that your CGM provider implementation does not have it's own `fetch` implementation.")
        // Should be implemented in the discrete providers
    }
}
