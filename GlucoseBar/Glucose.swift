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

@MainActor
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
    private var isFetching: Bool = false
    private let fetchQueue = DispatchQueue(label: "tools.t1d.GlucoseBar.fetchQueue")
    private var notificationObserver: NSObjectProtocol?

    let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "glucose")
    let notificationCenter = NotificationCenter.default

    public init(_ settingsStore: SettingsStore) {
        provider = Provider()
        settings = SettingsStore()

        timer = DispatchTimer(timeInterval: 15, queue: DispatchQueue(label: "tools.t1d.GlucoseBar.CGMQueue"))
        timer.suspend()
        timer.eventHandler = timerEventHandler
        timer.resume()

        registerForNotifications()
    }

    @MainActor
    deinit {
        timer.suspend()
        if let observer = notificationObserver {
            notificationCenter.removeObserver(observer)
            notificationObserver = nil
        }
    }

    func timerEventHandler() {
        if self.settings.cgmProvider != self.provider.type {
            self.setSettings(settings)
        }
        var shouldFetch: Bool = false
        if !vs.isOnline {
            self.logger.notice("Aborting fetch because network is offline")
            return
        }

        if self.provider.lastFetch.timeIntervalSinceNow <= -60 {
            shouldFetch = true
            self.logger.notice("Glucose.timer initiating fetch because last fetch was over 1 minute ago")
        }

        if let entries = self.entries, let firstEntry = entries.first {
            if firstEntry.date.timeIntervalSinceNow <= -300 && self.provider.lastFetch.timeIntervalSinceNow <= -10 {
                shouldFetch = true
                self.logger.notice("Glucose.timer initiating fetch because latest reading is over 5 minutes old and last fetch was over 10 seconds ago")
            }
        }

        if shouldFetch {
            fetchQueue.async { [weak self] in
                guard let self = self else { return }
                Task {
                    let alreadyFetching = await MainActor.run { self.isFetching }
                    if alreadyFetching {
                        await MainActor.run { self.logger.debug("Skipping fetch - already in progress") }
                        return
                    }
                    await MainActor.run { self.isFetching = true }
                    defer { Task { await MainActor.run { self.isFetching = false } } }
                    await self.provider.fetch()
                }
            }
        }

        Task {
            self.getGlucose()
        }
    }

    func reset(_ settings: SettingsStore) {

        self.setSettings(settings)
        self.entries = nil
        self.fetchedGlucose = false
        self.glucose = 0.0
        self.delta = 0.0
        self.glucoseTime = Date()
        self.glucoseAge = ""
        self.trend = ""

        // Load provider
        switch settings.cgmProvider {
            case .dexcomshare:
            provider = DexcomShare(username: settings.dxEmail, password: settings.dxPassword, server: settings.dxServer)
        case .nightscout:
            provider = Nightscout(baseURL: settings.nsURL, token: settings.nsSecret, aidEnabled: settings.aidEnableIntegration)
        default:
            provider = Simulator("defaulted")
        }

        timer = DispatchTimer(timeInterval: 15, queue: DispatchQueue(label: "tools.t1d.GlucoseBar.CGMQueue"))
        timer.suspend()
        timer.eventHandler = timerEventHandler
        timer.resume()

        // Re-register notifications after reset
        if let observer = notificationObserver {
            notificationCenter.removeObserver(observer)
        }
        registerForNotifications()

        self.logger.notice("Reset glucose object")
    }

    func registerForNotifications() {
        notificationObserver = notificationCenter.addObserver(
            forName: .computerDidWakeUp,
            object: nil,
            queue: .main,
            using: { [weak self] notification in
                guard let self = self else { return }
                Task { @MainActor in
                    self.getGlucose()
                }
            })
    }

    public func setSettings(_ settings: SettingsStore) {
        self.settings = settings

        self.logger.debug("Current provider before provider comparison: \(String(describing: self.provider))")
        if self.provider.type != settings.cgmProvider {
            self.logger.debug("found provider \(self.provider.type.presentable) != \(settings.cgmProvider.presentable)")

            Task {
                switch settings.cgmProvider {
                case .nightscout:
                    self.provider = Nightscout(baseURL: settings.nsURL, token: settings.nsSecret, aidEnabled: settings.aidEnableIntegration)
                case .dexcomshare:
                    self.provider = DexcomShare(username: settings.dxEmail, password: settings.dxPassword, server: settings.dxServer)
                case .simulator:
                    self.provider = Simulator("simulate")
                default:
                    self.logger.error("Unknown provider. Please add in setSettings in Glucose.swift")
                }
            }
        }

        Task {
            self.getGlucose()
        }
        self.logger.debug("Current provider after provider comparison and lookup: \(String(describing: self.provider))")
    }

    func reload() {
        self.getGlucose()
    }

    func getGlucose() {
        self.error = ""
        if let providerIssue = self.provider.providerIssue {
            Task { [weak self] in
                guard let self = self else { return }
                self.error = providerIssue
                return
            }
        }

        // Get a thread-safe copy of glucose entries
        let glucoseEntries = self.provider.getSafeGlucoseEntries()

        if glucoseEntries.isEmpty {
            return
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.formattingContext = .listItem

        Task { [weak self] in
            guard let self = self else { return }

            guard !glucoseEntries.isEmpty else {
                self.logger.warning("GlucoseEntries became empty in main dispatch block")
                return
            }

            self.glucose = glucoseEntries[0].glucose
            self.glucoseTime = glucoseEntries[0].date
            self.trend = glucoseEntries[0].trend?.arrows ?? ""
            self.entries = glucoseEntries

            if glucoseEntries.count > 1 {
                self.delta = glucoseEntries[0].glucose - glucoseEntries[1].glucose
            } else {
                self.delta = 0.0
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
