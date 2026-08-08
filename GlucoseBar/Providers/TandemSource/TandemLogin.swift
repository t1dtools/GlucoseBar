//
//  TandemLogin.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-26.
//

import Foundation
import OSLog
import CryptoKit

enum TandemLoginError: Error, LocalizedError {
    case invalidCredentials
    case parseError(String)
    case httpError(Int)
    case noAccessToken
    case noPumperId
    case noSessionCookies

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid Tandem Source credentials"
        case .parseError(let detail):
            return "Tandem login error: \(detail)"
        case .httpError(let status):
            return "Tandem login HTTP error: \(status)"
        case .noAccessToken:
            return "Unable to obtain access token from Tandem"
        case .noPumperId:
            return "Unable to find pump ID in Tandem account"
        case .noSessionCookies:
            return "Unable to establish session with Tandem"
        }
    }
}

public enum TandemRegion: String, CaseIterable, Identifiable {
    case us
    case eu

    public var id: String { self.rawValue }
    public var presentable: String {
        switch self {
        case .us: return "US"
        case .eu: return "EU"
        }
    }

    var loginPageURL: URL { URL(string: "https://sso.tandemdiabetes.com/")! }

    var loginAPIURL: URL {
        switch self {
        case .us: return URL(string: "https://tdcservices.tandemdiabetes.com/accounts/api/login")!
        case .eu: return URL(string: "https://tdcservices.eu.tandemdiabetes.com/accounts/api/login")!
        }
    }

    var authorizeURL: URL {
        switch self {
        case .us: return URL(string: "https://tdcservices.tandemdiabetes.com/accounts/api/connect/authorize")!
        case .eu: return URL(string: "https://tdcservices.eu.tandemdiabetes.com/accounts/api/connect/authorize")!
        }
    }

    var tokenURL: URL {
        switch self {
        case .us: return URL(string: "https://tdcservices.tandemdiabetes.com/accounts/api/connect/token")!
        case .eu: return URL(string: "https://tdcservices.eu.tandemdiabetes.com/accounts/api/connect/token")!
        }
    }

    var oidcClientID: String {
        switch self {
        case .us: return "0oa4wnbvtladeyVZX4h7"
        case .eu: return "1519e414-eeec-492e-8c5e-97bea4815a10"
        }
    }

    var redirectURI: String {
        switch self {
        case .us: return "https://sso.tandemdiabetes.com/auth/callback"
        case .eu: return "https://source.eu.tandemdiabetes.com/authorize/callback"
        }
    }

    var sourceURL: URL {
        switch self {
        case .us: return URL(string: "https://source.tandemdiabetes.com/")!
        case .eu: return URL(string: "https://source.eu.tandemdiabetes.com/")!
        }
    }
}

struct TandemLoginSession {
    let pumperId: String
    let accountId: String
    let accessToken: String
    let accessTokenExpiresAt: Date
    let region: TandemRegion

    var isExpired: Bool {
        accessTokenExpiresAt.timeIntervalSinceNow <= 300
    }
}

final class TandemLoginHelper: @unchecked Sendable {

    private let region: TandemRegion
    private let sourceIndex: Int
    private let httpTimeout: Double = 120.0

    private let session: URLSession
    private let apiSession: URLSession

    init(region: TandemRegion, sourceIndex: Int = -1) {
        self.region = region
        self.sourceIndex = sourceIndex

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = httpTimeout
        config.timeoutIntervalForResource = httpTimeout
        config.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: config)

