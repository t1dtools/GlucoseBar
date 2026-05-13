//
//  Nightscout.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-10-28.
//

import Foundation
import SocketIO

struct SocketSGV: Codable {
    let id: String
    let direction: String?
    let mgdl: Double?
    let date: TimeInterval
}

extension SocketSGV {
    init?(dict: [String: Any]) {
        guard
            let id = dict["_id"] as? String,
            let mgdl = dict["mgdl"] as? Double
        else {
            return nil
        }

        // mills is sometimes String, sometimes Number
        let millsValue: TimeInterval?
        if let m = dict["mills"] as? Double {
            millsValue = m
        } else if let m = dict["mills"] as? String {
            millsValue = Double(m)
        } else {
            millsValue = nil
        }

        guard let mills = millsValue else { return nil }

        self.id = id
        self.mgdl = mgdl
        self.date = mills
        self.direction = dict["direction"] as? String
    }
}

class Nightscout: Provider, @unchecked Sendable {

    private var isAuthenticated = false
    private var unsuccessfulAuthAttempts = 0
    public var validSettings: Bool = true
    public var settingsError: String = ""

    private let manager: SocketManager
    private let socket: SocketIOClient

    private let httpTimeout = 120.0

    private var lastFullFetch: Date = Date()

    var baseURL: String
    var token: String
    var aidEnabled: Bool

    init(baseURL: String, token: String, aidEnabled: Bool) {

        // Do some basic validation
        if baseURL.isEmpty {
            validSettings = false
            settingsError = "Host can not be empty"
        }

        if !baseURL.hasPrefix("https://") && !baseURL.hasPrefix("http://") && !baseURL.hasPrefix("wss://") && !baseURL.hasPrefix("ws://") {
            validSettings = false
            settingsError = "Host must start with http://, https://, ws:// or wss://"
        }

        self.baseURL = baseURL
        self.token = token
        self.aidEnabled = aidEnabled

        if baseURL.hasSuffix("/") {
            self.baseURL = String(self.baseURL.dropLast())
        }

        manager = SocketManager(
            socketURL: URL(string: self.baseURL)!,
            config: [
                .log(false),
                .compress,
                .reconnects(true),
                .reconnectAttempts(-1), // infinite
                .reconnectWait(5),
                .forcePolling(true),
            ]
        )

        socket = manager.defaultSocket

        super.init()

        registerHandlers()
        if socket.status != .connected {
            connect()
        }

        self.isBaseProvider = false
        Task {
            await self.fetch()
        }
        self.startTimer()

        self.type = .nightscout
    }

    func connect() {
        socket.connect(withPayload: nil, timeoutAfter: 60.0, withHandler: nil) // TODO: With handler is called when connection fails. Should probs do something with that.
    }

    func disconnect() {
        socket.disconnect()
    }

    private func registerHandlers() {
        socket.on(clientEvent: .connect) { _, _ in
            self.logger.debug("Nightscout socket connected")
            self.socket.emit("authorize", ["client": "web", "secret": self.token])
        }

        socket.on(clientEvent: .disconnect) { _, _ in
            self.logger.debug("Nightscout socket disconnected")
        }

        socket.on(clientEvent: .error) { _, _ in
            self.logger.debug("Nightscout socket error")
        }

        socket.on("dataUpdate") { data, _ in
            self.logger.debug("Nightscout socket got: dataUpdate")

            // Create a deep, Sendable-safe snapshot of the payload by round-tripping through JSON
            let snapshot: [Any]
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
                let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
                if let arr = jsonObject as? [Any] {
                    snapshot = arr
                } else if let dict = jsonObject as? [String: Any] {
                    snapshot = [dict]
                } else {
                    snapshot = []
                }
            } catch {
                self.logger.error("Failed to snapshot socket payload: \(String(describing: error))")
                snapshot = []
            }

            Task { @MainActor in
                await self.handleDataUpdate(snapshot)
            }
        }

