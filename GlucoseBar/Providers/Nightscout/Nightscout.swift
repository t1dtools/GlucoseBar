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
    private var lastAuthFailureDate: Date? = nil
    private let authLockoutDuration: TimeInterval = 30 * 60
    public var validSettings: Bool = true
    public var settingsError: String = ""

    private let manager: SocketManager
    private let socket: SocketIOClient

    /// Stand-in socket target used when the configured address is unusable.
    /// It is never connected to: every network path is gated on `validSettings`.
    private static let unreachableSocketURL = URL(string: "http://127.0.0.1:1") ?? URL(fileURLWithPath: "/")

    private let httpTimeout = 120.0

    private var lastFullFetch: Date = Date()

    var baseURL: String
    var token: String
    var aidEnabled: Bool
    var verifyOnly: Bool = false

    init(baseURL: String, token: String, aidEnabled: Bool, verifyOnly: Bool = false) {
        self.verifyOnly = verifyOnly
        self.token = token
        self.aidEnabled = aidEnabled

        // Validate before anything else: `SocketManager` needs a URL at init
        // time, and force-unwrapping one built from user input used to trap here
        // (on save, and again on every launch afterwards).
        let parsedSocketURL: URL
        switch ProviderURL.validate(baseURL) {
        case .success(let url):
            // The socket keeps the scheme the user typed — a `wss://` address is a
            // legitimate socket target. The request paths below need the http(s)
            // equivalent, and the trailing slash is dropped so they stay
            // single-slashed.
            parsedSocketURL = url
            let normalized = ProviderURL.httpEquivalent(of: url).absoluteString
            self.baseURL = normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized
        case .failure(let invalid):
            validSettings = false
            settingsError = invalid.message
            // Kept for logging/state readability only; nothing talks to it while
            // `validSettings` is false.
            self.baseURL = ProviderURL.cleaned(baseURL)
            parsedSocketURL = Nightscout.unreachableSocketURL
        }

        manager = SocketManager(
            socketURL: parsedSocketURL,
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

        // In verify-only mode (used by the settings Test Connection) skip the
        // socket connect + auto-fetch: a fresh provider would otherwise race
        // its own verifyCredentials() on shared auth state and flake the
        // verification result.
        if verifyOnly {
            self.isBaseProvider = false
            self.type = .nightscout
            return
        }

        self.isBaseProvider = false
        self.type = .nightscout

        // An unusable address is reported straight away rather than waiting for
        // a fetch that can never succeed.
        guard validSettings else {
            self.setIssue(settingsError, kind: .configuration)
            return
        }

        registerHandlers()
        if socket.status != .connected {
            connect()
        }

        Task {
            await self.fetch()
        }
        self.startTimer()
    }

    func connect() {
        socket.connect(withPayload: nil, timeoutAfter: 60.0, withHandler: nil) // TODO: With handler is called when connection fails. Should probs do something with that.
    }

    func disconnect() {
        socket.disconnect()
    }

    deinit {
        socket.disconnect()
        manager.disconnect()
    }

    private func registerHandlers() {
        socket.on(clientEvent: .connect) { _, _ in
            self.plog("Nightscout socket connected", category: "nightscout", level: .debug)
            self.socket.emit("authorize", ["client": "web", "secret": self.token])
        }

        socket.on(clientEvent: .disconnect) { _, _ in
            self.plog("Nightscout socket disconnected", category: "nightscout", level: .debug)
        }

        socket.on(clientEvent: .error) { _, _ in
            self.plog("Nightscout socket error", category: "nightscout", level: .debug)
        }

        socket.on("dataUpdate") { data, _ in
            self.plog("Nightscout socket got: dataUpdate", category: "nightscout", level: .debug)

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
                self.plog("Failed to snapshot socket payload: \(String(describing: error))", category: "nightscout", level: .error)
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
            self.plog("handleDataUpdate: unexpected format (\(data.count) items)", category: "nightscout", level: .error)
            return
        }


        if let deviceStatuses = dict["devicestatus"] as? [[String: Any]] {
            do {
                let data = try JSONSerialization.data(withJSONObject: deviceStatuses)
                let statuses = try JSONDecoder().decode([DeviceStatusResult].self, from: data)

                let sortedStatuses = statuses.filter { $0.mills ?? 0 > 0 }.sorted { $0.mills ?? 0 > $1.mills ?? 0 }

                if sortedStatuses.count > 0 {
                    let gse = await handleGSE(sortedStatuses.first!)

                    self.GlucoseSourceExtras = gse.gse
                }
            } catch {
                self.plog("Failed to decode devicestatus: \(error)", category: "nightscout", level: .error)
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
                self.plog("Fetched \(uniqueNewEntries.count) new entries", category: "nightscout", level: .debug)
                var updatedEntries = currentEntries
                updatedEntries.insert(contentsOf: newEntries, at: 0)

                if updatedEntries.count > 288 {
                    // The entry's value is a measurement, so log its identity instead.
                    self.plog("removing last entry from cache (id \(updatedEntries.last?.id ?? "?"))", category: "nightscout", level: .debug)
                    updatedEntries.removeLast()
                }
                self.plog("Latest glucose entry: id \(updatedEntries.first?.id ?? "none")", category: "nightscout", level: .debug)
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

    @MainActor
    override internal func fetch() async {
        plog("Nightscout.fetch", category: "nightscout", level: .debug)

        if self.socket.status == .connected {
            // We're on a socket connection, so the rest of this function is not needed
            lastFetch = Date()
            plog("Nightscout.fetch exiting early due to socket being connected", category: "nightscout", level: .debug)
            return
        }

        guard validSettings else {
            self.setIssue(settingsError, kind: .configuration)
            return
        }

        if unsuccessfulAuthAttempts > 5 {
            if let failDate = lastAuthFailureDate,
               Date().timeIntervalSince(failDate) > authLockoutDuration {
                plog("Auth lockout expired, resetting counter", category: "nightscout", level: .default)
                unsuccessfulAuthAttempts = 0
                lastAuthFailureDate = nil
            } else {
                self.setIssue(String(localized: "Nightscout rejected your sign-in several times. Check your Nightscout URL and access token in Settings."), kind: .credentials)
                return
            }
        }

        if token.count > 0 && !isAuthValid() {
            await authenticate()
        }

        if !isAuthValid() {
            // Do not clobber a more specific classification (e.g. a credential
            // rejection) set by authenticate() just above.
            if issueKind == .none {
                self.setIssue(String(localized: "Unable to fetch from Nightscout. Please ensure the Nightscout Server URL is correct and begins with http:// or https://, and that your access token is valid."), kind: .configuration)
            }
            return
        }

        self.clearIssue()

        var url = "\(baseURL)/api/v3/entries?sort%24desc=date&fields=sgv%2Ctrend%2Cdirection%2Cdate%2Cidentifier"

        var limit = 288
        if self.GlucoseEntries.count > 1 {
            limit = 1
            plog("Time since last fetch: \(self.lastFetch.timeIntervalSinceNow * -1) seconds", category: "nightscout", level: .info)
            if self.lastFetch.timeIntervalSinceNow < -400 {
                plog("re-setting limit to full fetch because last fetch was more than 400 seconds ago", category: "nightscout", level: .info)
                limit = 288
            }

            // This is a workaround for avoiding gaps in the graph. A better solution should be found so we don't tax the NS server unnecessarily every 15 minutes.
            if self.lastFullFetch.timeIntervalSinceNow < -900 {
                plog("full fetch because it's been over 15 minutes since we got all data", category: "nightscout", level: .info)
                limit = 288
                self.lastFullFetch = Date()
            }

        }
        url = url + "&limit=\(limit)"


        lastFetch = Date()

        let lim = limit // Needs to be a constant to not be "Reference to captured var 'limit' in concurrently-executing code"
        // `url` is built from the validated base URL plus a fixed query, so a
        // failure here is a programming error rather than user input — still,
        // report it instead of trapping.
        guard let entriesURL = URL(string: url) else {
            self.setIssue(ProviderURL.Invalid.malformed.message, kind: .configuration)
            return
        }
        do {
            var request = URLRequest(url: entriesURL, timeoutInterval: httpTimeout)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            if self.auth?.token.count ?? 0 > 0 {
                request.addValue("Bearer \(auth!.token)", forHTTPHeaderField: "Authorization")
            }

            request.httpMethod = "GET"

            let (data, response) = try await URLSession.appDefault.data(for: request)

            let res = response as? HTTPURLResponse
            if res == nil {
                noteTransportFailure()
                self.plog("Unable to cast response to HTTPURLResponse", category: "nightscout", level: .error)
                Task { @MainActor in
                    self.setIssue(String(localized: "Unable to get glucose data: Empty response from server."), kind: .transient)
                }
                return
            }
            noteResponseReceived()

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
                            self.plog("Fetched \(uniqueNewEntries.count) new entries", category: "nightscout", level: .debug)
                            var updatedEntries = currentEntries
                            updatedEntries.insert(contentsOf: newEntries, at: 0)

                            if updatedEntries.count > 288 {
                                // The entry's value is a measurement, so log its identity instead.
                                self.plog("removing last entry from cache (id \(updatedEntries.last?.id ?? "?"))", category: "nightscout", level: .debug)
                                updatedEntries.removeLast()
                            }
                            self.plog("Latest glucose entry: id \(updatedEntries.first?.id ?? "none")", category: "nightscout", level: .debug)
                            self.setGlucoseEntries(updatedEntries)
                        }
                    }

                    if aidEnabled && RemoteGlucoseSource != .null {
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }

                            let gs = GlucoseSource(baseURL: self.baseURL, token: self.auth?.token ?? "invalid", aidEnabled: self.aidEnabled, sourceIndex: self.sourceIndex)
                            let gse = await gs.getGlucoseSourceExtras()

                            self.GlucoseSourceExtras = gse
                        }
                    }
                } catch DecodingError.dataCorrupted(_) {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.setIssue(String(localized: "Unable to read data from Nightscout: Data corrupted."), kind: .transient)
                    }
                } catch let DecodingError.keyNotFound(key, _) {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.setIssue(String(localized: "Unable to read data from Nightscout: Missing key ") + "\(key)", kind: .transient)
                    }
                } catch DecodingError.valueNotFound(_, _) {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.setIssue(String(localized: "Unable to read data from Nightscout: Missing required value"), kind: .transient)
                    }
                } catch DecodingError.typeMismatch(_, _) {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.setIssue(String(localized: "Unable to read data from Nightscout: Value type mismatch. Is this a new version of Nightscout?"), kind: .transient)
                    }
                } catch {
                    self.plog("Error parsing NS response: \(String(describing: error))", category: "nightscout", level: .error)
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.setIssue(String(localized: "Unable to parse glucose data from nightscout: Error unknown."), kind: .transient)
                    }
                }
            } else if res!.statusCode == 401 || res!.statusCode == 403 {
                self.auth = nil
                self.setIssue(String(localized: "Nightscout rejected your sign-in. Check your Nightscout URL and access token in Settings."), kind: .credentials)

                return
            } else {
                do {
                    let result = try JSONDecoder().decode(NightscoutEntriesErrorResponse.self, from: data)
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.setIssue(String(localized: "Error from Nightscout: ") + result.message, kind: .transient)
                    }
                } catch {
                    self.plog("Error parsing NS error response: \(String(describing: error))", category: "nightscout", level: .error)
                }
            }
        } catch {
            noteTransportFailure()
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                var err = String(describing: error)

                if (error as? URLError)?.code == .timedOut {
                    err = "Request timed out"
                }

                self.setIssue(err, kind: .transient)
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
            self.plog("auth was nil", category: "nightscout", level: .debug)
            return false
        }

        if auth!.token != "" {
            let expiryTime = Date(timeIntervalSince1970: auth!.expiry)

            self.plog("nightscout token expiry: \(expiryTime.formatted())", category: "nightscout", level: .debug)
            return expiryTime.timeIntervalSinceNow > 0
        }

        return false
    }

    @MainActor
    private func authenticate() async {

        if isAuthenticating {
            self.plog("Already authenticating actively. Returning.", category: "nightscout", level: .info)
            return
        }

        isAuthenticating = true
        // Every exit path below — rejection, transport error, decode error — has
        // to clear this. It previously leaked on the rejection paths, which left
        // the provider stuck as "already authenticating" until relaunch and made
        // it impossible to recover by fixing the token in Settings.
        defer { isAuthenticating = false }

        guard validSettings else {
            self.setIssue(settingsError, kind: .configuration)
            return
        }

        self.clearIssue()

        self.plog("Nightscout.authenticate", category: "nightscout", level: .debug)

        // The token is a path segment here, so encode it: a token containing a
        // space or a slash used to make the URL unparseable (a hard crash when
        // the result was force-unwrapped, and a silent failure once guarded).
        var allowedTokenCharacters = CharacterSet.alphanumerics
        allowedTokenCharacters.insert(charactersIn: "-._~")
        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: allowedTokenCharacters) ?? token
        guard let requestURL = URL(string: "\(baseURL)/api/v2/authorization/request/\(encodedToken)") else {
            self.setIssue(ProviderURL.Invalid.malformed.message, kind: .configuration)
            return
        }
        var request = URLRequest(url: requestURL, timeoutInterval: httpTimeout)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.appDefault.data(for: request)

            guard let res = response as? HTTPURLResponse else {
                noteTransportFailure()
                self.setIssue(String(localized: "Invalid response from Nightscout"), kind: .transient)
                return
            }
            noteResponseReceived()
            if res.statusCode > 299 {
                unsuccessfulAuthAttempts += 1
                lastAuthFailureDate = Date()
                // Body shape only: the payload carries the token.
                self.plog("Auth endpoint rejected (HTTP \(res.statusCode)). \(LogRedactor.payloadShape(of: data))", category: "nightscout", level: .debug)

                // A 401/403 is a definitive credential rejection; anything else
                // (5xx, 429, unknown) is transient and may recover on its own.
                if res.statusCode == 401 || res.statusCode == 403 {
                    self.setIssue(String(localized: "Nightscout rejected your sign-in. Check your Nightscout URL and access token in Settings."), kind: .credentials)
                } else {
                    var providerError = "Unknown Nightscout Issue"
                    if let result = try? JSONDecoder().decode(NightscoutAuthErrorResponse.self, from: data) {
                        providerError = "\(result.message): \(result.description)"
                    }
                    self.setIssue(providerError, kind: .transient)
                }
                return
            } else {
                // Body shape only: the success payload carries the access token.
                self.plog("status code under 300: \(res.statusCode). \(LogRedactor.payloadShape(of: data))", category: "nightscout", level: .debug)
                do {
                    let result = try JSONDecoder().decode(NightscoutAuthResponse.self, from: data)

                    self.auth = ProviderAuth(token: result.token, expiry: result.exp)

                    self.plog("Authentication is successful.", category: "nightscout", level: .debug)
                    isAuthenticated = true
                    unsuccessfulAuthAttempts = 0

                    // Check glucose source device to see if we support extra features
                    let gs = GlucoseSource(baseURL: self.baseURL, token: result.token, aidEnabled: aidEnabled, sourceIndex: self.sourceIndex)
                    let (source, err) = try await gs.checkDeviceStatusForGSE()
                    if err != nil {
                        self.GlucoseSourceExtras.error = err!
                    }
                    if source != GlucoseSourceDevice.null {
                        RemoteGlucoseSource = source
                    }

                    return
                } catch {
                    self.plog("Unable to parse response from Nightscout: \(String(describing: error))", category: "nightscout", level: .error)
                    self.setIssue(String(localized: "Unable to parse response from Nightscout: ") + String(describing: error), kind: .transient)
                    return
                }
            }
        } catch {
            noteTransportFailure()
            var err = "Nightscout Error: \(String(describing: error))"
            if (error as? URLError)?.code == .timedOut {
                err = "Request timed out"
            }
            self.unsuccessfulAuthAttempts += 1
            lastAuthFailureDate = Date()
            self.setIssue(err, kind: .transient)
        }
    }

    override internal func verifyCredentials() async -> Bool {
        self.plog("nightscout.verifyCredentials", category: "nightscout", level: .debug)

        // Check the fields before spending a network round-trip on them.
        guard validSettings else {
            self.setIssue(settingsError, kind: .configuration)
            return false
        }

        // If an auth is already in flight (e.g. the live fetch cycle),
        // authenticate() early-returns and isAuthenticated stays stale,
        // so Verify would spuriously fail. Wait briefly for the in-flight
        // auth to settle, then auth if idle.
        if isAuthenticating {
            for _ in 0..<20 { // up to ~4s
                if !isAuthenticating { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        if !isAuthenticating {
            await self.authenticate()
        }

        return self.isAuthenticated
    }
}
