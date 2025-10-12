//
//  Nightscout.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-10-28.
//

import Foundation

class Nightscout: Provider, @unchecked Sendable {

    private var isAuthenticated = false
    public var validSettings: Bool = true
    public var settingsError: String = ""

    private let httpTimeout = 120.0

    private var lastFullFetch: Date = Date()

    var baseURL: String
    var token: String

    init(baseURL: String, token: String) {

        // Do some basic validation
        if baseURL.isEmpty {
            validSettings = false
            settingsError = "Host can not be empty"
        }

        if !baseURL.hasPrefix("https://") && !baseURL.hasPrefix("http://") {
            validSettings = false
            settingsError = "Host must start with http:// or https://"
        }

        self.baseURL = baseURL
        self.token = token

        if baseURL.hasSuffix("/") {
            self.baseURL = String(self.baseURL.dropLast())
        }

        super.init()
        self.isBaseProvider = false
        self.type = .nightscout
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
        if token.count > 0 && !isAuthValid() {
            await authenticate()
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
                DispatchQueue.main.async {
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

                    if RemoteGlucoseSource != .null {
                        let gs = GlucoseSource(baseURL: self.baseURL, token: self.auth?.token ?? "invalid")
                        let gse = await gs.getGlucoseSourceExtras()
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.GlucoseSourceExtras = gse
                        }
                    }
                } catch DecodingError.dataCorrupted(_) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.providerIssue = "Unable to read data from Nightscout: Data corrupted."
                    }
                } catch let DecodingError.keyNotFound(key, _) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.providerIssue = "Unable to read data from Nightscout: Missing key \(key)"
                    }
                } catch DecodingError.valueNotFound(_, _) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.providerIssue = "Unable to read data from Nightscout: Missing required value"
                    }
                } catch DecodingError.typeMismatch(_, _) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.providerIssue = "Unable to read data from Nightscout: Value type mismatch. Is this a new version of Nightscout?"
                    }
                } catch {
                    self.logger.error("Error parsing NS response: \(String(describing: error), privacy: .public)")
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.providerIssue = "Unable to parse glucose data from nightscout: Error unknown."
                    }
                }
            } else if res!.statusCode == 401 {
                self.auth = nil
                await self.fetch()
                return
            } else {
                do {
                    let result = try JSONDecoder().decode(NightscoutEntriesErrorResponse.self, from: data)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.providerIssue = "Error from Nightscout: \(result.message)"
                    }
                } catch {
                    self.logger.error("Error parsing NS error response: \(String(describing: error), privacy: .public)")
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
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

        if !baseURL.hasPrefix("https://") && !baseURL.hasPrefix("http://") {
            self.providerIssue = "Invalid Nightscout URL. Must start with either http:// or https://"
            return
        }

        DispatchQueue.main.async {
            self.providerIssue = nil
            self.isAuthenticating = true
        }

        self.logger.debug("Nightscout.authenticate")
        var request = URLRequest(url: URL(string: "\(baseURL)/api/v2/authorization/request/\(token)")!, timeoutInterval: httpTimeout)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let res = response as? HTTPURLResponse else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.providerIssue = "Invalid response from Nightscout"
                }
                return
            }
            if res.statusCode > 299 {
                self.logger.debug("status code over 299: \(res.statusCode). Body: \(data)")
                DispatchQueue.main.async { [weak self] in
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
                do {
                    let result = try JSONDecoder().decode(NightscoutAuthResponse.self, from: data)

                    DispatchQueue.main.async {
                        self.auth = ProviderAuth(token: result.token, expiry: result.exp)
                    }

                    isAuthenticating = false
                    self.logger.debug("Authentication is successful.")
                    isAuthenticated = true

                    // Check glucose source device to see if we support extra features
                    let gs = GlucoseSource(baseURL: self.baseURL, token: result.token)
                    let source = await gs.checkDeviceStatusForGSE()
                    if source != GlucoseSourceDevice.null {
                        RemoteGlucoseSource = source
                    }

                    return
                } catch {
                    self.providerIssue = "Unable to parse response from Nightscout: \(String(describing: error))"
                    return
                }
            }
        } catch {
            var err = "Nightscout Error: \(String(describing: error))"
            if (error as? URLError)?.code == .timedOut {
                err = "Request timed out"
            }
            self.providerIssue = err
        }
    }

    override internal func verifyCredentials() async -> Bool {
        self.logger.debug("nightscout.verifyCredentials")
        await self.authenticate()

        return self.isAuthenticated
    }
}
