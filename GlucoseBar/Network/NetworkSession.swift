//
//  NetworkSession.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2026-05-31.
//

import Foundation

extension URLSession {
    static let appDefault: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": URLSession.buildUserAgent(),
            "Accept-Language": URLSession.buildAcceptLanguage()
        ]
        return URLSession(configuration: config)
    }()

    private static func buildAcceptLanguage() -> String {
        let langs = Locale.preferredLanguages
        let items = langs.prefix(10).enumerated().map { i, lang in
            if i == 0 { return lang }
            let q = max(0.1, 1.0 - Double(i) * 0.1)
            return "\(lang);q=\(String(format: "%.1f", q))"
        }
        return items.joined(separator: ", ")
    }

    private static func buildUserAgent() -> String {
        let version = Bundle.main.appVersionLong
        let build = Bundle.main.appBuild
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let distributionChannel = DistributionChannel.detect().displayName
        return "GlucoseBar/\(version) (\(build); macOS \(osString); \(distributionChannel); \(installID))"
    }

    private static var installID: String {
        let key = "GlucoseBar.installID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let new = (0..<8).map { _ in String(format: "%x", Int.random(in: 0..<16)) }.joined()
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
