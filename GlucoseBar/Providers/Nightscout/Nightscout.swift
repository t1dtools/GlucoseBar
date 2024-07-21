//
//  Nightscout.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-10-28.
//

import Foundation

class Nightscout: Provider {

    private var isAuthenticated = false
    private var auth: NightscoutAuthResponse?
    public var validSettings: Bool = true
    public var settingsError: String = ""

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
            logger.debug("calling authenticate from fetch")
            await authenticate()
            await self.fetch()
            return
        }

        self.providerIssue = nil

        var url = "\(baseURL)/api/v3/entries?sort%24desc=date&fields=sgv%2Ctrend%2Cdirection%2Cdate%2Cidentifier"

        var limit = 288
        if self.GlucoseEntries.count > 1 {
            limit = 1
            logger.info("Time since last fetch: \(self.lastFetch.timeIntervalSinceNow * -1) seconds")
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
            var request = URLRequest(url: URL(string: url)!, timeoutInterval: 30)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            if self.token.count > 0 {
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
                    try DispatchQueue.global().sync {
                        let result = try JSONDecoder().decode(NightscoutEntriesResponse.self, from: data)

                        var previous: GlucoseEntry? = nil
                        if self.GlucoseEntries.count > 0 {
                            previous = self.GlucoseEntries[0]
                        }

                        let newEntries = self.nsEntriesToGlucoseEntries(input: result.result, previous: previous)

                        if lim > 1 {
                            self.GlucoseEntries = newEntries
                        } else {
                            let uniqueNewEntries = newEntries.filter { newEntry in
                                !self.GlucoseEntries.contains(where: {
                                    $0.id == newEntry.id
                                }
                                )}

                            if uniqueNewEntries.count > 0 {
                                self.logger.debug("Fetched \(uniqueNewEntries.count) new entries")
                                self.GlucoseEntries.insert(contentsOf: newEntries, at: 0)

                                if self.GlucoseEntries.countExcedes(288) {
                                    self.logger.debug("removing entry from glucoseentries: \(self.GlucoseEntries.last!.glucose)")
                                    self.GlucoseEntries.removeLast()
                                }
                                self.logger.debug("Latest glucose entry: \(String(describing: self.GlucoseEntries.first?.glucose))")
                            }
                        }
                    }
                } catch {
                    self.logger.error("Error parsing NS response: \(String(describing: error))")
                    DispatchQueue.main.async {
                        self.providerIssue = "Unable to get glucose data: \(String(describing: error))"
                    }
                }
            } else if res!.statusCode == 401 {
                self.auth = nil
                await self.fetch()
                return
            } else {
                do {
                    let result = try JSONDecoder().decode(NightscoutEntriesErrorResponse.self, from: data)
                    DispatchQueue.main.async {
                        self.providerIssue = "Error from Nightscout: \(result.message)"
                    }
                } catch {
                    self.logger.error("Error parsing NS error response: \(String(describing: error))")
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.providerIssue = "Nightscout Error: \(String(describing: error))"
            }
        }
    }

    private func nsEntriesToGlucoseEntries(input: [NSEntriesResult], previous: GlucoseEntry?) -> [GlucoseEntry] {
        var ge: [GlucoseEntry] = []
        var previousGe: GlucoseEntry?
        input.forEach { nsEntry in
            let date = Date(timeIntervalSince1970: nsEntry.date / 1000)

            if nsEntry.sgv != nil {
                var trend = GlucoseEntry.GlucoseTrend(direction: "invalid")
                if nsEntry.direction != nil {
                    trend = GlucoseEntry.GlucoseTrend(direction: nsEntry.direction!)
                }

                var changeRate = 0.0
                // Externally provided previous entry (for cases where we only fetch one new entry)
                if previous != nil {
                    changeRate = previous!.glucose - nsEntry.sgv!
                }

                // Internally tracked previous entry (for cases where we have more than one new entry fetched)
                if previousGe != nil {
                    changeRate = previousGe!.glucose - nsEntry.sgv!
                }

                let entry = GlucoseEntry(glucose: nsEntry.sgv!, date: date, trend: trend, changeRate: changeRate, id: nsEntry.identifier)
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
            let expiryTime = Date(timeIntervalSince1970: auth!.exp)

            self.logger.debug("nightscout token expiry: \(expiryTime.formatted())")
            return expiryTime.timeIntervalSinceNow > 0
        }

        return false
    }

    private func authenticate() async {

        if !baseURL.hasPrefix("https://") && !baseURL.hasPrefix("http://") {
            DispatchQueue.main.async {
                self.providerIssue = "Invalid Nightscout URL. Must start with either http:// or https://"
            }
            return
        }

        DispatchQueue.main.async {
            self.providerIssue = nil
        }

        self.logger.debug("Nightscout.authenticate")
        var request = URLRequest(url: URL(string: "\(baseURL)/api/v2/authorization/request/\(token)")!,timeoutInterval: Double.infinity)
        request.httpMethod = "GET"

        self.logger.info("Token URL: \(self.baseURL)/api/v2/authorization/request/\(self.token)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            let res = response as! HTTPURLResponse
            if res.statusCode > 299 {
                var providerError = ""
                do {
                    let result = try JSONDecoder().decode(NightscoutAuthErrorResponse.self, from: data)
                    providerError = "\(result.message): \(result.description)"
                } catch {
                    providerError = "Unknown Nightscout Issue"
                }

                self.providerIssue = providerError
                return
            } else {
                do {
                    let result = try JSONDecoder().decode(NightscoutAuthResponse.self, from: data)
                    self.auth = result
                    return
                } catch {
                    self.providerIssue = "Unable to parse response from Nightscout: \(String(describing: error))"
                    return
                }
            }
        } catch {
            self.providerIssue = "Nightscout Error: \(String(describing: error))"
        }
    }

    override internal func verifyCredentials() async -> Bool {
        self.logger.debug("nightscout.verifyCredentials")
        await self.authenticate()
        return true
    }
}
