//
//  UpdateChecker.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2026-05-24.
//

import Foundation
import OSLog
import Combine

private let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "UpdateChecker")

enum DistributionChannel {
    case appStore
    case testFlight
    case direct

    static func detect() -> DistributionChannel {
        let bundlePath = Bundle.main.bundlePath

        // Check for TestFlight via extended attribute metadata
        let attrName = "com.apple.appstore.metadata"
        let bufSize = getxattr(bundlePath, attrName, nil, 0, 0, 0)
        if bufSize > 0 {
            var buffer = [UInt8](repeating: 0, count: bufSize)
            if getxattr(bundlePath, attrName, &buffer, bufSize, 0, 0) > 0 {
                let data = Data(buffer)
                if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let metadata = plist["iTunesMetadata"] as? [String: Any],
                   metadata["betaExternalVersionIdentifier"] != nil {
                    return .testFlight
                }
            }
        }

        // Fall back to receipt-based App Store vs direct detection
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: receiptURL.path) else {
            return .direct
        }
        return .appStore
    }

    var displayName: String {
        switch self {
        case .appStore: return "App Store"
        case .testFlight: return "TestFlight"
        case .direct: return "Direct"
        }
    }
}

enum UpdateStatus: Equatable {
    case unknown
    case checking
    case upToDate
    case outdated(latestVersion: String, latestBuild: Int)
    case error(message: String)
}

@MainActor
class UpdateChecker: ObservableObject {
    @Published var status: UpdateStatus = .unknown
    @Published var channel: DistributionChannel = .direct
    @Published var downloadURL: URL = URL(string: "https://github.com/t1dtools/GlucoseBar/releases/latest")!

    private let lastCheckKey = "UpdateChecker.lastCheckDate"
    private let checkInterval: TimeInterval = 60 * 60 * 24 // 24 hours
    private let timerInterval: TimeInterval = 60 * 60      // check every hour (throttle still applies)
    private let manifestURL = URL(string: "https://glucosebar.t1d.tools/version.json")!
    private var timerCancellable: AnyCancellable?

    init() {
        channel = DistributionChannel.detect()
        logger.info("Distribution channel: \(self.channel.displayName)")
        startTimer()
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: timerInterval, tolerance: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.checkIfNeeded() }
            }
    }

    func checkIfNeeded() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FAKE_APP_BUILD"] != nil {
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
        status = .checking
        do {
            let entry = try await fetchManifest()
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            #if DEBUG
            let currentBuild = Int(ProcessInfo.processInfo.environment["FAKE_APP_BUILD"] ?? "") ?? Bundle.main.appBuild
            #else
            let currentBuild = Bundle.main.appBuild
            #endif

            if entry.build > currentBuild {
                if let url = URL(string: entry.downloadURL) {
                    downloadURL = url
                }
                status = .outdated(latestVersion: entry.version, latestBuild: entry.build)
                logger.info("Update available: \(entry.version) build \(entry.build) (current build: \(currentBuild))")
            } else {
                status = .upToDate
                logger.info("Up to date: build \(currentBuild)")
            }
        } catch {
            // Silently do nothing on failure
            status = .unknown
            logger.error("Update check failed: \(error.localizedDescription)")
        }
    }

    var isOutdated: Bool {
        if case .outdated = status { return true }
        return false
    }

    // MARK: - Private

    private func fetchManifest() async throws -> VersionManifestEntry {
        let (data, _) = try await URLSession.appDefault.data(from: manifestURL)
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: data)
        switch channel {
        case .appStore:   return manifest.appStore
        case .testFlight: return manifest.testFlight
        case .direct:     return manifest.direct
        }
    }
}

// MARK: - Decodable helpers

private struct VersionManifestEntry: Decodable {
    let version: String
    let build: Int
    let downloadURL: String
}

private struct VersionManifest: Decodable {
    let appStore: VersionManifestEntry
    let testFlight: VersionManifestEntry
    let direct: VersionManifestEntry
}
