//
//  DexcomShare.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-11-12.
//

import Foundation

public enum DexcomServer: String, CaseIterable, Identifiable {
    case us
    case ous
    public var id: String { self.rawValue }
    public var presentable: String {
        switch self {
        case .us:
            return "USA"
        case .ous:
            return "Outside USA"
        }
    }
    public var url: String {
        switch self {
        case .us:
            return "https://share2.dexcom.com/ShareWebServices/Services"
        case .ous:
            return "https://shareous1.dexcom.com/ShareWebServices/Services"
        }
    }
}

class DexcomShare: Provider {

    private var isAuthenticated = false
    private var accountID: String = ""
    private var sessionID: String = ""
    public var validSettings: Bool = true
    public var settingsError: String = ""

    // Hardcoded value found in https://github.com/gagebenne/pydexcom
    private let dexcomApplicationID = "d89443d2-327c-4a6f-89e5-496bbb0317db"
    private let httpTimeout = 30.0

    var username: String
    var password: String
    var server: DexcomServer

    init(username: String, password: String, server: DexcomServer) {
        if username.isEmpty {
            validSettings = false
            settingsError = "Username can not be empty"
        }

        if password.isEmpty {
            validSettings = false
            settingsError = "Password can not be empty"
        }

        self.username = username
        self.password = password
        self.server = server

        super.init()
        self.type = .dexcomshare
    }

    struct DXEntriesResult: Codable {
        let WT: String
        let ST: String
        let DT: String
        let Value: Int64
        let Trend: String
    }

    struct DexcomShareListRequest: Encodable {
        let sessionId: String
        let minutes: Int64
        let maxCount: Int64
    }

    struct DexcomShareErrorResponse: Decodable {
        let Code: String
        let Message: String
    }

    private struct DexcomShareAccountIDRequest: Encodable {
        let accountName: String
        let password: String
        let applicationId: String
    }

    private struct DexcomShareSessionIDRequest: Encodable {
        let accountId: String
        let password: String
        let applicationId: String
    }

