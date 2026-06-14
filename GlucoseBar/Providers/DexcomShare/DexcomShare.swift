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
            return String(localized: "USA", comment: "The USA Dexcom Share region")
        case .ous:
            return String(localized: "Outside USA", comment: "The non-USA Dexcom Share region")
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

class DexcomShare: Provider, @unchecked Sendable {

    private var accountID: String = ""
    private var sessionID: String = ""
    public var validSettings: Bool = true
    public var settingsError: String = ""
    /// Count of consecutive credential-level auth failures (4xx responses).
    /// Only incremented for definitive credential errors, not transient server
    /// errors (5xx), so a brief Dexcom outage cannot permanently lock the provider.
    private var unsuccessfulAuthAttempts = 0
    /// Timestamp of the last credential failure. Allows the lockout to be
    /// automatically cleared after a cooling-off period even without a settings reset.
    private var lastAuthFailureDate: Date? = nil
    /// How long the lock-out lasts before being automatically retried (30 minutes).
    private let authLockoutDuration: TimeInterval = 30 * 60

    @MainActor
    func setProviderIssue(_ value: String?) {
        self.providerIssue = value
    }

    /// Sentinel string used when Dexcom returns a valid 200 response but with no
    /// glucose entries (e.g. sensor warm-up, signal loss). Referenced by views to
    /// show a tailored "No data" UI rather than a generic error.
    static let noDataIssue = "Dexcom: No Data"

    // Hardcoded value found in https://github.com/gagebenne/pydexcom
    private let dexcomApplicationID = "d89443d2-327c-4a6f-89e5-496bbb0317db"
    private let httpTimeout = 30.0

    var username: String
    var password: String
    var server: DexcomServer

