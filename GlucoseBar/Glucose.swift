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
import Combine

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
    @ObservedObject var vs: ViewState

    private var providerCancellable: AnyCancellable?
    private var timer: DispatchTimer
    private var isFetching: Bool = false
    private let fetchQueue = DispatchQueue(label: "tools.t1d.GlucoseBar.fetchQueue")
    private var notificationObserver: NSObjectProtocol?

    let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "glucose")
    let notificationCenter = NotificationCenter.default

    public init(_ settingsStore: SettingsStore, viewState: ViewState = ViewState()) {
        provider = Provider()
        settings = SettingsStore()
        vs = viewState

        timer = DispatchTimer(timeInterval: 15, queue: DispatchQueue(label: "tools.t1d.GlucoseBar.CGMQueue"))
        timer.suspend()
        timer.eventHandler = timerEventHandler
        timer.resume()

        setSettings(settingsStore)

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
        // This handler is invoked from the background CGMQueue DispatchQueue, but
        // Glucose is @MainActor-isolated. Hop to the main actor before touching any
        // published or stored properties to eliminate the data race.
        Task { @MainActor in
            if self.settings.cgmProvider != self.provider.type {
                self.setSettings(settings)
            }
            var shouldFetch: Bool = false
            if !vs.isOnline {
                self.logger.dlog("Aborting fetch because network is offline", category: "glucose", level: .default)
                return
            }

            if self.provider.lastFetch.timeIntervalSinceNow <= -60 {
                shouldFetch = true
                self.logger.dlog("Glucose.timer initiating fetch because last fetch was over 1 minute ago", category: "glucose", level: .default)
            }

            if let entries = self.entries, let firstEntry = entries.first {
                if firstEntry.date.timeIntervalSinceNow <= -300 && self.provider.lastFetch.timeIntervalSinceNow <= -10 {
                    shouldFetch = true
                    self.logger.dlog("Glucose.timer initiating fetch because latest reading is over 5 minutes old and last fetch was over 10 seconds ago", category: "glucose", level: .default)
                }
            }

            if shouldFetch {
                fetchQueue.async { [weak self] in
                    guard let self = self else { return }
                    Task {
                        let alreadyFetching = await MainActor.run { self.isFetching }
                        if alreadyFetching {
                            await MainActor.run { self.logger.dlog("Skipping fetch - already in progress", category: "glucose", level: .debug) }
                            return
                        }
                        await MainActor.run { self.isFetching = true }
                        defer { Task { await MainActor.run { self.isFetching = false } } }
                        await self.provider.fetch()
                    }
                }
            }

            self.getGlucose()
        }
    }

    /// Subscribe `providerCancellable` to the current provider's `objectWillChange`.
    /// Must be called every time `self.provider` is replaced (both in `setSettings` and `reset`).
    private func subscribeToProvider() {
        self.providerCancellable = self.provider.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.getGlucose()
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

        // Re-subscribe to the new provider's changes (was missing before this fix,
        // causing the menu bar to never update after a reset).
        subscribeToProvider()

        timer = DispatchTimer(timeInterval: 15, queue: DispatchQueue(label: "tools.t1d.GlucoseBar.CGMQueue"))
        timer.suspend()
        timer.eventHandler = timerEventHandler
        timer.resume()

        // Re-register notifications after reset
        if let observer = notificationObserver {
            notificationCenter.removeObserver(observer)
        }
        registerForNotifications()

        self.logger.dlog("Reset glucose object", category: "glucose", level: .default)
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

        guard self.settings !== settings else { return }

        self.settings = settings

        switch settings.cgmProvider {
        case .nightscout:
            vs.providerURL = URL(string: settings.nsURL)
        case .dexcomshare:
            vs.providerURL = URL(string: settings.dxServer.url)
        default:
            vs.providerURL = nil
        }

        self.logger.dlog("Current provider before provider comparison: \(String(describing: self.provider))", category: "glucose", level: .debug)
        if self.provider.type != settings.cgmProvider {
            self.logger.dlog("found provider \(self.provider.type.presentable) != \(settings.cgmProvider.presentable)", category: "glucose", level: .debug)

            switch settings.cgmProvider {
            case .nightscout:
                self.provider = Nightscout(baseURL: settings.nsURL, token: settings.nsSecret, aidEnabled: settings.aidEnableIntegration)
            case .dexcomshare:
                self.provider = DexcomShare(username: settings.dxEmail, password: settings.dxPassword, server: settings.dxServer)
            case .simulator:
                self.provider = Simulator("simulate")
            default:
                self.logger.dlog("Unknown provider. Please add in setSettings in Glucose.swift", category: "glucose", level: .error)
            }

            // Subscribe to the newly assigned provider's changes
            subscribeToProvider()

        }

        Task {
            self.getGlucose()
        }
        self.logger.dlog("Current provider after provider comparison and lookup: \(String(describing: self.provider))", category: "glucose", level: .debug)
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
                self.logger.dlog("GlucoseEntries became empty in main dispatch block", category: "glucose", level: .error)
                return
            }

            let ge = glucoseEntries[0]
            if self.glucose != ge.glucose {
                self.glucose = ge.glucose
            }

            if self.glucoseTime != ge.date {
                self.glucoseTime = ge.date
            }

            if self.trend != ge.trend?.arrows ?? "" {
                self.trend = ge.trend?.arrows ?? ""
            }

            if self.entries != glucoseEntries {
                self.entries = glucoseEntries
            }

            // In cases where users have duplicate entries in their glucose source
            // this will correctly find the delta based on time.
            let newDelta: Double = {
                let current = glucoseEntries[0]
                let reference = glucoseEntries.dropFirst().first(where: {
                    current.date.timeIntervalSince($0.date) > 30
                })
                return reference.map { current.glucose - $0.glucose } ?? 0.0
            }()

            if self.delta != newDelta {
                self.delta = newDelta
            }

            self.glucoseAge = formatter.localizedString(for: glucoseEntries[0].date, relativeTo: Date())

            if !self.fetchedGlucose {
                self.fetchedGlucose = true
            }
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
