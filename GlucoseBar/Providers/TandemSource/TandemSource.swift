//
//  TandemSource.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-26.
//

import Foundation
import OSLog

@MainActor
class TandemSource: Provider, @unchecked Sendable {

    private let email: String
    private let password: String
    private let region: TandemRegion

    private let loginHelper: TandemLoginHelper
    private let networkSession: URLSession

    private var loginSession: TandemLoginSession?
    private var pumperId: String?
    private var pumpAssignmentId: String?
    private var hasControlIQ: Bool = false
    private var lowThreshold: Int = 110
    private var highThreshold: Int = 180
    private var unsuccessfulAuthAttempts: Int = 0
    private let maxAuthAttempts: Int = 5
    private var nextFetchAllowedAt: Date = .distantPast

    private let httpTimeout: Double = 120.0

    var availablePumps: [TandemPumpInfo] = []
    var selectedPumpAssignmentIdOverride: String? = nil
    @Published var basalSegments: [BasalSegment] = []
    @Published var bolusHistory: [BolusRecord] = []

    private struct BolusCandidate {
        let date: Date
        let code: Int
        let key: String
        let insulinDelivered: Double?
        let insulinRequested: Double?
        let carbAmount: Double?
        let bolusType: String?
        let bg: Double?
        let isExtended: Bool
    }

    struct TandemPumpInfo: Identifiable, Sendable {
        let id: String
        let serialNumber: String
        let modelName: String
        let hasData: Bool
        let lastDataDate: String?
    }

    init(email: String, password: String, region: TandemRegion) {
        self.email = email
        self.password = password
        self.region = region
        self.loginHelper = TandemLoginHelper(region: region)
        networkSession = loginHelper.browserSession()
        super.init()
        self.type = .tandemsource
    }

    // MARK: - Auth

    nonisolated private func hasValidAuth() -> Bool {
        return false
    }

    @MainActor
    private func hasValidAuthMain() -> Bool {
        guard let session = loginSession else { return false }
        let valid = !session.isExpired
        if !valid { plog("Token expired, needs re-auth", category: "tandem", level: .info) }
        return valid
    }

    @MainActor
    private func ensureAuth() async -> Bool {
        if !hasValidAuthMain() {
            plog("Auth invalid or expired, authenticating...", category: "tandem", level: .info)
            return await authenticate()
        }
        return true
    }

