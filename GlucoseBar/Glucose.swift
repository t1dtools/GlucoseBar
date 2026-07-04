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

    var sourceIndex: Int = -1
    let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "glucose")

    func plog(_ message: String, level: OSLogType = .default) {
        let taggedCategory = sourceIndex < 0 ? "glucose" : "glucose/\(sourceIndex)"
        let cat = sourceIndex < 0 ? "glucose" : "glucose/\(sourceIndex)"
        Logger(subsystem: "tools.t1d.GlucoseBar", category: cat)
            .dlog(message, category: taggedCategory, level: level)
    }
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

    nonisolated func timerEventHandler() {
        Task { @MainActor in
            if self.settings.cgmProvider != self.provider.type {
                self.setSettings(settings)
            }
            var shouldFetch: Bool = false
            if !vs.isOnline {
                self.plog("Aborting fetch because network is offline", level: .default)
                return
            }

            if self.provider.lastFetch.timeIntervalSinceNow <= -180 {
                shouldFetch = true
                self.plog("Glucose.timer initiating fetch because last fetch was over 1 minute ago", level: .default)
            }

            if let entries = self.entries, let firstEntry = entries.first {
                if firstEntry.date.timeIntervalSinceNow <= -300 && self.provider.lastFetch.timeIntervalSinceNow <= -10 {
                    shouldFetch = true
                    self.plog("Glucose.timer initiating fetch because latest reading is over 5 minutes old and last fetch was over 10 seconds ago", level: .default)
                }
            }

            if shouldFetch {
                fetchQueue.async { [weak self] in
                    guard let self = self else { return }
                    Task {
                        let alreadyFetching = await MainActor.run { self.isFetching }
                        if alreadyFetching {
                            await MainActor.run { self.plog("Skipping fetch - already in progress", level: .debug) }
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

        switch settings.cgmProvider {
            case .dexcomshare:
            provider = DexcomShare(username: settings.dxEmail, password: settings.dxPassword, server: settings.dxServer)
        case .nightscout:
            provider = Nightscout(baseURL: settings.nsURL, token: settings.nsSecret, aidEnabled: settings.aidEnableAID)
        case .tandemsource:
            let tandem = TandemSource(email: settings.tandemEmail, password: settings.tandemPassword, region: settings.tandemRegion)
            if !settings.tandemPumpAssignmentId.isEmpty {
                tandem.selectedPumpAssignmentIdOverride = settings.tandemPumpAssignmentId
            }
            provider = tandem
        default:
            provider = Simulator("defaulted")
        }

        self.provider.sourceIndex = self.sourceIndex

        subscribeToProvider()

        timer = DispatchTimer(timeInterval: 15, queue: DispatchQueue(label: "tools.t1d.GlucoseBar.CGMQueue"))
        timer.suspend()
        timer.eventHandler = timerEventHandler
        timer.resume()

        if let observer = notificationObserver {
            notificationCenter.removeObserver(observer)
        }
        registerForNotifications()

        self.plog("Reset glucose object", level: .default)
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
        self.provider.sourceIndex = self.sourceIndex

        switch settings.cgmProvider {
        case .nightscout:
            vs.providerURL = URL(string: settings.nsURL)
        case .dexcomshare:
            vs.providerURL = URL(string: settings.dxServer.url)
        default:
            vs.providerURL = nil
        }

        self.plog("Current provider before provider comparison: \(String(describing: self.provider))", level: .debug)
        if self.provider.type != settings.cgmProvider {
            self.plog("found provider \(self.provider.type.presentable) != \(settings.cgmProvider.presentable)", level: .debug)

            switch settings.cgmProvider {
            case .nightscout:
                self.provider = Nightscout(baseURL: settings.nsURL, token: settings.nsSecret, aidEnabled: settings.aidEnableAID)
            case .dexcomshare:
                self.provider = DexcomShare(username: settings.dxEmail, password: settings.dxPassword, server: settings.dxServer)
            case .simulator:
                self.provider = Simulator("simulate")
            case .tandemsource:
                let tandem = TandemSource(email: settings.tandemEmail, password: settings.tandemPassword, region: settings.tandemRegion)
                if !settings.tandemPumpAssignmentId.isEmpty {
                    tandem.selectedPumpAssignmentIdOverride = settings.tandemPumpAssignmentId
                }
                self.provider = tandem
            default:
                self.plog("Unknown provider. Please add in setSettings in Glucose.swift", level: .error)
            }

            self.provider.sourceIndex = self.sourceIndex

            subscribeToProvider()

        }

        Task {
            self.getGlucose()
        }
        self.plog("Current provider after provider comparison and lookup: \(String(describing: self.provider))", level: .debug)
    }

    func reload() {
        self.getGlucose()
    }

    func stop() {
        timer.suspend()
        timer.eventHandler = nil
        if let observer = notificationObserver {
            notificationCenter.removeObserver(observer)
            notificationObserver = nil
        }
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
                self.plog("GlucoseEntries became empty in main dispatch block", level: .error)
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