        let apiConfig = URLSessionConfiguration.default
        apiConfig.timeoutIntervalForRequest = httpTimeout
        apiConfig.timeoutIntervalForResource = httpTimeout
        apiConfig.httpAdditionalHeaders = ["User-Agent": TandemLoginHelper.randomUserAgent()]
        apiSession = URLSession(configuration: apiConfig)
    }

    private func plog(_ message: String, level: OSLogType = .default) {
        let cat = sourceIndex < 0 ? "tandem-login" : "tandem-login/\(sourceIndex)"
        Logger(subsystem: "tools.t1d.GlucoseBar", category: cat)
            .dlog(message, category: "tandem-login", level: level)
    }

    func browserSession() -> URLSession { apiSession }
    func loginSession() -> URLSession { session }

    func login(email: String, password: String) async throws -> TandemLoginSession {
        plog("TandemLogin (\(self.region.presentable)): starting login")

        try await establishSession(email: email, password: password)

        plog("TandemLogin: session established, starting OIDC flow")

        let code = try await oidcAuthorize()

        let (accessToken, idToken, expiresIn) = try await oidcToken(code: code)

        let (pumperId, accountId) = try parseJWT(idToken)

        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        plog("TandemLogin: OIDC complete, pumperId=\(pumperId.prefix(8))..., token expires in \(expiresIn)s")

        return TandemLoginSession(
            pumperId: pumperId,
            accountId: accountId,
            accessToken: accessToken,
            accessTokenExpiresAt: expiresAt,
            region: region
        )
    }

    // MARK: - Session Establishment

    private func establishSession(email: String, password: String) async throws {
        plog("TandemLogin: GET \(self.region.loginPageURL.absoluteString)...")
        var initialReq = URLRequest(url: region.loginPageURL)
        initialReq.setValue(TandemLoginHelper.randomUserAgent(), forHTTPHeaderField: "User-Agent")
        initialReq.cachePolicy = .reloadIgnoringLocalCacheData

        let _ = try await session.data(for: initialReq)

        var loginReq = URLRequest(url: region.loginAPIURL)
        loginReq.httpMethod = "POST"
        loginReq.timeoutInterval = 30
        loginReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        loginReq.setValue(TandemLoginHelper.randomUserAgent(), forHTTPHeaderField: "User-Agent")
        loginReq.setValue(region.loginPageURL.absoluteString, forHTTPHeaderField: "Referer")

        let body: [String: String] = ["username": email, "password": password]
        loginReq.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: loginReq)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TandemLoginError.parseError("No HTTP response from login API")
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8)?.prefix(500) ?? ""
            plog("TandemLogin: login API returned HTTP \(httpResponse.statusCode), body: \(body)", level: .error)
            throw TandemLoginError.httpError(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String,
              status == "SUCCESS" else {
            let body = String(data: data, encoding: .utf8) ?? ""
            plog("TandemLogin: login API unexpected response: \(body)", level: .error)
            throw TandemLoginError.invalidCredentials
        }

        plog("TandemLogin: login API OK")
    }

    // MARK: - OIDC Authorization

    private func oidcAuthorize() async throws -> String {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(verifier)

        let params: [String: String] = [
            "client_id": region.oidcClientID,
            "response_type": "code",
            "scope": "openid profile email",
            "redirect_uri": region.redirectURI,
            "code_challenge": challenge,
            "code_challenge_method": "S256"
        ]

        var components = URLComponents(url: region.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        var authReq = URLRequest(url: components.url!)
        authReq.timeoutInterval = 30
        authReq.setValue(TandemLoginHelper.randomUserAgent(), forHTTPHeaderField: "User-Agent")
        authReq.setValue(region.loginPageURL.absoluteString, forHTTPHeaderField: "Referer")

        plog("TandemLogin: OIDC authorize request...")

        let (data, response) = try await session.data(for: authReq)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode / 100 == 2 else {
            let body = String(data: data, encoding: .utf8)?.prefix(500) ?? ""
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            plog("TandemLogin: OIDC authorize returned HTTP \(status), body: \(body)", level: .error)
            throw TandemLoginError.parseError("OIDC authorize failed")
        }

        guard let finalURL = httpResponse.url,
              let components = URLComponents(url: finalURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            plog("TandemLogin: no code in OIDC redirect URL: \(httpResponse.url?.absoluteString ?? "nil")", level: .error)
            throw TandemLoginError.parseError("No authorization code in OIDC response")
        }

        plog("TandemLogin: OIDC authorize OK, got code")
        self.codeVerifier = verifier
        return code
    }

    private var codeVerifier: String = ""

    // MARK: - OIDC Token Exchange

    private func oidcToken(code: String) async throws -> (String, String, Int) {
        let tokenParams: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": region.oidcClientID,
            "code": code,
            "redirect_uri": region.redirectURI,
            "code_verifier": codeVerifier
        ]

        let bodyString = tokenParams
            .map { "\($0.key)=\(percentEncode($0.value))" }
            .joined(separator: "&")

        var tokenReq = URLRequest(url: region.tokenURL)
        tokenReq.httpMethod = "POST"
        tokenReq.timeoutInterval = 30
        tokenReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenReq.setValue(TandemLoginHelper.randomUserAgent(), forHTTPHeaderField: "User-Agent")
        tokenReq.httpBody = bodyString.data(using: .utf8)

        plog("TandemLogin: OIDC token exchange...")
        let (data, response) = try await session.data(for: tokenReq)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode / 100 == 2 else {
            let body = String(data: data, encoding: .utf8)?.prefix(500) ?? ""
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            plog("TandemLogin: OIDC token returned HTTP \(status), body: \(body)", level: .error)
            throw TandemLoginError.parseError("OIDC token exchange failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let idToken = json["id_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            let body = String(data: data, encoding: .utf8) ?? ""
            plog("TandemLogin: OIDC token response missing fields: \(body)", level: .error)
            throw TandemLoginError.noAccessToken
        }

        plog("TandemLogin: OIDC token exchange OK")
        codeVerifier = ""
        return (accessToken, idToken, expiresIn)
    }

    // MARK: - JWT Parsing

    private func parseJWT(_ idToken: String) throws -> (String, String) {
        let segments = idToken.split(separator: ".")
        guard segments.count == 3 else {
            throw TandemLoginError.parseError("Invalid JWT format")
        }

        let payloadSegment = String(segments[1])
        let padded = payloadSegment.paddedBase64

        guard let payloadData = Data(base64Encoded: padded),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw TandemLoginError.parseError("Unable to decode JWT payload")
        }

        guard let pumperId = payload["pumperId"] as? String else {
            plog("TandemLogin: JWT missing pumperId. Claims: \(payload.keys.joined(separator: ", "))", level: .error)
            throw TandemLoginError.noPumperId
        }

        let accountId = payload["accountId"] as? String ?? ""
        plog("TandemLogin: JWT decoded, pumperId=\(pumperId.prefix(8))..., accountId=\(accountId.prefix(8))...")
        return (pumperId, accountId)
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        let bytes = (0..<64).map { _ in UInt8.random(in: 0...255) }
        let data = Data(bytes)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(_ verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    static func randomUserAgent() -> String {
        let agents = [
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.5005.115 Safari/537.36",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.5005.115 Safari/537.36",
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:101.0) Gecko/20100101 Firefox/101.0",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:102.0) Gecko/20100101 Firefox/102.0",
        ]
        return agents.randomElement() ?? agents[0]
    }
}

extension String {
    var paddedBase64: String {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return base64
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