    override internal func fetch() async {
        logger.debug("DexcomShare.fetch")
        if !isAuthValid() {
            logger.debug("calling authenticate from fetch")
            await authenticate()
            await self.fetch()
            return
        }

        self.providerIssue = nil

        let url = "\(self.server.url)/Publisher/ReadPublisherLatestGlucoseValues"
        let requestBody = DexcomShareListRequest(sessionId: self.sessionID, minutes: 1440, maxCount: 288)

        var request = URLRequest(url: URL(string: url)!, timeoutInterval: httpTimeout)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "POST"
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
        } catch {
            logger.info("Failed marshalling json, aborting fetch")
            DispatchQueue.main.async {
                self.providerIssue = "Unable to create request"
            }
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let res = response as! HTTPURLResponse
            if res.statusCode > 299 {
                var providerError = ""

                do {
                    let result = try JSONDecoder().decode(DexcomShareErrorResponse.self, from: data)

                    // If auth error, clear auth data and re-fetch
                    if result.Code == "SessionIdNotFound" || result.Code == "SessionNotValid" {
                        self.accountID = ""
                        self.sessionID = ""
                        await self.fetch()
                        return
                    }

                    providerError = "\(result.Code): \(result.Message)"
                } catch {
                    providerError = "Unknown Dexcom Share Issue: \(res.statusCode)"
                    self.logger.error("Unknown Dexcom Share Issue: \(String(describing: error))")

                    self.logger.error("Request info: Status Code: \(res.statusCode)")
                    if let str = String(data: data, encoding: .utf8) {
                        self.logger.error("Request info: Response Body: \(str)")
                    } else {
                        self.logger.error("Request info: No response body.")
                    }
                }

                self.providerIssue = providerError
            } else {
                do {
                    let result = try JSONDecoder().decode([DXEntriesResult].self, from: data)
                    var previous: GlucoseEntry? = nil
                    if self.GlucoseEntries.count > 0 {
                        previous = self.GlucoseEntries[0]
                    }

                    self.GlucoseEntries = self.dexcomEntriesToGlucoseEntries(input: result, previous: previous)
                    self.lastFetch = Date()

                } catch { self.logger.error("\(String(describing: error))") }
            }
        } catch {
            self.providerIssue = "Dexcom Share Error: \(String(describing: error))"
        }
    }

    private func dexcomEntriesToGlucoseEntries(input: [DXEntriesResult], previous: GlucoseEntry?) -> [GlucoseEntry] {
        var ge: [GlucoseEntry] = []
        var lastValue: Int64 = 0
        input.forEach { dxEntry in
            var wt = dxEntry.WT.replacingOccurrences(of: "Date(", with: "")
            wt = wt.replacingOccurrences(of: ")", with: "")
            // Adding 5 minutes on the timestamp because Dexcom servers for some reason return all entries with time skewed 5 minutes.
            // Note that the readings are correct in time, the time attached to them is however 5 minutes too early
            let date = Date(timeIntervalSince1970: (Double(wt)! / 1000) + 300)

            var trend = GlucoseEntry.GlucoseTrend(direction: "invalid")
            if dxEntry.Trend != "" {
                trend = GlucoseEntry.GlucoseTrend(direction: dxEntry.Trend)
            }

            var changeRate = 0.0
            if lastValue > 0 {
                changeRate = Double(lastValue - dxEntry.Value)
            }

            let entry = GlucoseEntry(glucose: Double(dxEntry.Value), date: date, trend: trend, changeRate: changeRate)
            ge.append(entry)

            lastValue = dxEntry.Value
        }

        return ge
    }

    override public func isAuthValid() -> Bool {
        if accountID == "" {
            self.logger.debug("accountID was empty string")
            return false
        }

        if sessionID == "" {
            self.logger.debug("sessionID was empty string")
            return false
        }

        // TODO: Can the token be validated more? Not an empty uuid v4?
        return true
    }

    // This function gets the accountID from the username and password (used for getting the sessionID)
    private func getAccountID() async {
        self.logger.debug("DexcomShare.getAccountID")

//        DispatchQueue.main.async {
        self.providerIssue = nil
//        }

        let url = "\(self.server.url)/General/AuthenticatePublisherAccount"
        let requestBody = DexcomShareAccountIDRequest(accountName: self.username, password: self.password, applicationId: self.dexcomApplicationID)

        var request = URLRequest(url: URL(string: url)!, timeoutInterval: httpTimeout)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "POST"
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
        } catch {
            logger.info("Failed marshalling json, aborting getAccountId")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            let res = response as! HTTPURLResponse
            if res.statusCode > 299 {
                var providerError: String? = nil
                self.logger.error("\(String(data: data, encoding: .utf8)!)")

                do {
                    let result = try JSONDecoder().decode(DexcomShareErrorResponse.self, from: data)
                    providerError = "\(result.Code): \(result.Message)"

                    if result.Code == "AccountPasswordInvalid" {
                        providerError! += " (If you've gotten this error a few times in a row, this could also mean that the Dexcom servers have given you a short timeout before you can login again)"
                    }
                } catch {
                    providerError = "Unknown Dexcom Share Issue"
                    self.logger.error("Unknown Dexcom Share Issue: \(String(describing: error))")
                }

                self.providerIssue = providerError

            } else {
                self.logger.debug("successful auth to Dexcom Share")
                self.accountID = String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\"", with: "")
            }
        } catch {
            self.providerIssue = "Dexcom Share Error: \(String(describing: error))"
        }
    }

    // This function gets the sessionID (used for getting glucose entries)
    private func getSessionID() async {
        self.logger.debug("DexcomShare.getSessionID")
        self.providerIssue = nil

        let url = "\(self.server.url)/General/LoginPublisherAccountById"
        let requestBody = DexcomShareSessionIDRequest(accountId: self.accountID, password: self.password, applicationId: self.dexcomApplicationID)

        var request = URLRequest(url: URL(string: url)!, timeoutInterval: httpTimeout)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "POST"
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
        } catch {
            logger.info("Failed marshalling json, aborting getSessionID")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            let res = response as! HTTPURLResponse
            if res.statusCode > 299 {
                var providerError = ""
                self.logger.error("\(String(data: data, encoding: .utf8)!)")

                do {
                    let result = try JSONDecoder().decode(DexcomShareErrorResponse.self, from: data)
                    providerError = "\(result.Code): \(result.Message)"
                } catch {
                    providerError = "Unknown Dexcom Share Issue"
                    self.logger.error("Unknown Dexcom Share Issue: \(String(describing: error))")
                }

                self.providerIssue = providerError
            } else {
                self.logger.debug("successful session to Dexcom Share")
                self.sessionID = String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\"", with: "")
            }
        } catch {
            self.providerIssue = "Dexcom Share Error: \(String(describing: error))"
        }

    }

    private func authenticate() async {
        self.logger.debug("DexcomShare.authenticate")

        DispatchQueue.main.async {
            self.providerIssue = nil
        }

        // Do we need a full refresh?
        if self.accountID == "" {
            await getAccountID()
            await self.authenticate()

            return
        }

        if self.sessionID == "" {
            await getSessionID()
        }
    }

    override internal func verifyCredentials() async -> Bool {
        self.logger.debug("dexcomshare.verifyCredentials")
        
        await self.getAccountID()
        if self.accountID != "" {
            await self.getSessionID()
            return self.sessionID != ""
        }

        return false
    }
}