    init(username: String, password: String, server: DexcomServer) {
        if username.isEmpty {
            validSettings = false
            settingsError = String(localized: "Username can not be empty")
        }

        if password.isEmpty {
            validSettings = false
            settingsError = String(localized: "Password can not be empty")
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
        logger.dlog("DexcomShare.fetch", category: "dexcomshare", level: .debug)

        // Auto-reset the lockout after the cooling-off period so transient outages
        // don't require the user to manually reset settings.
        if unsuccessfulAuthAttempts > 5 {
            if let failDate = lastAuthFailureDate,
               Date().timeIntervalSince(failDate) > authLockoutDuration {
                logger.dlog("Auth lockout expired, resetting counter", category: "dexcomshare", level: .default)
                unsuccessfulAuthAttempts = 0
                lastAuthFailureDate = nil
                accountID = ""
                sessionID = ""
            } else {
                self.providerIssue = "Unable to connect to Dexcom Share after 5 attempts. Please check your credentials and if Dexcom is asking to send a code to your email or phone, please go through that flow on your device."
                return
            }
        }

        if !isAuthValid() {
            logger.dlog("calling authenticate from fetch", category: "dexcomshare", level: .debug)
            await authenticate()
            // Only proceed if authentication actually succeeded; do not recurse
            // to avoid cascading network calls when auth fails repeatedly.
            guard isAuthValid() else { return }
        }

        await self.setProviderIssue(nil)

        let url = "\(self.server.url)/Publisher/ReadPublisherLatestGlucoseValues"
        let requestBody = DexcomShareListRequest(sessionId: self.sessionID, minutes: 1440, maxCount: 288)

        var request = URLRequest(url: URL(string: url)!, timeoutInterval: httpTimeout)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
        } catch {
            logger.dlog("Failed marshalling json, aborting fetch", category: "dexcomshare", level: .info)
            await self.setProviderIssue(String(localized: "Unable to create request"))
            return
        }

        do {
            let (data, response) = try await URLSession.appDefault.data(for: request)
            guard let res = response as? HTTPURLResponse else {
                await self.setProviderIssue(String(localized: "Invalid response from Dexcom Share"))
                return
            }
            if res.statusCode > 299 {
                var providerError = ""

                do {
                    let result = try JSONDecoder().decode(DexcomShareErrorResponse.self, from: data)

                    // If session expired, clear auth data and re-authenticate inline
                    // (one level only — no recursive fetch to avoid cascading calls).
                    if result.Code == "SessionIdNotFound" || result.Code == "SessionNotValid" {
                        self.accountID = ""
                        self.sessionID = ""
                        await authenticate()
                        guard isAuthValid() else { return }
                        // Re-attempt the data fetch now that we have a fresh session.
                        await self.fetch()
                        return
                    }

                    providerError = "\(result.Code): \(result.Message)"
                } catch {
                    providerError = String(localized: "Unknown Dexcom Share Issue: \(res.statusCode)")
                    self.logger.dlog("Unknown Dexcom Share Issue: \(String(describing: error))", category: "dexcomshare", level: .error)
                    self.logger.dlog("Request info: Status Code: \(res.statusCode)", category: "dexcomshare", level: .error)
                    if let str = String(data: data, encoding: .utf8) {
                        self.logger.dlog("Request info: Response Body: \(str)", category: "dexcomshare", level: .error)
                    } else {
                        self.logger.dlog("Request info: No response body.", category: "dexcomshare", level: .error)
                    }
                }

                await self.setProviderIssue(providerError)
            } else {
                do {
                    let result = try JSONDecoder().decode([DXEntriesResult].self, from: data)
                    var previous: GlucoseEntry? = nil
                    let currentEntries = self.getSafeGlucoseEntries()
                    if currentEntries.count > 0 {
                        previous = currentEntries[0]
                    }

                    let newEntries = self.dexcomEntriesToGlucoseEntries(input: result, previous: previous)
                    if newEntries.isEmpty {
                        await self.setProviderIssue(DexcomShare.noDataIssue)
                        // Do NOT call setGlucoseEntries([]) — preserve the existing
                        // cache so the chart and last-known glucose remain visible.
                    } else {
                        self.setGlucoseEntries(newEntries)
                    }
                    self.lastFetch = Date()
                } catch DecodingError.dataCorrupted(_) {
                    await self.setProviderIssue(String(localized: "Unable to read data from Dexcom Share: Data corrupted."))
                } catch let DecodingError.keyNotFound(key, _) {
                    await self.setProviderIssue(String(localized: "Unable to read data from Dexcom Share: Missing key ") + "\(key)")
                } catch DecodingError.valueNotFound(_, _) {
                    await self.setProviderIssue(String(localized: "Unable to read data from Dexcom Share: Missing required value"))
                } catch DecodingError.typeMismatch(_, _) {
                    await self.setProviderIssue(String(localized: "Unable to read data from Dexcom Share: Value type mismatch."))
                } catch {
                    self.logger.dlog("\(String(describing: error))", category: "dexcomshare", level: .error)
                }
            }
        } catch {
            var err = String(localized: "Dexcom Share Error: ") + "\(String(describing: error))"
            if (error as? URLError)?.code == .timedOut {
                err = String(localized: "Request timed out")
            }
            await self.setProviderIssue(err)
        }
    }

    private func dexcomEntriesToGlucoseEntries(input: [DXEntriesResult], previous: GlucoseEntry?) -> [GlucoseEntry] {
        // Dexcom returns entries newest-first.
        // To compute changeRate for entry[i] we need entry[i+1] (the older neighbour),
        // which we can look up by index once we have the raw value array.
        var ge: [GlucoseEntry] = []
        for (i, dxEntry) in input.enumerated() {
            var wt = dxEntry.WT.replacingOccurrences(of: "Date(", with: "")
            wt = wt.replacingOccurrences(of: ")", with: "")
            let date = Date(timeIntervalSince1970: (Double(wt)! / 1000))

            var trend = GlucoseEntry.GlucoseTrend(direction: "invalid")
            if dxEntry.Trend != "" {
                trend = GlucoseEntry.GlucoseTrend(direction: dxEntry.Trend)
            }

            // positive = rising, negative = falling; 0 for the oldest entry (no prior reference).
            let olderValue = i + 1 < input.count ? Double(input[i + 1].Value) : nil
            let changeRate = olderValue.map { Double(dxEntry.Value) - $0 } ?? 0.0

            let entry = GlucoseEntry(glucose: Double(dxEntry.Value), date: date, glucoseType: .sensor, trend: trend, changeRate: changeRate)
            ge.append(entry)
        }

        return ge
    }

