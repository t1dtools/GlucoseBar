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

    /// Sentinel string used when Dexcom returns a valid 200 response but with no
    /// glucose entries (e.g. sensor warm-up, signal loss). Referenced by views to
    /// show a tailored "No data" UI rather than a generic error.
    static let noDataIssue = "Dexcom: No Data"

    // Hardcoded value found in https://github.com/gagebenne/pydexcom
    private let dexcomApplicationID = "d89443d2-327c-4a6f-89e5-496bbb0317db"
    private let httpTimeout = 30.0

    // MARK: - Issue classification

    /// Plain-language message shown when Dexcom definitively rejects sign-in.
    /// The technical code (`AccountPasswordInvalid`) is logged separately so it
    /// still reaches the debug log without being shown raw in the UI.
    private func credentialMessage() -> String {
        String(localized: "Dexcom Share rejected your sign-in. Check your Dexcom username and password in Settings. If you have tried several times, Dexcom may briefly block new sign-ins — wait a few minutes and try again.")
    }

    /// Maps an auth-endpoint failure to an issue kind. A 429 (Dexcom's
    /// "Too many requests") is a rate limit, not a credential problem, so it
    /// stays transient.
    private func authIssueKind(statusCode: Int, code: String?) -> ProviderIssueKind {
        if statusCode == 429 { return .transient }
        if statusCode == 401 || statusCode == 403 { return .credentials }
        if let code = code?.lowercased(),
           code.contains("password") || code.contains("invalid") || code.contains("unauthor") || code.contains("forbidden") {
            return .credentials
        }
        return .transient
    }

    var username: String
    var password: String
    var server: DexcomServer
    /// Effective API base — the VCR proxy override when set, otherwise the
    /// region's production URL. Keeps `server` for display/region logic.
    private let baseURL: String

    init(username: String, password: String, server: DexcomServer, serverURL: String? = nil) {
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
        self.baseURL = serverURL ?? server.url

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

    @MainActor
    override internal func fetch() async {
        plog("DexcomShare.fetch", category: "dexcomshare", level: .debug)

        // Refuse to hit the network with obviously incomplete settings; the user
        // must fix the fields in Settings first.
        guard validSettings else {
            plog("Dexcom Share settings invalid: \(settingsError)", category: "dexcomshare", level: .error)
            self.setIssue(settingsError, kind: .configuration)
            return
        }

        // Auto-reset the lockout after the cooling-off period so transient outages
        // don't require the user to manually reset settings.
        if unsuccessfulAuthAttempts > 5 {
            if let failDate = lastAuthFailureDate,
               Date().timeIntervalSince(failDate) > authLockoutDuration {
                plog("Auth lockout expired, resetting counter", category: "dexcomshare", level: .default)
                unsuccessfulAuthAttempts = 0
                lastAuthFailureDate = nil
                accountID = ""
                sessionID = ""
            } else {
                // Only credential-level (4xx) failures advance this counter, so a
                // persistent lockout is a sign-in problem, not a transient outage.
                self.setIssue(
                    String(localized: "Dexcom Share sign-in has failed several times. Check your username and password in Settings. If Dexcom is asking for a verification code, complete that flow in your Dexcom app first."),
                    kind: .credentials
                )
                return
            }
        }

        if !isAuthValid() {
            plog("calling authenticate from fetch", category: "dexcomshare", level: .debug)
            await authenticate()
            // Only proceed if authentication actually succeeded; do not recurse
            // to avoid cascading network calls when auth fails repeatedly.
            guard isAuthValid() else { return }
        }

        self.clearIssue()

        let url = "\(self.baseURL)/Publisher/ReadPublisherLatestGlucoseValues"
        let requestBody = DexcomShareListRequest(sessionId: self.sessionID, minutes: 1440, maxCount: 288)

        guard let requestURL = URL(string: url) else {
            self.setIssue(ProviderURL.Invalid.malformed.message, kind: .configuration)
            return
        }
        var request = URLRequest(url: requestURL, timeoutInterval: httpTimeout)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
        } catch {
            plog("Failed marshalling json, aborting fetch", category: "dexcomshare", level: .info)
            self.setProviderIssue(String(localized: "Unable to create request"))
            return
        }

        do {
            let (data, response) = try await URLSession.appDefault.data(for: request)
            guard let res = response as? HTTPURLResponse else {
                noteTransportFailure()
                self.setProviderIssue(String(localized: "Invalid response from Dexcom Share"))
                return
            }
            noteResponseReceived()
            if res.statusCode > 299 {
                var providerError = ""

                do {
                    let result = try JSONDecoder().decode(DexcomShareErrorResponse.self, from: data)

                    if result.Code == "SessionIdNotFound" || result.Code == "SessionNotValid" {
                        self.accountID = ""
                        self.sessionID = ""
                        await authenticate()
                        return
                    }

                    providerError = "\(result.Code): \(result.Message)"
                } catch {
                    providerError = String(localized: "Unknown Dexcom Share Issue: \(res.statusCode)")
                    self.plog("Unknown Dexcom Share Issue: \(String(describing: error))", category: "dexcomshare", level: .error)
                    self.plog("Request info: Status Code: \(res.statusCode)", category: "dexcomshare", level: .error)
                    // Shape only: never the body, which may contain readings.
                    self.plog("Request info: Response Body: \(LogRedactor.payloadShape(of: data))", category: "dexcomshare", level: .error)
                }

                self.setProviderIssue(providerError)
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
                        self.setIssue(DexcomShare.noDataIssue, kind: .noData)
                        // Do NOT call setGlucoseEntries([]) — preserve the existing
                        // cache so the chart and last-known glucose remain visible.
                    } else {
                        self.setGlucoseEntries(newEntries)
                    }
                    self.lastFetch = Date()
                } catch DecodingError.dataCorrupted(_) {
                    self.setProviderIssue(String(localized: "Unable to read data from Dexcom Share: Data corrupted."))
                } catch let DecodingError.keyNotFound(key, _) {
                    self.setProviderIssue(String(localized: "Unable to read data from Dexcom Share: Missing key ") + "\(key)")
                } catch DecodingError.valueNotFound(_, _) {
                    self.setProviderIssue(String(localized: "Unable to read data from Dexcom Share: Missing required value"))
                } catch DecodingError.typeMismatch(_, _) {
                    self.setProviderIssue(String(localized: "Unable to read data from Dexcom Share: Value type mismatch."))
                } catch {
                    self.plog("\(String(describing: error))", category: "dexcomshare", level: .error)
                }
            }
        } catch {
            noteTransportFailure()
            var err = String(localized: "Dexcom Share Error: ") + "\(String(describing: error))"
            if (error as? URLError)?.code == .timedOut {
                err = String(localized: "Request timed out")
            }
            self.setProviderIssue(err)
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
            self.plog("accountID was empty string", category: "dexcomshare", level: .debug)
            return false
        }

        if sessionID == "" {
            self.plog("sessionID was empty string", category: "dexcomshare", level: .debug)
            return false
        }

        // TODO: Can the token be validated more? Not an empty uuid v4?
        return true
    }

    // This function gets the accountID from the username and password (used for getting the sessionID)
    private func getAccountID() async {
        self.plog("DexcomShare.getAccountID", category: "dexcomshare", level: .debug)

        let url = "\(self.baseURL)/General/AuthenticatePublisherAccount"
        let requestBody = DexcomShareAccountIDRequest(accountName: self.username, password: self.password, applicationId: self.dexcomApplicationID)

        guard let requestURL = URL(string: url) else {
            self.setIssue(ProviderURL.Invalid.malformed.message, kind: .configuration)
            return
        }
        var request = URLRequest(url: requestURL, timeoutInterval: httpTimeout)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
        } catch {
            plog("Failed marshalling json, aborting getAccountId", category: "dexcomshare", level: .info)
            return
        }

        do {
            let (data, response) = try await URLSession.appDefault.data(for: request)

            guard let res = response as? HTTPURLResponse else {
                noteTransportFailure()
                self.setProviderIssue(String(localized: "Invalid response from Dexcom Share"))
                return
            }
            noteResponseReceived()
            if res.statusCode > 299 {
                // Only count 4xx responses as credential failures.
                // 5xx responses are transient server errors and must not
                // count toward the lockout threshold.
                if res.statusCode < 500 {
                    unsuccessfulAuthAttempts += 1
                    lastAuthFailureDate = Date()
                }

                do {
                    let result = try JSONDecoder().decode(DexcomShareErrorResponse.self, from: data)
                    // Log the provider's code/message, never the full raw JSON
                    // body: it is huge, noisy, and adds no signal beyond the code.
                    self.plog("Auth endpoint rejected (HTTP \(res.statusCode)): \(result.Code): \(result.Message)", category: "dexcomshare", level: .error)

                    let kind = self.authIssueKind(statusCode: res.statusCode, code: result.Code)
                    if kind == .credentials {
                        self.setIssue(self.credentialMessage(), kind: .credentials)
                    } else {
                        self.setIssue("\(result.Code): \(result.Message)", kind: kind)
                    }
                } catch DecodingError.dataCorrupted(_) {
                    self.setIssue(String(localized: "Unable to read data from Dexcom Share: Data corrupted."), kind: .transient)
                } catch let DecodingError.keyNotFound(key, _) {
                    self.setIssue(String(localized: "Unable to read data from Dexcom Share: Missing key ") + "\(key)", kind: .transient)
                } catch DecodingError.valueNotFound(_, _) {
                    self.setIssue(String(localized: "Unable to read data from Dexcom Share: Missing required value"), kind: .transient)
                } catch DecodingError.typeMismatch(_, _) {
                    self.setIssue(String(localized: "Unable to read data from Dexcom Share: Value type mismatch."), kind: .transient)
                } catch {
                    self.setIssue(String(localized: "Unknown Dexcom Share Issue"), kind: .transient)
                    self.plog("Unknown Dexcom Share Issue: \(String(describing: error))", category: "dexcomshare", level: .error)
                }

            } else {
                self.plog("successful auth to Dexcom Share", category: "dexcomshare", level: .debug)
                guard let responseString = String(data: data, encoding: .utf8) else {
                    self.setProviderIssue(String(localized: "Unable to decode account ID from Dexcom Share"))
                    return
                }
                self.accountID = responseString.replacingOccurrences(of: "\"", with: "")
            }
        } catch {
            noteTransportFailure()
            var err = String(localized: "Dexcom Share Error: ") + "\(String(describing: error))"
            if (error as? URLError)?.code == .timedOut {
                err = String(localized: "Request timed out")
            }
            self.setProviderIssue(err)
        }
    }

    // This function gets the sessionID (used for getting glucose entries)
    private func getSessionID() async {
        self.plog("DexcomShare.getSessionID", category: "dexcomshare", level: .debug)

        let url = "\(self.baseURL)/General/LoginPublisherAccountById"
        let requestBody = DexcomShareSessionIDRequest(accountId: self.accountID, password: self.password, applicationId: self.dexcomApplicationID)

        guard let requestURL = URL(string: url) else {
            self.setIssue(ProviderURL.Invalid.malformed.message, kind: .configuration)
            return
        }
        var request = URLRequest(url: requestURL, timeoutInterval: httpTimeout)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
        } catch {
            plog("Failed marshalling json, aborting getSessionID", category: "dexcomshare", level: .info)
            return
        }

        do {
            let (data, response) = try await URLSession.appDefault.data(for: request)

            guard let res = response as? HTTPURLResponse else {
                noteTransportFailure()
                self.setProviderIssue(String(localized: "Invalid response from Dexcom Share"))
                return
            }
            noteResponseReceived()
            if res.statusCode > 299 {
                // Only count 4xx responses as credential failures (not transient 5xx).
                if res.statusCode < 500 {
                    unsuccessfulAuthAttempts += 1
                    lastAuthFailureDate = Date()
                }

                do {
                    let result = try JSONDecoder().decode(DexcomShareErrorResponse.self, from: data)
                    // Log the provider's code/message, never the full raw JSON body.
                    self.plog("Auth endpoint rejected (HTTP \(res.statusCode)): \(result.Code): \(result.Message)", category: "dexcomshare", level: .error)

                    let kind = self.authIssueKind(statusCode: res.statusCode, code: result.Code)
                    if kind == .credentials {
                        self.setIssue(self.credentialMessage(), kind: .credentials)
                    } else {
                        self.setIssue("\(result.Code): \(result.Message)", kind: kind)
                    }
                } catch DecodingError.dataCorrupted(_) {
                    self.setIssue(String(localized: "Unable to read data from Dexcom: Data corrupted."), kind: .transient)
                } catch let DecodingError.keyNotFound(key, _) {
                    self.setIssue(String(localized: "Unable to read data from Dexcom Share: Missing key ") + "\(key)", kind: .transient)
                } catch DecodingError.valueNotFound(_, _) {
                    self.setIssue(String(localized: "Unable to read data from Dexcom Share: Missing required value"), kind: .transient)
                } catch DecodingError.typeMismatch(_, _) {
                    self.setIssue(String(localized: "Unable to read data from Dexcom Share: Value type mismatch."), kind: .transient)
                } catch {
                    self.setIssue(String(localized: "Unknown Dexcom Share Issue"), kind: .transient)
                    self.plog("Unknown Dexcom Share Issue: \(String(describing: error))", category: "dexcomshare", level: .error)
                }
            } else {
                self.plog("successful session to Dexcom Share", category: "dexcomshare", level: .debug)
                guard let responseString = String(data: data, encoding: .utf8) else {
                    self.setProviderIssue(String(localized: "Unable to decode session ID from Dexcom Share"))
                    return
                }
                self.sessionID = responseString.replacingOccurrences(of: "\"", with: "")
            }
        } catch {
            noteTransportFailure()
            var err = String(localized: "Dexcom Share Error: ") + "\(String(describing: error))"
            if (error as? URLError)?.code == .timedOut {
                err = String(localized: "Request timed out")
            }
            self.setProviderIssue(err)
        }

    }

    @MainActor
    private func authenticate() async {
        self.plog("DexcomShare.authenticate", category: "dexcomshare", level: .debug)

        if unsuccessfulAuthAttempts > 5 {
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        // One bounded pass: fetch the account id if it is missing, then the
        // session id. Deliberately NOT recursive — the previous implementation
        // re-entered itself on every failed account lookup, firing ~10 requests
        // in a few seconds (see debug(1).log, 2026-10-19) until Dexcom returned
        // "Too many requests".
        if self.accountID == "" {
            await getAccountID()
        }

        if self.accountID != "" && self.sessionID == "" {
            await getSessionID()
        }

        if self.accountID != "" && self.sessionID != "" {
            unsuccessfulAuthAttempts = 0
            lastAuthFailureDate = nil
            self.clearIssue()
        }
    }

    override internal func verifyCredentials() async -> Bool {
        self.plog("dexcomshare.verifyCredentials", category: "dexcomshare", level: .debug)

        // Check the fields before spending a network round-trip on them.
        guard validSettings else {
            self.setIssue(settingsError, kind: .configuration)
            return false
        }

        await self.getAccountID()
        if self.accountID != "" {
            await self.getSessionID()
            if self.sessionID != "" {
                self.clearIssue()
                return true
            }
            return false
        }

        return false
    }
}
