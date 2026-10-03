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
    private let endpoints: TandemEndpoints

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
    private var lastAuthAttempt: Date = .distantPast
    private var nextFetchAllowedAt: Date = .distantPast

    /// HTTP-level failures (non-200 responses, undecodable bodies) from the BFF
    /// drive a progressive backoff: Tandem's pump-logs interface is validated by
    /// zod server-side, so a contract break (e.g. the `eventIds` -> `eventCodes`
    /// rename, 2026-10-01) fails with a stable non-200. Hammering that is
    /// pointless, so consecutive failures escalate to one request per hour and
    /// reset on the first success. Transport-level failures (network down,
    /// timeouts) intentionally do NOT advance the chain: a transient offline
    /// period must recover at the normal cadence instead of waiting out the cap.
    private var consecutiveFetchFailures: Int = 0
    private let backoffIntervals: [TimeInterval] = [60, 300, 900, 1800, 3600] // 1m -> 5m -> 15m -> 30m -> 1h (cap)

    private let httpTimeout: Double = 120.0

    var availablePumps: [TandemPumpInfo] = []
    var selectedPumpAssignmentIdOverride: String? = nil
    @Published var basalSegments: [BasalSegment] = []
    @Published var bolusHistory: [BolusRecord] = []
    @Published var pumpDIAHours: Double? = nil
    @Published var modeTimeline: [ModeChange] = []

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

    init(email: String, password: String, region: TandemRegion, endpoints: TandemEndpoints) {
        self.email = email
        self.password = password
        self.endpoints = endpoints
        self.loginHelper = TandemLoginHelper(region: region, endpoints: endpoints)
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
        if !valid { plog("Token expired, needs re-auth", category: "tandemsource", level: .info) }
        return valid
    }

    @MainActor
    private func ensureAuth() async -> Bool {
        if !hasValidAuthMain() {
            plog("Auth invalid or expired, authenticating...", category: "tandemsource", level: .info)
            return await authenticate()
        }
        return true
    }

    @MainActor
    private func authenticate() async -> Bool {
        if isAuthenticating { return false }
        if unsuccessfulAuthAttempts > maxAuthAttempts {
            if Date().timeIntervalSince(lastAuthAttempt) > 900 {
                unsuccessfulAuthAttempts = 0
            } else {
                plog("Auth locked: \(unsuccessfulAuthAttempts) failed attempts", category: "tandemsource", level: .error)
                providerIssue = "Unable to connect to Tandem Source after \(maxAuthAttempts) attempts. Please check your credentials."
                return false
            }
        }

        isAuthenticating = true
        providerIssue = nil
        plog("Authenticating (attempt \(unsuccessfulAuthAttempts + 1))...", category: "tandemsource", level: .info)

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
            plog("Authentication successful, pumperId=\(session.pumperId.prefix(8))..., token valid for \(String(format:"%.0f", session.accessTokenExpiresAt.timeIntervalSinceNow))s", category: "tandemsource", level: .info)
            return true
        } catch {
            plog("Authentication failed: \(error.localizedDescription)", category: "tandemsource", level: .error)
            let nsErr = error as NSError
            let networkCodes = [NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost,
                                NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost,
                                NSURLErrorTimedOut, NSURLErrorDNSLookupFailed]
            let isNetworkError = nsErr.domain == NSURLErrorDomain && networkCodes.contains(nsErr.code)
            if isNetworkError {
                noteTransportFailure()
            }
            if !isNetworkError { unsuccessfulAuthAttempts += 1 }
            lastAuthAttempt = Date()
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
            plog("Fetch skipped: cooldown until \(nextFetchAllowedAt.formatted())", category: "tandemsource", level: .info)
            return
        }

        plog("Fetch cycle starting", category: "tandemsource", level: .info)

        guard await ensureAuth() else {
            plog("Fetch skipped: not authenticated", category: "tandemsource", level: .info)
            return
        }

        var didTimeout = false

        do {
            try await fetchPumperInfo()
        } catch {
            noteTransportFailure()
            plog("Pumper info fetch failed: \(error.localizedDescription)", category: "tandemsource", level: .error)
            if !isTransportFailure(error) {
                registerFetchFailure(endpoint: "pumper", status: nil)
            }
            didTimeout = isTimeout(error)
        }

        do {
            try await fetchPumpLogs()
        } catch {
            noteTransportFailure()
            plog("Pump logs fetch failed: \(error.localizedDescription)", category: "tandemsource", level: .error)
            if !isTransportFailure(error) {
                registerFetchFailure(endpoint: "pump-logs", status: nil)
            }
            didTimeout = didTimeout || isTimeout(error)
        }

        if didTimeout {
            let cooldownUntil = Date().addingTimeInterval(60)
            if cooldownUntil > nextFetchAllowedAt {
                nextFetchAllowedAt = cooldownUntil
            }
            plog("Cooldown set for 60s due to timeout", category: "tandemsource", level: .info)
        }

        lastFetch = Date()
    }

    /// A request that ended below the HTTP layer (timeout, refused, DNS, lost
    /// connection). These are reachability problems, not contract problems, and
    /// must not advance the failure backoff.
    private func isTransportFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost,
                NSURLErrorTimedOut, NSURLErrorDNSLookupFailed].contains(nsError.code)
    }

    /// Records a pump-data failure (Tandem answered, but with a non-200 status
    /// or an undecodable body), surfaces it in the popover, and escalates the
    /// cooldown towards the once-per-hour cap.
    @MainActor
    private func registerFetchFailure(endpoint: String, status: Int?) {
        consecutiveFetchFailures = min(consecutiveFetchFailures + 1, backoffIntervals.count)
        let level = consecutiveFetchFailures - 1
        let wait = backoffIntervals[level]
        nextFetchAllowedAt = Date().addingTimeInterval(wait)

        let detail = status.map { "HTTP \($0)" } ?? "unexpected response"
        // User-facing text: keep it simple for non-technical users, but embed a
        // maintainer-recognizable code so an issue report signals a likely
        // Tandem-side API contract break (e.g. the `eventIds` -> `eventCodes`
        // rename, 2026-10-01). The error popover pairs this with a
        // "Report Issue on GitHub" button that prefills an issue.
        providerIssue = "Experiencing issues with Tandem (error code: TANDEM-API-CHANGE). Your data will resume automatically once Tandem responds. If it keeps happening, report it below so we can investigate."
        plog("\(endpoint) failed (\(detail)); next fetch in \(Int(wait))s (consecutive HTTP failures: \(consecutiveFetchFailures))", category: "tandemsource", level: .error)
    }

    /// Clears the failure state and any pending cooldown once pump data flows
    /// again. No-op when there was nothing to reset.
    @MainActor
    private func registerFetchSuccess() {
        guard consecutiveFetchFailures > 0 else { return }
        consecutiveFetchFailures = 0
        nextFetchAllowedAt = .distantPast
        providerIssue = nil
        plog("Tandem fetch recovered; backoff reset", category: "tandemsource", level: .info)
    }

    private func isTimeout(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
    }

    // MARK: - Pumper Info

    private func fetchPumperInfo() async throws {
        guard let token = loginSession?.accessToken,
              let pid = pumperId else { return }

        let url = endpoints.sourceURL.appendingPathComponent("api/reports/bff/pumper/\(pid)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(endpoints.sourceURL.absoluteString.dropSuffix("/"), forHTTPHeaderField: "Origin")
        request.setValue(endpoints.sourceURL.absoluteString, forHTTPHeaderField: "Referer")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = httpTimeout

        let (data, response) = try await networkSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            noteTransportFailure()
            logResponse("fetchPumperInfo", status: -1, body: data)
            return
        }

        noteResponseReceived()

        guard httpResponse.statusCode == 200 else {
            logResponse("fetchPumperInfo", status: httpResponse.statusCode, body: data)
            if httpResponse.statusCode == 401 {
                plog("fetchPumperInfo: token expired, clearing session", category: "tandemsource", level: .info)
                loginSession = nil
            }
            registerFetchFailure(endpoint: "pumper", status: httpResponse.statusCode)
            return
        }

        let pumper: BffPumper
        do {
            pumper = try JSONDecoder().decode(BffPumper.self, from: data)
        } catch {
            plog("fetchPumperInfo: decode failed: \(error)", category: "tandemsource", level: .error)
            registerFetchFailure(endpoint: "pumper", status: nil)
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
                plog("Pumper: using user-selected pump \(match.serialNumber ?? "?")", category: "tandemsource", level: .info)
            } else {
                selected = pumps.max(by: { a, b in
                    (a.availableDataRange?.end ?? "") < (b.availableDataRange?.end ?? "")
                }) ?? pumps.first!
                plog("Pumper: auto-selected pump \(selected.serialNumber ?? "?"), \(pumps.count) pumps on account", category: "tandemsource", level: .info)
            }

            pumpAssignmentId = selected.assignmentId
            hasControlIQ = selected.algorithm == "Control-IQ"
            lowThreshold = pumper.lowGlucoseThreshold ?? 110
            highThreshold = pumper.highGlucoseThreshold ?? 180
            if let diaMin = selected.settings?.details?.activeProfileDiaMinutes {
                pumpDIAHours = diaMin / 60
            }
            let dataEnd = selected.availableDataRange?.end ?? "never uploaded"
            plog("Pumper: serial=\(selected.serialNumber ?? "?"), model=\(selected.modelName ?? "?"), CIQ=\(hasControlIQ), targets=\(lowThreshold)-\(highThreshold), data till \(dataEnd)", category: "tandemsource", level: .info)
        } else {
            availablePumps = []
        }
    }

    // MARK: - Pump Logs

    private func fetchPumpLogs() async throws {
        guard let token = loginSession?.accessToken,
              let pid = pumperId,
              let deviceId = pumpAssignmentId else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-86400)
        let startStr = formatter.string(from: startDate).prefix(10) // YYYY-MM-DD
        let endStr = formatter.string(from: endDate).prefix(10)

        let eventCodes = "229,5,28,4,26,99,279,3,16,59,21,55,20,280,64,65,66,61,33,371,171,369,460,172,370,461,372,480,399,256,213,406,477,394,212,404,214,405,486,447,313,60,14,6,90,230,140,12,11,53,13,63,203,307,191"

        // Tandem renamed the filter query param `eventIds` -> `eventCodes` on the
        // BFF (2026-10-01). `eventIds` is now rejected with a zod 400
        // "unrecognized_keys". Verified live: single comma-separated value only;
        // repeated keys return 0 events.
        var components = URLComponents(url: endpoints.sourceURL.appendingPathComponent("api/reports/bff/pump-logs/\(deviceId)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "pumperId", value: pid),
            URLQueryItem(name: "startDate", value: "\(startStr)T00:00:00Z"),
            URLQueryItem(name: "endDate", value: "\(endStr)T23:59:59Z"),
            URLQueryItem(name: "eventCodes", value: eventCodes)
        ]

        guard let requestURL = components.url else { return }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(endpoints.sourceURL.absoluteString.dropSuffix("/"), forHTTPHeaderField: "Origin")
        request.setValue(endpoints.sourceURL.absoluteString, forHTTPHeaderField: "Referer")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = httpTimeout

        let (data, response) = try await networkSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            noteTransportFailure()
            logResponse("fetchPumpLogs", status: -1, body: data)
            return
        }

        noteResponseReceived()

        guard httpResponse.statusCode == 200 else {
            logResponse("fetchPumpLogs", status: httpResponse.statusCode, body: data)
            if httpResponse.statusCode == 401 {
                loginSession = nil
            }
            registerFetchFailure(endpoint: "pump-logs", status: httpResponse.statusCode)
            return
        }

        let logs = try JSONDecoder().decode(PumpLogsResponse.self, from: data)
        let events = logs.events ?? []
        plog("fetchPumpLogs: received \(events.count) events", category: "tandemsource", level: .info)
        registerFetchSuccess()

        if events.isEmpty { return }

        parsePumpEvents(events)
    }

    // MARK: - Event Parsing

    private func parsePumpEvents(_ events: [PumpLogEvent]) {
        // --- Date helpers ---
        let iso8601Frac = ISO8601DateFormatter()
        iso8601Frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        let manualFmt = DateFormatter()
        manualFmt.locale = Locale(identifier: "en_US_POSIX")
        manualFmt.timeZone = TimeZone(secondsFromGMT: 0)
        manualFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        func parseISO(_ s: String) -> Date? {
            if let d = iso8601Frac.date(from: s) { return d }
            if let d = iso8601.date(from: s) { return d }
            let clean = s.hasSuffix("Z") ? String(s.dropLast()) : s
            return manualFmt.date(from: clean)
        }

        func fallbackDate(for event: PumpLogEvent) -> Date {
            if let ds = event.estimatedDateTime, !ds.isEmpty, let d = parseISO(ds) { return d }
            if let ds = event.pumpDateTime, !ds.isEmpty, let d = parseISO(ds) { return d }
            return Date()
        }

        func wrap32(_ delta: Int) -> Int {
            delta >= 0 ? delta : Int(Int64(delta) &+ (1 << 32))
        }

        // RTC deltas larger than the fetch window are wrap/ordering artifacts;
        // reject them so poisoned dates (e.g. ~136 years off) never reach the UI.
        func safeDate(rtc: Int, ref: Int, refD: Date) -> Date? {
            let delta = wrap32(rtc - ref)
            guard delta < 86400 * 2 else { return nil }
            return refD.addingTimeInterval(TimeInterval(delta))
        }

        // Final sanity check: reject dates far outside the fetch window (the
        // pump-log query spans ~24-48h). Falls back to the API timestamp, then to now.
        func sanitizeDate(_ date: Date, fallback: Date) -> Date {
            let window: TimeInterval = 86400 * 3
            if abs(date.timeIntervalSinceNow) <= window { return date }
            if abs(fallback.timeIntervalSinceNow) <= window { return fallback }
            return Date()
        }

        func propStr(_ p: PumpLogProperty) -> String {
            switch p {
            case .int(let v): return "\(v)"
            case .double(let v): return "\(v)"
            case .string(let v): return v
            case .bool(let v): return "\(v)"
            case .array(let v): return "[\(v.map(propStr).joined(separator: ","))]"
            case .dictionary(let v): return "{\(v.map { "\($0.key):\(propStr($0.value))" }.joined(separator: ","))}"
            case .null: return "null"
            }
        }

        // --- Debug dump: raw CGM-related events to diagnose duplicate readings ---
        let evtFmt = ISO8601DateFormatter()
        evtFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for event in events {
            guard let code = event.eventCode, code == 399 || code == 16 else { continue }
            let props = event.eventProperties?.sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\(propStr($0.value))" }
                .joined(separator: " ") ?? "none"
            plog("CGM_EVENT code=\(code) group=\(event.sequenceGroup ?? -1) num=\(event.sequenceNumber ?? -1) est=\(event.estimatedDateTime ?? "nil") pump=\(event.pumpDateTime ?? "nil") props={\(props)}", category: "tandemsource", level: .info)
        }

        // --- Pass 1: build CGM anchor with RTC-based times ---
        struct CGMAnchor { let seq: Int; let rtc: Int; let date: Date }
        var cgmAnchors: [CGMAnchor] = []

        var refRtc: Int?
        var refDate: Date?
        struct CGMPoint { let seq: Int; let entry: GlucoseEntry }
        var cgmEntries: [CGMPoint] = []

        // Also collect raw non-CGM events for pass 2
        struct RawEvent { let event: PumpLogEvent; let seq: Int; let fallback: Date }
        var rawEvents: [RawEvent] = []

        for event in events {
            let seq = (event.sequenceGroup ?? 0) * 1_000_000 + (event.sequenceNumber ?? 0)
            guard let code = event.eventCode, let props = event.eventProperties else { continue }

            if code == 399,
               let rtc = props["egvTimeStamp"]?.intValue,
               let egv = props["currentGlucoseDisplayValue"]?.intValue, egv > 0 {
                var date: Date
                if let ref = refRtc, let refD = refDate, let safe = safeDate(rtc: rtc, ref: ref, refD: refD) {
                    date = safe
                } else {
                    // RTC wrapped (new CGM session) or no anchor yet: re-anchor to the
                    // API timestamp so post-wrap readings spread out via RTC deltas
                    // instead of collapsing onto a single shared fallback timestamp.
                    date = fallbackDate(for: event)
                    if let edt = event.estimatedDateTime, !edt.isEmpty, let d = parseISO(edt) {
                        refRtc = rtc
                        refDate = d
                    }
                }
                // RTC timestamps are not monotonic across CGM sessions (they reset/wrap),
                // so a purely RTC-derived date can be hours off. If it disagrees with the
                // API's own timestamp by more than 5 minutes, trust the API timestamp.
                if let edt = event.estimatedDateTime, !edt.isEmpty, let ed = parseISO(edt),
                   abs(date.timeIntervalSince(ed)) > 300 {
                    date = ed
                }
                date = sanitizeDate(date, fallback: fallbackDate(for: event))
                cgmEntries.append(CGMPoint(seq: seq, entry: GlucoseEntry(glucose: Double(egv), date: date, changeRate: 0.0)))
                cgmAnchors.append(CGMAnchor(seq: seq, rtc: rtc, date: date))
                continue
            }

            rawEvents.append(RawEvent(event: event, seq: seq, fallback: fallbackDate(for: event)))
        }

        cgmAnchors.sort(by: { $0.seq < $1.seq })

        // --- Pre-scan: collect profile basal anchors from code 279 ---
        var profileAnchors: [(Date, Double)] = []
        for raw in rawEvents {
            let code = raw.event.eventCode!
            if code == 279,
               let props = raw.event.eventProperties,
               let rate = props["profileBasalRate"]?.intValue {
                profileAnchors.append((raw.fallback, Double(rate) / 1000))
            }
        }
        profileAnchors.sort(by: { $0.0 < $1.0 })
        func profileRate(at date: Date) -> Double? {
            profileAnchors.last(where: { $0.0 <= date })?.1
        }

        // --- Pass 2: process non-CGM events with interpolated RTC times ---
        var iobValue: Double? = nil
        var newestIOBDate: Date = .distantPast
        var basalRate: Double? = nil
        var newestBasalDate: Date = .distantPast
        var cobValue: Double? = nil
        var newestCOBDate: Date = .distantPast
        var newestCIQDate: Date = .distantPast
        var segments: [BasalSegment] = []
        var bolusCandidates: [BolusCandidate] = []
        var modeChanges: [ModeChange] = []

        for raw in rawEvents {
            let code = raw.event.eventCode!
            let props = raw.event.eventProperties!
            let seq = raw.seq

            var date: Date
            var code16BG: Int? = nil
            if code == 16, let bg = props["bg"]?.intValue, bg > 0 {
                // Code 16 BG entries: use estimateDateTime directly (no RTC)
                date = raw.fallback
                code16BG = bg
            } else if let rtc = props["egvTimeStamp"]?.intValue ?? props["rawRtcTime"]?.intValue,
                      let ref = refRtc, let refD = refDate {
                // Has RTC: compute directly
                if let safe = safeDate(rtc: rtc, ref: ref, refD: refD) {
                    date = safe
                } else {
                    date = raw.fallback
                }
            } else if !cgmAnchors.isEmpty {
                // No RTC: interpolate between CGM anchors
                var before: CGMAnchor?, after: CGMAnchor?
                for a in cgmAnchors { if a.seq <= seq { before = a } else { after = a; break } }
                if before == nil, let a = cgmAnchors.first { before = a }
                if after == nil, let a = cgmAnchors.last { after = a }
                if let b = before, let a = after, let ref = refRtc, let refD = refDate {
                    let rtcDelta = wrap32(a.rtc - b.rtc)
                    let frac = a.seq > b.seq ? Double(seq - b.seq) / Double(a.seq - b.seq) : 0
                    let interpRtc = b.rtc + Int(Double(rtcDelta) * frac)
                    date = refD.addingTimeInterval(TimeInterval(wrap32(interpRtc - ref)))
                } else {
                    date = raw.fallback
                }
            } else {
                date = raw.fallback
            }

            date = sanitizeDate(date, fallback: raw.fallback)

            // Same RTC-vs-API sanity check as pass 1 (non-CGM events).
            if let edt = raw.event.estimatedDateTime, !edt.isEmpty, let ed = parseISO(edt),
               abs(date.timeIntervalSince(ed)) > 300 {
                date = ed
            }

            if let bg = code16BG {
                cgmEntries.append(CGMPoint(seq: seq, entry: GlucoseEntry(glucose: Double(bg), date: date, glucoseType: .meter, changeRate: 0.0)))
                if let iob = props["iob"]?.doubleValue, date > newestIOBDate {
                    iobValue = iob; newestIOBDate = date
                }
            }

            // Code 20, 55, 64: IOB snapshot
            if [20, 55, 64].contains(code), let iob = props["iob"]?.doubleValue, date > newestIOBDate {
                iobValue = iob; newestIOBDate = date
            }

            // Code 64: Bolus with carbs
            if code == 64, let carbs = props["carbAmount"]?.intValue, carbs > 0, date > newestCOBDate {
                cobValue = Double(carbs); newestCOBDate = date
            }

            // Code 90: CIQ basal rate
            if code == 90, let rate = props["commandedBasalRate"]?.doubleValue {
                let actual = rate / 1000
                let profile = profileRate(at: date) ?? actual
                if date > newestBasalDate { basalRate = actual; newestBasalDate = date }
                segments.append(BasalSegment(date: date, profileRate: profile, actualRate: actual))
            }

            // Code 279: Legacy basal rate with profile (skip when no commanded rate,
            // otherwise the missing rate reads as a spurious zero-delivery segment)
            if code == 279, let commanded = props["commandedRate"]?.doubleValue {
                let actual = commanded / 1000
                if date > newestBasalDate { basalRate = actual; newestBasalDate = date }
                let profile = (props["profileBasalRate"]?.doubleValue ?? commanded) / 1000
                segments.append(BasalSegment(date: date, profileRate: profile, actualRate: actual))
            }
            if code == 279, date > newestCIQDate {
                newestCIQDate = date
            }

            // Code 64: bolus IOB + target
            if code == 64, let iob = props["iob"]?.doubleValue, date > newestIOBDate {
                iobValue = iob;
                newestIOBDate = date
            }

            // --- Mode timeline: codes 229, 230, 11, 12 ---
            let mode: String? = {
                switch code {
                case 229:
                    let current = props["currentUserMode"]?.intValue
                    if current == 1 { return "Sleep" }
                    if current == 2 { return "Exercise" }
                    if current == 3 { return "Eating Soon" }
                    return "Normal"
                case 230:
                    if props["pumpSuspended"]?.boolValue == true { return "Suspended" }
                    return nil
                case 11: return "Suspended"
                case 12: return "Normal"
                default: return nil
                }
            }()
            if let mode = mode {
                modeChanges.append(ModeChange(date: date, mode: mode, endDate: date))
                plog("Mode: \(mode) (event \(code))", category: "tandemsource", level: .info)
            }

            // --- Bolus event collection ---
            guard [20, 55, 64, 66, 280].contains(code) else { continue }

            let bKey: String = {
                if let bid = props["bolusId"]?.stringValue, !bid.isEmpty { return bid }
                if let bid = props["bolusId"]?.intValue { return String(bid) }
                return String(Int(date.timeIntervalSince1970 / 180))
            }()

            let bInsulin: Double? = {
                if let v = props["deliveredTotal"]?.doubleValue, v >= 50 { return v / 1000 }
                if let v = props["insulinDelivered"]?.doubleValue, v >= 50 { return v / 1000 }
                if let v = props["totalBolusSize"]?.doubleValue, v >= 50 { return v / 1000 }
                if let v = props["requestedNow"]?.doubleValue, v >= 50 { return v / 1000 }
                return nil
            }()

            let bRequested: Double? = {
                let val = props["insulinRequested"]?.doubleValue ?? props["requestedNow"]?.doubleValue
                if let v = val, v > 0 {
                    return v / 1000
                }
                return nil
            }()
            let bCarbs: Double? = props["carbAmount"]?.doubleValue
            let bBG: Double? = props["bg"]?.doubleValue
            let bType: String? = props["bolusType"]?.stringValue
            let bExtended = (props["extendedDurationRequested"]?.doubleValue ?? 0) > 0 || (props["standardPercent"]?.doubleValue ?? 100) < 100

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
            let gap = abs(c.date.timeIntervalSince(existing.firstDate))
            if gap > 180, c.key.count < 10 {
                bolusByKey["\(c.key)_\(Int(c.date.timeIntervalSince1970))"] = (firstDate: c.date, insD: c.insulinDelivered, insR: c.insulinRequested, carbs: c.carbAmount, type: c.bolusType, bg: c.bg, extended: c.isExtended)
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
                date: b.firstDate, insulinDelivered: ins, insulinRequested: b.insR,
                carbAmount: b.carbs, bolusType: b.type, bg: b.bg,
                isExtended: b.extended, eventCode: key.count < 10 ? (Int(key) ?? 0) : 0
            ))
        }
        bolusHistory = records.sorted(by: { $0.date > $1.date })

        // Buffered CGM readings (e.g. after a sensor gap) can share a single
        // timestamp. Instead of discarding them, spread each stacked run backward
        // at the known 5-minute CGM interval, ordered by sequence number, so the
        // trace shows a continuous line rather than a vertical stack.
        func spreadStackedPoints(_ points: [CGMPoint]) -> [CGMPoint] {
            let sorted = points.sorted { $0.entry.date > $1.entry.date }
            guard sorted.count > 1 else { return sorted }
            var result: [CGMPoint] = []
            var i = 0
            while i < sorted.count {
                var run = [sorted[i]]
                i += 1
                while i < sorted.count, sorted[i].entry.date == run[0].entry.date {
                    run.append(sorted[i])
                    i += 1
                }
                if run.count == 1 {
                    result.append(run[0])
                } else {
                    let ordered = run.sorted { $0.seq > $1.seq }
                    for (j, p) in ordered.enumerated() {
                        let pushed = run[0].entry.date.addingTimeInterval(TimeInterval(-j * 300))
                        let e = p.entry
                        result.append(CGMPoint(seq: p.seq, entry: GlucoseEntry(
                            glucose: e.glucose, date: pushed, glucoseType: e.glucoseType,
                            trend: e.trend, changeRate: e.changeRate, isCalibration: e.isCalibration,
                            condition: e.condition, id: e.id)))
                    }
                }
            }
            return result
        }

        if !cgmEntries.isEmpty {
            let spread = spreadStackedPoints(cgmEntries)
            setGlucoseEntries(spread.map { $0.entry })
        }

        var extras = GlucoseSourceExtras
        extras.aid = .controliq
        extras.glucoseTarget = Double(lowThreshold)
        extras.diaHours = pumpDIAHours
        extras.reason = hasControlIQ ? "Control-IQ active" : "Pump SN: \(availablePumps.first(where: { $0.id == pumpAssignmentId })?.serialNumber ?? "?")"
        if newestCIQDate != .distantPast { extras.enactedAt = newestCIQDate }
        if let iob = iobValue { extras.iob = iob }
        if let cob = cobValue { extras.cob = cob }
        if let rate = basalRate { extras.basalRate = rate }
        GlucoseSourceExtras = extras
        basalSegments = segments.sorted(by: { $0.date < $1.date })

        let sortedModes = modeChanges.sorted(by: { $0.date < $1.date })
        var paired: [ModeChange] = []
        for (i, mc) in sortedModes.enumerated() {
            let end = i + 1 < sortedModes.count ? sortedModes[i + 1].date : Date()
            paired.append(ModeChange(id: mc.id, date: mc.date, mode: mc.mode, endDate: end))
        }
        self.modeTimeline = paired
        plog("Mode timeline: \(paired.count) changes", category: "tandemsource", level: .info)
    }

    // MARK: - Helpers

    private func logResponse(_ label: String, status: Int, body data: Data) {
        let preview = String(data: data, encoding: .utf8)?.prefix(500) ?? "<binary>"
        plog("\(label): HTTP \(status), body: \(preview)", category: "tandemsource", level: .info)
    }
}

extension String {
    func dropSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }
}