    @MainActor
    private func authenticate() async -> Bool {
        if isAuthenticating { return false }
        if unsuccessfulAuthAttempts > maxAuthAttempts {
            plog("Auth locked: \(unsuccessfulAuthAttempts) failed attempts", category: "tandem", level: .error)
            providerIssue = "Unable to connect to Tandem Source after \(maxAuthAttempts) attempts. Please check your credentials."
            return false
        }

        isAuthenticating = true
        providerIssue = nil
        plog("Authenticating (attempt \(unsuccessfulAuthAttempts + 1))...", category: "tandem", level: .info)

        do {
            let session = try await loginHelper.login(email: email, password: password)
            loginSession = session
            pumperId = session.pumperId
            pumpAssignmentId = nil
            auth = ProviderAuth(token: session.accessToken, expiry: session.accessTokenExpiresAt.timeIntervalSince1970)
            unsuccessfulAuthAttempts = 0
            isAuthenticating = false
            GlucoseSourceExtras.aid = .controliq
            RemoteGlucoseSource = .controliq
            plog("Authentication successful, pumperId=\(session.pumperId.prefix(8))..., token valid for \(String(format:"%.0f", session.accessTokenExpiresAt.timeIntervalSinceNow))s", category: "tandem", level: .info)
            return true
        } catch {
            plog("Authentication failed: \(error.localizedDescription)", category: "tandem", level: .error)
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
        if Date() < nextFetchAllowedAt {
            plog("Fetch skipped: cooldown until \(nextFetchAllowedAt.formatted())", category: "tandem", level: .info)
            return
        }

        plog("Fetch cycle starting", category: "tandem", level: .info)

        guard await ensureAuth() else {
            plog("Fetch skipped: not authenticated", category: "tandem", level: .info)
            return
        }

        var didTimeout = false

        do {
            try await fetchPumperInfo()
        } catch {
            plog("Pumper info fetch failed: \(error.localizedDescription)", category: "tandem", level: .error)
            providerIssue = "Tandem fetch error: \(error.localizedDescription)"
            didTimeout = isTimeout(error)
        }

        do {
            try await fetchPumpLogs()
        } catch {
            plog("Pump logs fetch failed: \(error.localizedDescription)", category: "tandem", level: .error)
            didTimeout = didTimeout || isTimeout(error)
        }

        if didTimeout {
            nextFetchAllowedAt = Date().addingTimeInterval(60)
            plog("Cooldown set for 60s due to timeout", category: "tandem", level: .info)
        }

        lastFetch = Date()
    }

    private func isTimeout(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
    }

    // MARK: - Pumper Info

    private func fetchPumperInfo() async throws {
        guard let token = loginSession?.accessToken,
              let pid = pumperId else { return }

        let url = region.sourceURL.appendingPathComponent("api/reports/bff/pumper/\(pid)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(region.sourceURL.absoluteString.dropSuffix("/"), forHTTPHeaderField: "Origin")
        request.setValue(region.sourceURL.absoluteString, forHTTPHeaderField: "Referer")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = httpTimeout

        plog("fetchPumperInfo: requesting...", category: "tandem", level: .debug)

        let (data, response) = try await networkSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            logResponse("fetchPumperInfo", status: status, body: data)
            if status == 401 {
                plog("fetchPumperInfo: token expired, clearing session", category: "tandem", level: .info)
                loginSession = nil
            }
            return
        }

        plog("fetchPumperInfo: response received, parsing...", category: "tandem", level: .debug)

        let rawJSON = String(data: data, encoding: .utf8)?.prefix(1000) ?? "<binary>"
        plog("fetchPumperInfo: raw JSON: \(rawJSON)", category: "tandem", level: .info)

        let pumper: BffPumper
        do {
            pumper = try JSONDecoder().decode(BffPumper.self, from: data)
        } catch {
            plog("fetchPumperInfo: decode failed: \(error)", category: "tandem", level: .error)
            return
        }

        if let pumps = pumper.pumps, !pumps.isEmpty {
            // Build pump info list for UI selector
            let infos: [TandemPumpInfo] = pumps.map { pump in
                let hasData = pump.availableDataRange?.end != nil
                return TandemPumpInfo(
                    id: pump.assignmentId ?? UUID().uuidString,
                    serialNumber: pump.serialNumber ?? "?",
                    modelName: pump.modelName ?? "?",
                    hasData: hasData,
                    lastDataDate: pump.availableDataRange?.end
                )
            }
            availablePumps = infos

            // Select best pump: user override > most recent data > first
            let selected: BffPump
            if let overrideId = selectedPumpAssignmentIdOverride,
               let match = pumps.first(where: { $0.assignmentId == overrideId }) {
                selected = match
                plog("Pumper: using user-selected pump \(match.serialNumber ?? "?")", category: "tandem", level: .info)
            } else {
                selected = pumps.max(by: { a, b in
                    (a.availableDataRange?.end ?? "") < (b.availableDataRange?.end ?? "")
                }) ?? pumps.first!
                plog("Pumper: auto-selected pump \(selected.serialNumber ?? "?"), \(pumps.count) pumps on account", category: "tandem", level: .info)
            }

            pumpAssignmentId = selected.assignmentId
            hasControlIQ = selected.algorithm == "Control-IQ"
            lowThreshold = pumper.lowGlucoseThreshold ?? 110
            highThreshold = pumper.highGlucoseThreshold ?? 180
            let dataEnd = selected.availableDataRange?.end ?? "never uploaded"
            plog("Pumper: serial=\(selected.serialNumber ?? "?"), model=\(selected.modelName ?? "?"), CIQ=\(hasControlIQ), targets=\(lowThreshold)-\(highThreshold), data till \(dataEnd)", category: "tandem", level: .info)
        } else {
            availablePumps = []
        }
    }

    // MARK: - Pump Logs

    private func fetchPumpLogs() async throws {
        guard let token = loginSession?.accessToken,
              let pid = pumperId,
              let deviceId = pumpAssignmentId else {
            plog("fetchPumpLogs: missing pumperId or pumpAssignmentId", category: "tandem", level: .debug)
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-86400)
        let startStr = formatter.string(from: startDate).prefix(10) // YYYY-MM-DD
        let endStr = formatter.string(from: endDate).prefix(10)

        let eventIds = "229,5,28,4,26,99,279,3,16,59,21,55,20,280,64,65,66,61,33,371,171,369,460,172,370,461,372,480,399,256,213,406,477,394,212,404,214,405,486,447,313,60,14,6,90,230,140,12,11,53,13,63,203,307,191"

        var components = URLComponents(url: region.sourceURL.appendingPathComponent("api/reports/bff/pump-logs/\(deviceId)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "pumperId", value: pid),
            URLQueryItem(name: "startDate", value: "\(startStr)T00:00:00Z"),
            URLQueryItem(name: "endDate", value: "\(endStr)T23:59:59Z"),
            URLQueryItem(name: "eventIds", value: eventIds)
        ]

        guard let requestURL = components.url else { return }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(region.sourceURL.absoluteString.dropSuffix("/"), forHTTPHeaderField: "Origin")
        request.setValue(region.sourceURL.absoluteString, forHTTPHeaderField: "Referer")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = httpTimeout

        plog("fetchPumpLogs: requesting events for device=\(deviceId.prefix(8))..., range=\(startStr) to \(endStr)", category: "tandem", level: .debug)

        let (data, response) = try await networkSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            logResponse("fetchPumpLogs", status: status, body: data)
            if status == 401 {
                loginSession = nil
            }
            return
        }

        let logs = try JSONDecoder().decode(PumpLogsResponse.self, from: data)
        let events = logs.events ?? []
        plog("fetchPumpLogs: received \(events.count) events", category: "tandem", level: .info)

        if events.isEmpty { return }

        parsePumpEvents(events)
    }

    // MARK: - Event Parsing

    private func parsePumpEvents(_ events: [PumpLogEvent]) {
        var cgmEntries: [GlucoseEntry] = []
        var iobValue: Double? = nil
        var newestIOBDate: Date = .distantPast
        var basalRate: Double? = nil
        var newestBasalDate: Date = .distantPast
        var cobValue: Double? = nil
        var newestCOBDate: Date = .distantPast
        var newestCIQDate: Date = .distantPast
        var segments: [BasalSegment] = []
        var bolusCandidates: [BolusCandidate] = []

        for event in events {
            guard let code = event.eventCode, let props = event.eventProperties else { continue }

            let date: Date = {
                if let ds = event.pumpDateTime, !ds.isEmpty {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                    return fmt.date(from: ds) ?? Date()
                }
                return Date()
            }()

            // Code 16: BG entry (calibration) with IOB
            if code == 16, let bg = props["bg"]?.intValue, bg > 0 {
                cgmEntries.append(GlucoseEntry(glucose: Double(bg), date: date, changeRate: 0.0))
                if let iob = props["iob"]?.doubleValue, date > newestIOBDate {
                    iobValue = iob; newestIOBDate = date
                }
            }

            // Code 399: CGM reading
            if code == 399, let egv = props["currentGlucoseDisplayValue"]?.intValue, egv > 0 {
                let cgmDate: Date = {
                    if let ts = props["egvTimeStamp"]?.doubleValue, ts > 1000000000 {
                        return Date(timeIntervalSince1970: ts / 1000)
                    }
                    if let ts = props["egvTimeStamp"]?.intValue, ts > 1000000000 {
                        return Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
                    }
                    return date
                }()
                cgmEntries.append(GlucoseEntry(glucose: Double(egv), date: cgmDate, changeRate: 0.0))
            }

            // Code 20, 55, 64: IOB snapshot from bolus/bg events
            if [20, 55, 64].contains(code), let iob = props["iob"]?.doubleValue, date > newestIOBDate {
                iobValue = iob; newestIOBDate = date
            }

            // Code 64: Bolus with carbs
            if code == 64 {
                if let carbs = props["carbAmount"]?.intValue, carbs > 0, date > newestCOBDate {
                    cobValue = Double(carbs); newestCOBDate = date
                }
            }

            // Code 90: CIQ basal rate
            if code == 90, let rate = props["commandedBasalRate"]?.doubleValue {
                let actual = rate / 1000
                if date > newestBasalDate { basalRate = actual; newestBasalDate = date }
                segments.append(BasalSegment(date: date, profileRate: actual, actualRate: actual))
            }

            // Code 279: Legacy basal rate with profile
            if code == 279 {
                if let rate = props["commandedRate"]?.doubleValue {
                    let actual = rate / 1000
                    if date > newestBasalDate { basalRate = actual; newestBasalDate = date }
                }
                let actual = (props["commandedRate"]?.doubleValue ?? 0) / 1000
                let profile = (props["profileBasalRate"]?.doubleValue ?? actual * 1000) / 1000
                segments.append(BasalSegment(date: date, profileRate: profile, actualRate: actual))
            }
            if code == 279, date > newestCIQDate {
                newestCIQDate = date
            }

            // Code 64: bolus IOB + target
            if code == 64, let iob = props["iob"]?.doubleValue, date > newestIOBDate {
                iobValue = iob; newestIOBDate = date
            }

            // --- Bolus event collection ---
            let bolusCodes: Set<Int> = [20, 55, 64, 66, 280]
            guard bolusCodes.contains(code) else { continue }

            let bKey: String = {
                if let bid = props["bolusId"]?.stringValue, !bid.isEmpty { return bid }
                if let bid = props["bolusId"]?.intValue { return String(bid) }
                return String(Int(date.timeIntervalSince1970 / 180))
            }()

            let bInsulin: Double? = {
                if let v = props["deliveredTotal"]?.doubleValue, v > 0 { return v }
                if let v = props["insulinDelivered"]?.doubleValue, v > 0 { return v }
                if let v = props["totalBolusSize"]?.doubleValue, v > 0 { return v }
                if let v = props["bolusSize"]?.doubleValue, v > 0 { return v }
                return nil
            }()

            let bRequested: Double? = {
                if let v = props["insulinRequested"]?.doubleValue { return v }
                if let v = props["requestedNow"]?.doubleValue { return v }
                return nil
            }()

            let bCarbs: Double? = props["carbAmount"]?.doubleValue
            let bBG: Double? = props["bg"]?.doubleValue
            let bType: String? = props["bolusType"]?.stringValue

            let bExtended: Bool = {
                if let dur = props["extendedDurationRequested"]?.doubleValue, dur > 0 { return true }
                if let std = props["standardPercent"]?.doubleValue, std < 100 { return true }
                return false
            }()

            bolusCandidates.append(BolusCandidate(
                date: date, code: code, key: bKey,
                insulinDelivered: bInsulin, insulinRequested: bRequested,
                carbAmount: bCarbs, bolusType: bType, bg: bBG, isExtended: bExtended
            ))
        }

        // --- Merge bolus candidates into records ---
        var bolusByKey: [String: (firstDate: Date, insD: Double?, insR: Double?, carbs: Double?, type: String?, bg: Double?, extended: Bool)] = [:]
        for c in bolusCandidates {
            var existing = bolusByKey[c.key] ?? (firstDate: c.date, insD: nil, insR: nil, carbs: nil, type: nil, bg: nil, extended: false)
            let keyDate = existing.firstDate
            let gap = abs(c.date.timeIntervalSince(keyDate))
            if gap > 180, c.key.count < 10 {
                let newKey = "\(c.key)_\(Int(c.date.timeIntervalSince1970))"
                bolusByKey[newKey] = (firstDate: c.date, insD: c.insulinDelivered, insR: c.insulinRequested, carbs: c.carbAmount, type: c.bolusType, bg: c.bg, extended: c.isExtended)
                continue
            }
            existing.firstDate = min(existing.firstDate, c.date)
            existing.insD = c.insulinDelivered ?? existing.insD
            existing.insR = c.insulinRequested ?? existing.insR
            existing.carbs = c.carbAmount ?? existing.carbs
            existing.type = c.bolusType ?? existing.type
            existing.bg = c.bg ?? existing.bg
            existing.extended = existing.extended || c.isExtended
            bolusByKey[c.key] = existing
        }

        var records: [BolusRecord] = []
        for (key, b) in bolusByKey {
            guard let ins = b.insD, ins > 0 else { continue }
            records.append(BolusRecord(
                date: b.firstDate,
                insulinDelivered: ins,
                insulinRequested: b.insR,
                carbAmount: b.carbs,
                bolusType: b.type,
                bg: b.bg,
                isExtended: b.extended,
                eventCode: key.count < 10 ? (Int(key) ?? 0) : 0
            ))
        }
        bolusHistory = records.sorted(by: { $0.date > $1.date })
        plog("Bolus history: \(bolusHistory.count) records", category: "tandem", level: .info)

        if !cgmEntries.isEmpty {
            let sorted = cgmEntries.sorted(by: { $0.date > $1.date })
            setGlucoseEntries(sorted)
            plog("Parsed \(sorted.count) CGM entries (latest: \(String(format:"%.0f", sorted.first!.glucose)) at \(sorted.first!.date.formatted()))", category: "tandem", level: .info)
        }

        var extras = GlucoseSourceExtras
        extras.aid = .controliq
        extras.glucoseTarget = Double(lowThreshold)
        if hasControlIQ {
            extras.reason = "Control-IQ active"
        } else if let sn = (availablePumps.first(where: { $0.id == pumpAssignmentId }))?.serialNumber {
            extras.reason = "Pump SN: \(sn)"
        }
        if newestCIQDate != .distantPast {
            extras.enactedAt = newestCIQDate
        }
        if let iob = iobValue {
            extras.iob = iob
            plog("IOB: \(String(format:"%.2f", iob))U", category: "tandem", level: .info)
        }
        if let cob = cobValue {
            extras.cob = cob
            plog("COB: \(String(format:"%.0f", cob))g", category: "tandem", level: .info)
        }
        if let rate = basalRate {
            extras.basalRate = rate
            plog("Basal: \(String(format:"%.3f", rate))U/hr", category: "tandem", level: .info)
        }
        GlucoseSourceExtras = extras
        basalSegments = segments.sorted(by: { $0.date < $1.date })
        plog("Basal segments: \(segments.count)", category: "tandem", level: .info)
    }

    // MARK: - Helpers

    private func logResponse(_ label: String, status: Int, body data: Data) {
        let preview = String(data: data, encoding: .utf8)?.prefix(500) ?? "<binary>"
        plog("\(label): HTTP \(status), body: \(preview)", category: "tandem", level: .info)
    }

    override func plog(_ message: String, category: String, level: OSLogType = .default) {
        Logger(subsystem: "tools.t1d.GlucoseBar", category: "tandem")
            .dlog(message, category: category, level: level)
    }
}

extension String {
    func dropSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }
}
