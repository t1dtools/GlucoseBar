//
//  CGMProvider.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-10-16.
//

import Foundation
import OSLog
import SwiftUI

public enum CGMProvider: String, CaseIterable, Identifiable {
    case null
    case simulator
    case nightscout
    case dexcomshare
    case tandemsource
    public var id: String { self.rawValue }
    public var presentable: String {
        switch self {
        case .null:
            return String(localized: "No provider", comment: "The name for when no CGM data provider has been chosen yet")
        case .simulator:
            return String(localized: "Simulator", comment: "The name for the Simulator CGM data provider")
        case .nightscout:
            return String(localized: "Nightscout", comment: "The name for the Nightscout CGM data provider")
        case .dexcomshare:
            return String(localized: "Dexcom Share", comment: "The name for the Dexcom Share CGM data provider")
        case .tandemsource:
            return String(localized: "Tandem Source", comment: "The name for the Tandem Source CGM data provider")
        }
    }
}

struct ProviderAuth: Decodable {
    var token: String
    var expiry: Double
}

/// Classifies a provider issue so the UI can present a tailored, actionable
/// message instead of a generic error. Set alongside `providerIssue` via
/// `setIssue(_:kind:)`.
///
/// Credential rejections are deliberately distinguished from transient
/// failures: only the former should prompt the user to revisit their sign-in
/// details in Settings, and only the former warrant pausing the normal fetch
/// cadence while the settings are unchanged.
enum ProviderIssueKind: String, Equatable, Sendable {
    case none
    /// The provider definitively rejected our sign-in (bad username, password,
    /// or token). The user must fix their credentials in Settings.
    case credentials
    /// Required settings are invalid or missing (empty field, malformed URL).
    case configuration
    /// Reachable and authenticated, but the provider has no measurements to
    /// offer (e.g. Dexcom Share with no follower / sensor warm-up).
    case noData
    /// The provider's API contract changed under us. The user cannot fix it;
    /// GlucoseBar must ship an update.
    case apiChange
    /// Network, server, rate-limit, or decoding problem that may recover on its
    /// own without any user action.
    case transient
}

struct GlucoseSourceExtraProperties {
    var aid: GlucoseSourceDevice = .null
    var iob: Double? = nil
    var cob: Double? = nil
    var basalRate: Double? = nil
    var eventualGlucose: Double? = nil
    var reason: String? = nil
    var enactedAt: Date? = nil
    var forecasts: AIDForecasts = AIDForecasts(iob: nil, cob: nil, zt: nil, uam: nil)
    var glucoseTarget: Double? = nil
    var error: String? = nil
    var diaHours: Double? = nil
}

struct AIDForecasts: Decodable {
    var iob: [Int]?
    var cob: [Int]?
    var zt: [Int]?
    var uam: [Int]?
    var loop: [Int]?

    static func fromPredBGs(predBGs: PredBGs?) -> AIDForecasts {
        return AIDForecasts(
            iob: predBGs?.iob,
            cob: predBGs?.cob,
            zt: predBGs?.zt,
            uam: predBGs?.uam
        )
    }

    static func fromLoopPredicted(_ loopPredicted: LoopPredicted?) -> AIDForecasts {
        let loopValues: [Int]? = {
            guard var values = loopPredicted?.values else { return nil }
            values.removeFirst()
            return values.map {
                Int(($0).rounded())
            }
        }()
        return AIDForecasts(loop: loopValues)
    }
}

class Provider: ObservableObject, @unchecked Sendable {

    var type: CGMProvider = .null
    var isBaseProvider: Bool = true
    internal var readingInterval: Double = 300 // Seconds between readings

