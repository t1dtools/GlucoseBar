//
//  Glucose.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-09-24.
//

import Foundation
import SwiftUI
import CryptoKit
import OSLog

class Glucose: ObservableObject, Sendable {

    @Published var glucose: Double = 0.0
    @Published var delta: Double = 0.0
    @Published var glucoseTime: Date = Date()
    @Published var glucoseAge: String = ""
    @Published var trend: String = ""
    @Published var fetchedGlucose: Bool = false
    @Published var entries: [GlucoseEntry]? = nil

    @Published var error: String = ""

    @Published var provider: Provider
    @ObservedObject var settings: SettingsStore
    @ObservedObject var vs: ViewState = ViewState()

    private var timer: DispatchTimer

    let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "glucose")
    let notificationCenter = NotificationCenter.default

    public init() {
        provider = Provider()
        settings = SettingsStore()

        timer = DispatchTimer(timeInterval: 5, queue: DispatchQueue(label: "tools.t1d.GlucoseBar.CGMQueue"))
        timer.suspend()
        timer.eventHandler = { [self] in

            if self.settings.cgmProvider != self.provider.type {
                self.setSettings(settings)
            }
            var shouldFetch: Bool = false
            if !vs.isOnline {
                shouldFetch = false
                self.logger.info("Aborting fetch because network is offline")
                return
            }

            if self.provider.lastFetch.timeIntervalSinceNow <= -60 {
                shouldFetch = true
                self.logger.info("Glucose.timer initiating fetch because last fetch was over 1 minute ago")
            }

            if self.entries != nil && self.entries!.first != nil {
                if self.entries!.first!.date.timeIntervalSinceNow <= -300 && self.provider.lastFetch.timeIntervalSinceNow <= -10 {
                    shouldFetch = true
                    self.logger.info("Glucose.timer initiating fetch because latest reading is over 5 minutes old and last fetch was over 10 seconds ago")
                }
            }

            if shouldFetch {
                Task {
                    await self.provider.fetch()
                }
            }

            DispatchQueue.main.async {
                self.getGlucose()
            }
        }
        timer.resume()

        registerForNotifications()
    }

    func registerForNotifications() {
        notificationCenter
            .addObserver(forName: .computerDidWakeUp,
                         object: nil,
                         queue: nil) {(notification) in
                DispatchQueue.main.async {
                    self.getGlucose()
                }
        }
    }

    public func setSettings(_ settings: SettingsStore) {
        self.settings = settings

        self.logger.debug("Current provider before provider comparison: \(String(describing: self.provider))")
        if self.provider.type != settings.cgmProvider {
            self.logger.debug("found provider \(self.provider.type.presentable) != \(settings.cgmProvider.presentable)")

            DispatchQueue.main.async {
                switch settings.cgmProvider {
                case .nightscout:
                    self.provider = Nightscout(baseURL: settings.nsURL, token: settings.nsSecret)
                case .dexcomshare:
                    self.provider = DexcomShare(username: settings.dxEmail, password: settings.dxPassword, server: settings.dxServer)
                case .librelinkup:
                    self.provider = LibreLinkUp(username: settings.libreUsername, password: settings.librePassword)
                case .simulator:
                    self.provider = Simulator("simulate")
                default:
                    self.logger.error("Unknown provider. Please add in setSettings in Glucose.swift")
                }
            }
        }

        DispatchQueue.main.async {
            self.getGlucose()
        }
        self.logger.debug("Current provider after provider comparison and lookup: \(String(describing: self.provider))")
    }

    func reload() {
        self.getGlucose()
    }

    func getGlucose() {
        self.error = ""
        if self.provider.providerIssue != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.error = self.provider.providerIssue ?? "Unknown provider issue"
                return
            }
        }

        let glucoseEntries = self.provider.GlucoseEntries

        if glucoseEntries.isEmpty {
            return
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.formattingContext = .listItem

        DispatchQueue.main.async {
            self.glucose = glucoseEntries[0].glucose
            self.glucoseTime = glucoseEntries[0].date
            self.trend = glucoseEntries[0].trend?.arrows ?? ""
            self.entries = glucoseEntries

            if glucoseEntries.count > 1 {
                self.delta = glucoseEntries[0].glucose - glucoseEntries[1].glucose
            }

            self.glucoseAge = formatter.localizedString(for: glucoseEntries[0].date, relativeTo: Date())
            self.fetchedGlucose = true
        }
    }
}

extension Digest {
    var bytes: [UInt8] { Array(makeIterator()) }
    var data: Data { Data(bytes) }

    var hexStr: String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}