        // For debugging the socket
//        socket.onAny { event in
//            if event.event != "dataUpdate" {
//                print("Event:", event.event, "Items:", event.items ?? [])
//            }
//        }
    }

    // Socket update handler
    @MainActor
    func handleDataUpdate(_ data: [Any]) async {
        guard let dict = data.first as? [String: Any] else {
            print("Unexpected format:", data)
            return
        }


        if let deviceStatuses = dict["devicestatus"] as? [[String: Any]] {
            do {
                let data = try JSONSerialization.data(withJSONObject: deviceStatuses)
                let statuses = try JSONDecoder().decode([DeviceStatusResult].self, from: data)

                let sortedStatuses = statuses.filter { $0.mills ?? 0 > 0 }.sorted { $0.mills ?? 0 > $1.mills ?? 0 }

                if sortedStatuses.count > 0 {
                    let gse = await handleGSE(sortedStatuses.first!)

                    await MainActor.run {
                        self.GlucoseSourceExtras = gse.gse
                    }
                }
            } catch {
                self.logger.error("Failed to decode devicestatus: \(error)")
            }
        }

        if let sgvDicts = dict["sgvs"] as? [[String: Any]] {
            var previous: GlucoseEntry? = nil
            let currentEntries = self.getSafeGlucoseEntries()
            if currentEntries.count > 0 {
                previous = currentEntries[0]
            }

            let sgvs = sgvDicts.compactMap(SocketSGV.init).sorted { $0.date > $1.date }

            // 24 hours is enough for our needs
            let cutOff = Date().addingTimeInterval(-24 * 60 * 60)
            let recentSGVs = sgvs.filter { sgv in
                let d = Date(timeIntervalSince1970: TimeInterval(sgv.date) / 1000)
                return d >= cutOff
            }

            let newEntries = nsSocketSGVsToGlucoseEntries(input: recentSGVs, previous: previous)
            let uniqueNewEntries = newEntries.filter { newEntry in
                !currentEntries.contains(where: {
                    $0.id == newEntry.id
                })
            }

            if uniqueNewEntries.count > 0 {
                self.logger.debug("Fetched \(uniqueNewEntries.count, privacy: .public) new entries")
                var updatedEntries = currentEntries
                updatedEntries.insert(contentsOf: newEntries, at: 0)

                if updatedEntries.count > 288 {
                    self.logger.debug("removing entry from glucoseentries: \(updatedEntries.last!.glucose, privacy: .private)")
                    updatedEntries.removeLast()
                }
                self.logger.debug("Latest glucose entry: \(String(describing: updatedEntries.first?.glucose), privacy: .private)")
                self.setGlucoseEntries(updatedEntries)
            }
        }
    }

    private func nsSocketSGVsToGlucoseEntries(input: [SocketSGV], previous: GlucoseEntry?) -> [GlucoseEntry] {
        var ge: [GlucoseEntry] = []
        var previousGe: GlucoseEntry?

        input.forEach { nsSGV in
            let date = Date(timeIntervalSince1970: nsSGV.date / 1000)

            if let sgv = nsSGV.mgdl {
                var trend = GlucoseEntry.GlucoseTrend(direction: "invalid")
                if let direction = nsSGV.direction {
                    trend = GlucoseEntry.GlucoseTrend(direction: direction)
                }

                var changeRate = 0.0
                if let prev = previous {
                    changeRate = prev.glucose - sgv
                }

                if let prevGe = previousGe {
                    changeRate = prevGe.glucose - sgv
                }

                let entry = GlucoseEntry(glucose: sgv, date: date, glucoseType: .sensor, trend: trend, changeRate: changeRate, id: nsSGV.id)
                previousGe = entry
                ge.append(entry)
            }
        }

        return ge
    }

    private func handleSGV(_ payload: [String: Any]) {
        guard
            let mgdl = payload["mgdl"] as? Int,
            let timestamp = payload["datetime"] as? TimeInterval
        else {
            return
        }

        let date = Date(timeIntervalSince1970: timestamp / 1000)

        self.logger.debug("SGV: \(mgdl) at \(date)")
    }


    struct NightscoutEntriesErrorResponse: Codable {
        let status: Int
        let message: String
    }

    struct NightscoutEntriesResponse: Codable {
        let status: Int
        let result: [NSEntriesResult]
    }

    struct NSEntriesResult: Codable {
        let identifier: String
        let date: Double
        let sgv, trend: Double?
        let direction: String?
        let trendRate: Double?
    }

    override internal func fetch() async {
        logger.debug("Nightscout.fetch")

        if self.socket.status == .connected {
            // We're on a socket connection, so the rest of this function is not needed
            lastFetch = Date()
            logger.debug("Nightscout.fetch exiting early due to socket being connected")
            return
        }

        if !baseURL.hasPrefix("http://") && !baseURL.hasPrefix("https://") {
            self.providerIssue = "Invalid Nightscout URL. It must start with http:// or https://"
            return
        }

        if unsuccessfulAuthAttempts > 5 {
            self.providerIssue = "Unable to connect to Nightscout after 5 attempts. Please check your credentials."
            return
        }

        if token.count > 0 && !isAuthValid() {
            await authenticate()
        }

        if !isAuthValid() {
            self.providerIssue = "Unable to fetch due to unknown issue. Please ensure the Nightscout Server URL is correct and begins with http:// or https://"
            return
        }

        self.providerIssue = nil

        var url = "\(baseURL)/api/v3/entries?sort%24desc=date&fields=sgv%2Ctrend%2Cdirection%2Cdate%2Cidentifier"

        var limit = 288
        if self.GlucoseEntries.count > 1 {
            limit = 1
            logger.info("Time since last fetch: \(self.lastFetch.timeIntervalSinceNow * -1, privacy: .public) seconds")
            if self.lastFetch.timeIntervalSinceNow < -400 {
                logger.info("re-setting limit to full fetch because last fetch was more than 400 seconds ago")
                limit = 288
            }

            // This is a workaround for avoiding gaps in the graph. A better solution should be found so we don't tax the NS server unnecessarily every 15 minutes.
            if self.lastFullFetch.timeIntervalSinceNow < -900 {
                logger.info("full fetch because it's been over 15 minutes since we got all data")
                limit = 288
                self.lastFullFetch = Date()
            }

        }
        url = url + "&limit=\(limit)"


        lastFetch = Date()

        let lim = limit // Needs to be a constant to not be "Reference to captured var 'limit' in concurrently-executing code"
        do {
            var request = URLRequest(url: URL(string: url)!, timeoutInterval: httpTimeout)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            if self.auth?.token.count ?? 0 > 0 {
                request.addValue("Bearer \(auth!.token)", forHTTPHeaderField: "Authorization")
            }

            request.httpMethod = "GET"

            let (data, response) = try await URLSession.shared.data(for: request)

            let res = response as? HTTPURLResponse
            if res == nil {
                self.logger.error("Unable to cast response to HTTPURLResponse")
                Task {
                    self.providerIssue = "Unable to get glucose data: Empty response from server."
                }
                return
            }

            if res!.statusCode == 200 {
                do {
                    let result = try JSONDecoder().decode(NightscoutEntriesResponse.self, from: data)

                    var previous: GlucoseEntry? = nil
                    let currentEntries = self.getSafeGlucoseEntries()
                    if currentEntries.count > 0 {
                        previous = currentEntries[0]
                    }

                    let newEntries = self.nsEntriesToGlucoseEntries(input: result.result, previous: previous)

                    if lim > 1 {
                        self.setGlucoseEntries(newEntries)
                    } else {
                        let uniqueNewEntries = newEntries.filter { newEntry in
                            !currentEntries.contains(where: {
                                $0.id == newEntry.id
                            }
                            )}

                        if uniqueNewEntries.count > 0 {
                            self.logger.debug("Fetched \(uniqueNewEntries.count, privacy: .public) new entries")
                            var updatedEntries = currentEntries
                            updatedEntries.insert(contentsOf: newEntries, at: 0)

                            if updatedEntries.count > 288 {
                                self.logger.debug("removing entry from glucoseentries: \(updatedEntries.last!.glucose, privacy: .private)")
                                updatedEntries.removeLast()
                            }
                            self.logger.debug("Latest glucose entry: \(String(describing: updatedEntries.first?.glucose), privacy: .private)")
                            self.setGlucoseEntries(updatedEntries)
                        }
                    }

                    if aidEnabled && RemoteGlucoseSource != .null {
                        Task { [weak self] in
                            guard let self = self else { return }

                            let gs = GlucoseSource(baseURL: self.baseURL, token: self.auth?.token ?? "invalid", aidEnabled: self.aidEnabled)
                            let gse = await gs.getGlucoseSourceExtras()

                            self.GlucoseSourceExtras = gse
                        }
                    }
                } catch DecodingError.dataCorrupted(_) {
                    Task { [weak self] in
                        guard let self = self else { return }
                        self.providerIssue = "Unable to read data from Nightscout: Data corrupted."
                    }
                } catch let DecodingError.keyNotFound(key, _) {
                    Task { [weak self] in
                        guard let self = self else { return }
                        self.providerIssue = "Unable to read data from Nightscout: Missing key \(key)"
                    }
                } catch DecodingError.valueNotFound(_, _) {
                    Task { [weak self] in
                        guard let self = self else { return }
                        self.providerIssue = "Unable to read data from Nightscout: Missing required value"
                    }
                } catch DecodingError.typeMismatch(_, _) {
                    Task { [weak self] in
                        guard let self = self else { return }
                        self.providerIssue = "Unable to read data from Nightscout: Value type mismatch. Is this a new version of Nightscout?"
                    }
                } catch {
                    self.logger.error("Error parsing NS response: \(String(describing: error), privacy: .public)")
                    Task { [weak self] in
                        guard let self = self else { return }
                        self.providerIssue = "Unable to parse glucose data from nightscout: Error unknown."
                    }
                }
            } else if res!.statusCode == 401 {
                self.auth = nil

                return
            } else {
                do {
                    let result = try JSONDecoder().decode(NightscoutEntriesErrorResponse.self, from: data)
                    Task { [weak self] in
                        guard let self = self else { return }
                        self.providerIssue = "Error from Nightscout: \(result.message)"
                    }
                } catch {
                    self.logger.error("Error parsing NS error response: \(String(describing: error), privacy: .public)")
                }
            }
        } catch {
            Task { [weak self] in
                guard let self = self else { return }

                var err = String(describing: error)

                if (error as? URLError)?.code == .timedOut {
                    err = "Request timed out"
                }

                self.providerIssue = err
            }
        }
    }

    private func nsEntriesToGlucoseEntries(input: [NSEntriesResult], previous: GlucoseEntry?) -> [GlucoseEntry] {
        var ge: [GlucoseEntry] = []
        var previousGe: GlucoseEntry?
        input.forEach { nsEntry in
            let date = Date(timeIntervalSince1970: nsEntry.date / 1000)

            if let sgv = nsEntry.sgv {
                var trend = GlucoseEntry.GlucoseTrend(direction: "invalid")
                if let direction = nsEntry.direction {
                    trend = GlucoseEntry.GlucoseTrend(direction: direction)
                }

                var changeRate = 0.0
                // Externally provided previous entry (for cases where we only fetch one new entry)
                if let prev = previous {
                    changeRate = prev.glucose - sgv
                }

                // Internally tracked previous entry (for cases where we have more than one new entry fetched)
                if let prevGe = previousGe {
                    changeRate = prevGe.glucose - sgv
                }

                var glucoseType = GlucoseEntry.GlucoseType.sensor
                if nsEntry.direction == nil {
                    glucoseType = GlucoseEntry.GlucoseType.meter
                }

                let entry = GlucoseEntry(glucose: sgv, date: date, glucoseType: glucoseType, trend: trend, changeRate: changeRate, id: nsEntry.identifier)
                previousGe = entry
                ge.append(entry)
            }
        }

        return ge
    }

    private struct NightscoutAuthResponse: Decodable {
        var token: String
        var sub: String
        var iat: Double
        var exp: Double
    }

    private struct NightscoutAuthErrorResponse: Decodable {
        let status: Int64
        let message: String
        let description: String
    }

    override public func isAuthValid() -> Bool {
        if auth == nil {
            self.logger.debug("auth was nil")
            return false
        }

        if auth!.token != "" {
            let expiryTime = Date(timeIntervalSince1970: auth!.expiry)

            self.logger.debug("nightscout token expiry: \(expiryTime.formatted())")
            return expiryTime.timeIntervalSinceNow > 0
        }

        return false
    }

    private func authenticate() async {

        if isAuthenticating {
            self.logger.info("Already authenticating actively. Returning.")
            return
        }

        isAuthenticating = true

        if !baseURL.hasPrefix("https://") && !baseURL.hasPrefix("http://") {
            self.providerIssue = "Invalid Nightscout URL. Must start with either http:// or https://"
            return
        }

        Task {
            self.providerIssue = nil
            self.isAuthenticating = true
        }

        self.logger.debug("Nightscout.authenticate")
        var request = URLRequest(url: URL(string: "\(baseURL)/api/v2/authorization/request/\(token)")!, timeoutInterval: httpTimeout)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let res = response as? HTTPURLResponse else {
                Task { [weak self] in
                    guard let self = self else { return }
                    self.providerIssue = "Invalid response from Nightscout"
                }
                return
            }
            if res.statusCode > 299 {
                unsuccessfulAuthAttempts += 1
                self.logger.debug("status code over 299: \(res.statusCode). Body: \(data)")
                Task { [weak self] in
                    guard let self = self else { return }

                    var providerError = ""
                    do {
                        let result = try JSONDecoder().decode(NightscoutAuthErrorResponse.self, from: data)
                        providerError = "\(result.message): \(result.description)"
                    } catch {
                        providerError = "Unknown Nightscout Issue"
                    }
                    self.providerIssue = providerError
                }
                return
            } else {
                self.logger.debug("status code under 300: \(res.statusCode). Body: \(data)")
                do {
                    let result = try JSONDecoder().decode(NightscoutAuthResponse.self, from: data)

                    Task {
                        self.auth = ProviderAuth(token: result.token, expiry: result.exp)
                    }

                    self.logger.debug("Authentication is successful.")
                    isAuthenticating = false
                    isAuthenticated = true
                    unsuccessfulAuthAttempts = 0

                    // Check glucose source device to see if we support extra features
                    let gs = GlucoseSource(baseURL: self.baseURL, token: result.token, aidEnabled: aidEnabled)
                    let (source, err) = try await gs.checkDeviceStatusForGSE()
                    if err != nil {
                        self.GlucoseSourceExtras.error = err!
                    }
                    if source != GlucoseSourceDevice.null {
                        RemoteGlucoseSource = source
                    }

                    return
                } catch {
                    self.providerIssue = "Unable to parse response from Nightscout: \(String(describing: error))"
                    isAuthenticating = false
                    return
                }
            }
        } catch {
            var err = "Nightscout Error: \(String(describing: error))"
            if (error as? URLError)?.code == .timedOut {
                err = "Request timed out"
            }
            self.unsuccessfulAuthAttempts += 1
            self.providerIssue = err
        }

        isAuthenticating = false
    }

    override internal func verifyCredentials() async -> Bool {
        self.logger.debug("nightscout.verifyCredentials")
        await self.authenticate()

        return self.isAuthenticated
    }
}