    var sourceIndex: Int = -1
    let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "provider")

    func plog(_ message: String, category: String, level: OSLogType = .default) {
        let taggedCategory = sourceIndex < 0 ? category : "\(category)/\(sourceIndex)"
        let cat = sourceIndex < 0 ? "provider" : "provider/\(sourceIndex)"
        Logger(subsystem: "tools.t1d.GlucoseBar", category: cat)
            .dlog(message, category: taggedCategory, level: level)
    }
    @Published var RemoteGlucoseSource: GlucoseSourceDevice = .null
    @Published private var _glucoseEntries: [GlucoseEntry] = []

    @Published var GlucoseSourceExtras: GlucoseSourceExtraProperties = GlucoseSourceExtraProperties()
    @Published public var providerIssue: String?
    /// Classification of `providerIssue`, for views that need to tell a bad
    /// password apart from a temporary outage. `.none` whenever there is no
    /// issue (or, for providers that predate this, when unset).
    @Published public var issueKind: ProviderIssueKind = .none
    @Published public var lastFetch: Date = Date().addingTimeInterval(TimeInterval(-5*60))
    @Published public var isAuthenticating: Bool = false
    @Published var auth: ProviderAuth?

    @Published var connectionID: String = ""

    /// Consecutive transport-level failures (timeout, refused, DNS, or a
    /// non-HTTP response). Reset to zero whenever ANY HTTP response arrives,
    /// including error-status ones — a 401/403/5xx still proves the host is
    /// reachable. Drives the per-source online indicator; a source is only
    /// considered offline after several transport failures in a row.
    @Published public var consecutiveTransportFailures: Int = 0

    // MARK: - Issues

    /// Sets the user-facing issue message and its classification together.
    /// Nonisolated (like the rest of `Provider`) so providers can call it from
    /// their own worker contexts; the `@Published` update is carried to the
    /// main actor by Combine.
    func setIssue(_ message: String?, kind: ProviderIssueKind) {
        if let message {
            providerIssue = message
            issueKind = kind
        } else {
            providerIssue = nil
            issueKind = .none
        }
    }

    /// Clears any current issue.
    func clearIssue() {
        setIssue(nil, kind: .none)
    }

    /// Backwards-compatible setter for call sites that only know the message.
    /// Classifies the issue as `.transient` (the safe default for network,
    /// server, rate-limit, and decoding problems). Use `setIssue(_:kind:)`
    /// when the failure is a credential, configuration, no-data, or API-change
    /// problem so the UI can present it appropriately.
    func setProviderIssue(_ value: String?) {
        setIssue(value, kind: value == nil ? .none : .transient)
    }

    /// Call when a request yielded any HTTP response (any status code).
    func noteResponseReceived() {
        if consecutiveTransportFailures != 0 {
            consecutiveTransportFailures = 0
        }
    }

    /// Call when a request failed below the HTTP layer (timeout, refused, DNS,
    /// or a response that was not HTTP).
    func noteTransportFailure() {
        consecutiveTransportFailures += 1
    }

    init() {
        if self.isBaseProvider {
            return
        }

        startTimer()
    }

    var GlucoseEntries: [GlucoseEntry] {
        _glucoseEntries
    }

    func setGlucoseEntries(_ entries: [GlucoseEntry]) {
        _glucoseEntries = entries
    }

    func getSafeGlucoseEntries() -> [GlucoseEntry] {
        return _glucoseEntries
    }

    internal func startTimer() {
        let _ = Timer.publish(every: readingInterval, on: .main, in: .default)
    }

    /// Verifies the provider's credentials. Returning `false` should leave a
    /// classified `providerIssue`/`issueKind` behind; callers fall back to
    /// `.transient` when a provider forgets to set one.
    func verifyCredentials() async -> Bool {
        return true
    }

    func getCurrent() -> GlucoseEntry {
        let entries = getSafeGlucoseEntries()
        return entries.count > 0 ? entries[0] : GlucoseEntry(glucose: 1, date: Date(), changeRate: 0.0)
    }

    func getData(completion: @escaping ([GlucoseEntry]) -> Void) {
        completion(getSafeGlucoseEntries())
    }

    func isAuthValid() -> Bool {
        return false
    }

    @MainActor
    internal func fetch() async {
        self.logger.dlog("Base fetch function called. This should not happen. Occurrences of this message means that your CGM provider implementation does not have it's own `fetch` implementation, or that no provider is configured.", category: "provider", level: .error)
        // Should be implemented in the discrete providers
    }
}
