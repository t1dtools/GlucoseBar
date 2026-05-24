//
//  UpdateChecker.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2026-05-24.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "UpdateChecker")

enum DistributionChannel {
    case appStore
    case testFlight
    case direct

    static func detect() -> DistributionChannel {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return .direct
        }
        guard FileManager.default.fileExists(atPath: receiptURL.path) else {
            return .direct
        }
        return receiptURL.path.contains("sandboxReceipts") ? .testFlight : .appStore
    }
}

enum UpdateStatus: Equatable {
    case unknown
    case checking
    case upToDate
    case outdated(latestVersion: String)
    case error(message: String)
}

@MainActor
class UpdateChecker: ObservableObject {
    @Published var status: UpdateStatus = .unknown
    @Published var channel: DistributionChannel = .direct

    private let lastCheckKey = "UpdateChecker.lastCheckDate"
    private let checkInterval: TimeInterval = 60 * 60 * 24 // 24 hours

    init() {
        channel = DistributionChannel.detect()
        logger.info("Distribution channel: \(self.channel == .appStore ? "App Store" : "Direct")")
    }

    /// Checks for updates if 24 hours have elapsed since the last check.
    func checkIfNeeded() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FAKE_APP_VERSION"] != nil {
            await check()
            return
        }
        #endif
        let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastCheck) >= checkInterval else {
            logger.debug("Skipping update check — last checked \(lastCheck)")
            return
        }
        await check()
    }

    /// Forces an immediate update check regardless of last check time.
    func check() async {
        guard channel != .testFlight else {
            logger.info("TestFlight build — skipping update check")
            status = .upToDate
            return
        }
        status = .checking
        do {
            let latest = try await fetchLatestVersion()
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            #if DEBUG
            let current = ProcessInfo.processInfo.environment["FAKE_APP_VERSION"] ?? Bundle.main.appVersionLong
            #else
            let current = Bundle.main.appVersionLong
            #endif
            if isNewer(latest, than: current) {
                status = .outdated(latestVersion: latest)
                logger.info("Update available: \(latest) (current: \(current))")
            } else {
                status = .upToDate
                logger.info("Up to date: \(current)")
            }
        } catch {
            status = .error(message: error.localizedDescription)
            logger.error("Update check failed: \(error.localizedDescription)")
        }
    }

    var isOutdated: Bool {
        if case .outdated = status { return true }
        return false
    }

    var downloadURL: URL {
        switch channel {
        case .appStore, .testFlight:
            return URL(string: "https://apps.apple.com/app/glucosebar/id6468110131")!
        case .direct:
            return URL(string: "https://github.com/t1dtools/GlucoseBar/releases/latest")!
        }
    }

    // MARK: - Private

    private func fetchLatestVersion() async throws -> String {
        switch channel {
        case .appStore, .testFlight:
            return try await fetchAppStoreVersion()
        case .direct:
            return try await fetchGitHubVersion()
        }
    }

    private func fetchGitHubVersion() async throws -> String {
        let url = URL(string: "https://api.github.com/repos/t1dtools/GlucoseBar/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONDecoder().decode(GitHubRelease.self, from: data)
        // Strip leading "v" prefix if present (e.g. "v1.4.0" → "1.4.0")
        return json.tagName.hasPrefix("v") ? String(json.tagName.dropFirst()) : json.tagName
    }

    private func fetchAppStoreVersion() async throws -> String {
        let url = URL(string: "https://itunes.apple.com/lookup?id=6468110131&country=us")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONDecoder().decode(AppStoreLookup.self, from: data)
        guard let result = json.results.first else {
            throw UpdateError.noVersionFound
        }
        return result.version
    }

    /// Returns true if `candidate` is a higher semantic version than `current`.
    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let c = parseVersion(candidate)
        let v = parseVersion(current)
        return c.lexicographicallyPrecedes(v) == false && c != v
    }

    private func parseVersion(_ string: String) -> [Int] {
        string.split(separator: ".").map { Int($0) ?? 0 }
    }
}

// MARK: - Decodable helpers

private struct GitHubRelease: Decodable {
    let tagName: String
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}

private struct AppStoreLookup: Decodable {
    let results: [AppStoreResult]
}

private struct AppStoreResult: Decodable {
    let version: String
}

private enum UpdateError: LocalizedError {
    case noVersionFound
    var errorDescription: String? {
        switch self {
        case .noVersionFound: return "No version information found."
        }
    }
}