    override public func isAuthValid() -> Bool {
        if accountID == "" {
            self.logger.dlog("accountID was empty string", category: "dexcomshare", level: .debug)
            return false
        }

        if sessionID == "" {
            self.logger.dlog("sessionID was empty string", category: "dexcomshare", level: .debug)
            return false
        }

        // TODO: Can the token be validated more? Not an empty uuid v4?
        return true
    }

    // This function gets the accountID from the username and password (used for getting the sessionID)
    private func getAccountID() async {
        self.logger.dlog("DexcomShare.getAccountID", category: "dexcomshare", level: .debug)
        await self.setProviderIssue(nil)

        let url = "\(self.server.url)/General/AuthenticatePublisherAccount"
        let requestBody = DexcomShareAccountIDRequest(accountName: self.username, password: self.password, applicationId: self.dexcomApplicationID)

        var request = URLRequest(url: URL(string: url)!, timeoutInterval: httpTimeout)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
        } catch {
            logger.dlog("Failed marshalling json, aborting getAccountId", category: "dexcomshare", level: .info)
            return
        }

        do {
            let (data, response) = try await URLSession.appDefault.data(for: request)

            guard let res = response as? HTTPURLResponse else {
                await self.setProviderIssue(String(localized: "Invalid response from Dexcom Share"))
                return
            }
            if res.statusCode > 299 {
                // Only count 4xx responses as credential failures.
                // 5xx responses are transient server errors and must not
                // count toward the lockout threshold.
                if res.statusCode < 500 {
                    unsuccessfulAuthAttempts += 1
                    lastAuthFailureDate = Date()
                }
                var providerError: String? = nil
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                self.logger.dlog("\(responseString)", category: "dexcomshare", level: .error)

                do {
                    let result = try JSONDecoder().decode(DexcomShareErrorResponse.self, from: data)
                    providerError = "\(result.Code): \(result.Message)"

                    if result.Code == "AccountPasswordInvalid" {
                        providerError! += String(localized: " (If you've gotten this error a few times in a row, this could also mean that the Dexcom servers have given you a short timeout before you can login again)")
                    }
                } catch DecodingError.dataCorrupted(_) {
                    providerError = String(localized: "Unable to read data from Dexcom Share: Data corrupted.")
                } catch let DecodingError.keyNotFound(key, _) {
                    providerError = String(localized: "Unable to read data from Dexcom Share: Missing key ") + "\(key)"
                } catch DecodingError.valueNotFound(_, _) {
                    providerError = String(localized: "Unable to read data from Dexcom Share: Missing required value")
                } catch DecodingError.typeMismatch(_, _) {
                    providerError = String(localized: "Unable to read data from Dexcom Share: Value type mismatch.")
                } catch {
                    providerError = "Unknown Dexcom Share Issue"
                    self.logger.dlog("Unknown Dexcom Share Issue: \(String(describing: error))", category: "dexcomshare", level: .error)
                }

                await self.setProviderIssue(providerError)

            } else {
                self.logger.dlog("successful auth to Dexcom Share", category: "dexcomshare", level: .debug)
                guard let responseString = String(data: data, encoding: .utf8) else {
                    await self.setProviderIssue(String(localized: "Unable to decode account ID from Dexcom Share"))
                    return
                }
                self.accountID = responseString.replacingOccurrences(of: "\"", with: "")
            }
        } catch {
            var err = String(localized: "Dexcom Share Error: ") + "\(String(describing: error))"
            if (error as? URLError)?.code == .timedOut {
                err = String(localized: "Request timed out")
            }
            await self.setProviderIssue(err)
        }
    }

    // This function gets the sessionID (used for getting glucose entries)
    private func getSessionID() async {
        self.logger.dlog("DexcomShare.getSessionID", category: "dexcomshare", level: .debug)
        await self.setProviderIssue(nil)

        let url = "\(self.server.url)/General/LoginPublisherAccountById"
        let requestBody = DexcomShareSessionIDRequest(accountId: self.accountID, password: self.password, applicationId: self.dexcomApplicationID)

        var request = URLRequest(url: URL(string: url)!, timeoutInterval: httpTimeout)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
        } catch {
            logger.dlog("Failed marshalling json, aborting getSessionID", category: "dexcomshare", level: .info)
            return
        }

        do {
            let (data, response) = try await URLSession.appDefault.data(for: request)

            guard let res = response as? HTTPURLResponse else {
                await self.setProviderIssue(String(localized: "Invalid response from Dexcom Share"))
                return
            }
            if res.statusCode > 299 {
                // Only count 4xx responses as credential failures (not transient 5xx).
                if res.statusCode < 500 {
                    unsuccessfulAuthAttempts += 1
                    lastAuthFailureDate = Date()
                }
                var providerError = ""
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                self.logger.dlog("\(responseString)", category: "dexcomshare", level: .error)

                do {
                    let result = try JSONDecoder().decode(DexcomShareErrorResponse.self, from: data)
                    providerError = "\(result.Code): \(result.Message)"
                } catch DecodingError.dataCorrupted(_) {
                    providerError = String(localized: "Unable to read data from Dexcom: Data corrupted.")
                } catch let DecodingError.keyNotFound(key, _) {
                    providerError = String(localized: "Unable to read data from Dexcom Share: Missing key ") + "\(key)"
                } catch DecodingError.valueNotFound(_, _) {
                    providerError = String(localized: "Unable to read data from Dexcom Share: Missing required value")
                } catch DecodingError.typeMismatch(_, _) {
                    providerError = String(localized: "Unable to read data from Dexcom Share: Value type mismatch.")
                } catch {
                    providerError = String(localized: "Unknown Dexcom Share Issue")
                    self.logger.dlog("Unknown Dexcom Share Issue: \(String(describing: error))", category: "dexcomshare", level: .error)
                }

                await self.setProviderIssue(providerError)
            } else {
                self.logger.dlog("successful session to Dexcom Share", category: "dexcomshare", level: .debug)
                guard let responseString = String(data: data, encoding: .utf8) else {
                    await self.setProviderIssue(String(localized: "Unable to decode session ID from Dexcom Share"))
                    return
                }
                self.sessionID = responseString.replacingOccurrences(of: "\"", with: "")
            }
        } catch {
            var err = String(localized: "Dexcom Share Error: ") + "\(String(describing: error))"
            if (error as? URLError)?.code == .timedOut {
                err = String(localized: "Request timed out")
            }
            await self.setProviderIssue(err)
        }

    }

    private func authenticate() async {
        self.logger.dlog("DexcomShare.authenticate", category: "dexcomshare", level: .debug)

        if unsuccessfulAuthAttempts > 5 {
            return
        }

        isAuthenticating = true

        await self.setProviderIssue(nil)

        // Do we need a full refresh?
        if self.accountID == "" {
            await getAccountID()
            await self.authenticate()

            isAuthenticating = false
            return
        }

        if self.sessionID == "" {
            await getSessionID()
        }

        if self.accountID != "" && self.sessionID != "" {
            unsuccessfulAuthAttempts = 0
        }

        isAuthenticating = false
    }

    override internal func verifyCredentials() async -> Bool {
        self.logger.dlog("dexcomshare.verifyCredentials", category: "dexcomshare", level: .debug)

        await self.getAccountID()
        if self.accountID != "" {
            await self.getSessionID()
            return self.sessionID != ""
        }

        return false
    }
}
