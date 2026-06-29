//
//  TandemSource.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-26.
//

import Foundation
import OSLog

@MainActor
class TandemSource: Provider {

    private let email: String
    private let password: String

    private let loginHelper = TandemLoginHelper()
    private let baseURL = URL(string: "https://tdcservices.tandemdiabetes.com")!

    private var loginSession: TandemLoginSession?
    private var userId: String?
    private var userGuid: String?
    private var unsuccessfulAuthAttempts: Int = 0
    private let maxAuthAttempts: Int = 5

    private let httpTimeout: Double = 120.0

    init(email: String, password: String) {
        self.email = email
        self.password = password
        super.init()
        self.type = CGMProvider.tandemsource
        self.isBaseProvider = false
    }

    // MARK: - Auth

    nonisolated private func hasValidAuth() -> Bool {
        // loginSession is @MainActor; use _auth proxy
        return false
    }

    @MainActor
    private func hasValidAuthMain() -> Bool {
        guard let session = loginSession else { return false }
        return !session.isExpired
    }

    @MainActor
    private func ensureAuth() async -> Bool {
        if !hasValidAuthMain() {
            return await authenticate()
        }
        return true
    }

    @MainActor
    private func authenticate() async -> Bool {
        if isAuthenticating { return false }
        if unsuccessfulAuthAttempts > maxAuthAttempts {
            providerIssue = "Unable to connect to Tandem Source after \(maxAuthAttempts) attempts. Please check your credentials."
            return false
        }

        isAuthenticating = true
        providerIssue = nil

        do {
            let session = try await loginHelper.login(email: email, password: password)
            loginSession = session
            userId = nil // will be set from user_profile
            userGuid = session.userGuid
            auth = ProviderAuth(token: session.accessToken, expiry: session.accessTokenExpiresAt.timeIntervalSince1970)
            unsuccessfulAuthAttempts = 0
            isAuthenticating = false
            GlucoseSourceExtras.aid = .controliq
            return true
        } catch {
            plog("TandemSource.auth failed: \(error.localizedDescription)", category: "tandem", level: .error)
            unsuccessfulAuthAttempts += 1
            if unsuccessfulAuthAttempts > maxAuthAttempts {
                providerIssue = "Unable to connect to Tandem Source after \(maxAuthAttempts) attempts. Please check your credentials."
            } else {
                providerIssue = "Tandem Source: \(error.localizedDescription)"
            }
            isAuthenticating = false
            return false
        }
    }

    override func verifyCredentials() async -> Bool {
        return await authenticate()
    }

    // MARK: - Fetch Cycle

    @MainActor
    override internal func fetch() async {
        plog("TandemSource.fetch", category: "tandem", level: .debug)

        guard await ensureAuth() else { return }

        do {
            try await fetchTherapyEvents()
        } catch {
            plog("TandemSource.fetch error: \(error.localizedDescription)", category: "tandem", level: .error)
            providerIssue = "Tandem fetch error: \(error.localizedDescription)"
        }

        do {
            try await fetchAIDData()
        } catch {
            plog("TandemSource.fetchAIDData error: \(error.localizedDescription)", category: "tandem", level: .error)
        }

        lastFetch = Date()
    }

    // MARK: - CGM Fetch

    private func fetchTherapyEvents() async throws {
        guard let token = loginSession?.accessToken else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"

        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-86400)

        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)

        guard let userId = try? await fetchUserId(token: token) else {
            plog("Unable to fetch userId", category: "tandem", level: .error)
            return
        }

        let url = baseURL.appendingPathComponent("tconnect/therapyevents/api/TherapyEvents/\(startStr)/\(endStr)/false")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "userId", value: userId)]

        guard let requestURL = components?.url else { return }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://tconnect.tandemdiabetes.com/", forHTTPHeaderField: "Origin")
        request.setValue("https://tconnect.tandemdiabetes.com/", forHTTPHeaderField: "Referer")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = httpTimeout

        let (data, response) = try await URLSession.appDefault.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                loginSession = nil
            }
            return
        }

        let therapyResponse = try JSONDecoder().decode(TandemTherapyEventsResponse.self, from: data)
        guard let events = therapyResponse.event else { return }

        let entries = eventsToGlucoseEntries(events)
        if !entries.isEmpty {
            setGlucoseEntries(entries)
        }
    }

    private func fetchUserId(token: String) async throws -> String? {
        if let id = userId { return id }

        let url = baseURL.appendingPathComponent("cloud/usersettings/api/UserProfile")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        guard let requestURL = components?.url else { return nil }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = httpTimeout

        let (data, response) = try await URLSession.appDefault.data(for: request)

        guard let _ = response as? HTTPURLResponse else { return nil }

        let profile = try JSONDecoder().decode(TandemUserProfile.self, from: data)
        userId = profile.userID
        return profile.userID
    }

    // MARK: - AID Data Fetch

    private func fetchAIDData() async throws {
        guard loginSession != nil else { return }

        var extras = GlucoseSourceExtraProperties(aid: .controliq)

        if let iob = try? await fetchIOB() {
            extras.iob = iob
        }

        if let thresholds = try? await fetchThresholds() {
            extras.glucoseTarget = Double(thresholds.targetBGLow ?? 110)
        }

        if let pumpInfo = try? await fetchPumpFeatures() {
            extras.reason = pumpInfo
        }

        GlucoseSourceExtras = extras
    }

    private func fetchIOB() async throws -> Double? {
        guard let guid = userGuid,
              let token = loginSession?.accessToken else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        let today = formatter.string(from: Date())

        let ws2URL = URL(string: "https://tconnectws2.tandemdiabetes.com/therapytimeline2csv/\(guid)/\(today)/\(today)?format=csv")!

        var request = URLRequest(url: ws2URL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.appDefault.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let csv = String(data: data, encoding: .utf8) else { return nil }

            let iob = parseIOBFromCSV(csv)
            return iob
        } catch {
            plog("IOB fetch error: \(error.localizedDescription)", category: "tandem", level: .debug)
            return nil
        }
    }

    private func fetchThresholds() async throws -> TandemTherapyThresholds? {
        guard let token = loginSession?.accessToken else { return nil }
        let uid: String
        if let existing = userId {
            uid = existing
        } else if let fetched = try? await fetchUserId(token: token) {
            uid = fetched
        } else {
            return nil
        }

        let url = baseURL.appendingPathComponent("cloud/usersettings/api/therapythresholds")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "userId", value: uid)]

        guard let requestURL = components?.url else { return nil }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = httpTimeout

        let (data, _) = try await URLSession.appDefault.data(for: request)
        return try JSONDecoder().decode(TandemTherapyThresholds.self, from: data)
    }

    private func fetchPumpFeatures() async throws -> String? {
        guard let token = loginSession?.accessToken else { return nil }
        let uid: String
        if let existing = userId {
            uid = existing
        } else if let fetched = try? await fetchUserId(token: token) {
            uid = fetched
        } else {
            return nil
        }

        let url = baseURL.appendingPathComponent("tconnect/controliq/api/pumpfeatures/users/\(uid)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://tconnect.tandemdiabetes.com/", forHTTPHeaderField: "Origin")
        request.setValue("https://tconnect.tandemdiabetes.com/", forHTTPHeaderField: "Referer")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = httpTimeout

        let (data, _) = try await URLSession.appDefault.data(for: request)

        let features = try JSONDecoder().decode([TandemPumpFeatures].self, from: data)

        if let first = features.first,
           let ciq = first.features?.controlIQ,
           ciq.feature == 1 {
            return "Control-IQ active"
        }

        if let first = features.first {
            if let firstName = first.serialNumber {
                return "Pump SN: \(firstName)"
            }
        }

        return nil
    }

    // MARK: - Data Parsing

    private func eventsToGlucoseEntries(_ events: [TandemTherapyEvent]) -> [GlucoseEntry] {
        return events.compactMap { event in
            guard event.type == "CGM", let egv = event.egv, egv > 0 else { return nil }

            let date: Date = {
                if let dt = event.eventDateTime {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return formatter.date(from: dt) ?? Date()
                }
                return Date()
            }()

            return GlucoseEntry(glucose: Double(egv), date: date, changeRate: 0.0)
        }.sorted(by: { $0.date > $1.date })
    }

    private func parseIOBFromCSV(_ csv: String) -> Double? {
        let lines = csv.components(separatedBy: .newlines)

        var inIOB = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.starts(with: "IOB") {
                inIOB = true
                continue
            }

            if inIOB && trimmed.contains(",") && !trimmed.isEmpty {
                let columns = trimmed.components(separatedBy: ",")
                if columns.count >= 2,
                   let iobVal = Double(columns[1].replacingOccurrences(of: "\"", with: "")) {
                    return iobVal
                }
                break
            }

            if inIOB && trimmed.isEmpty {
                break
            }
        }

        return nil
    }

    // MARK: - Helpers

    override func plog(_ message: String, category: String, level: OSLogType = .default) {
        Logger(subsystem: "tools.t1d.GlucoseBar", category: "tandem")
            .dlog(message, category: category, level: level)
    }
}
