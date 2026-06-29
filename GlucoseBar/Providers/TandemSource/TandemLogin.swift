//
//  TandemLogin.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-26.
//

import Foundation
import OSLog

enum TandemLoginError: Error, LocalizedError {
    case invalidCredentials
    case missingCookies
    case parseError(String)
    case rateLimited
    case httpError(Int)
    case noAccessToken

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid Tandem Source credentials"
        case .missingCookies:
            return "Unable to retrieve session cookies"
        case .parseError(let detail):
            return "Error parsing Tandem login page: \(detail)"
        case .rateLimited:
            return "Tandem login is rate-limited. Please try again later."
        case .httpError(let status):
            return "Tandem login HTTP error: \(status)"
        case .noAccessToken:
            return "Unable to obtain access token from Tandem"
        }
    }
}

struct TandemLoginSession {
    let userGuid: String
    let accessToken: String
    let accessTokenExpiresAt: Date
    let loginCookies: [HTTPCookie]

    var isExpired: Bool {
        accessTokenExpiresAt.timeIntervalSinceNow <= 300
    }
}

final class TandemLoginHelper {

    private let loginURL = URL(string: "https://tconnect.tandemdiabetes.com/login.aspx?ReturnUrl=%2f")!
    private let baseURL = URL(string: "https://tdcservices.tandemdiabetes.com")!
    private let oauthTokenPath = "cloud/oauth2/token"
    private let oauthScopes = "cloud.account cloud.upload cloud.accepttcpp cloud.email cloud.password"

    private let clientId = "C2331CD6-D450-495E-9C19-67215230C85D"
    private let clientSecret = "tz433KW5QDC9V7f!z6@^2o&Y6SGGYh"
    private let httpTimeout: Double = 120.0

    private let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "tandem-login")

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = httpTimeout
        config.timeoutIntervalForResource = httpTimeout
        config.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: config)
    }

    func login(email: String, password: String) async throws -> TandemLoginSession {
        logger.debug("TandemLoginHelper.login: starting")

        let (loginCookies, userGuid) = try await formsLogin(email: email, password: password)
        logger.debug("TandemLoginHelper.login: forms login success, userGuid=\(userGuid)")

        let (accessToken, accessTokenExpiresAt) = try await oauthLogin(email: email, password: password)
        logger.debug("TandemLoginHelper.login: oauth success, expires=\(accessTokenExpiresAt)")

        return TandemLoginSession(
            userGuid: userGuid,
            accessToken: accessToken,
            accessTokenExpiresAt: accessTokenExpiresAt,
            loginCookies: loginCookies
        )
    }

    // MARK: - Forms Login

    private func formsLogin(email: String, password: String) async throws -> ([HTTPCookie], String) {
        var request = URLRequest(url: loginURL)
        request.httpMethod = "GET"
        request.setValue(randomUserAgent(), forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TandemLoginError.parseError("No HTTP response")
        }

        if httpResponse.statusCode == 200 {
            if let body = String(data: data, encoding: .utf8),
               body.contains("Web Page Blocked!") || body.contains("Attack ID:") {
                throw TandemLoginError.rateLimited
            }
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw TandemLoginError.parseError("Unable to read login page")
        }

        guard let viewState = extractHiddenField(named: "__VIEWSTATE", from: html),
              let viewStateGenerator = extractHiddenField(named: "__VIEWSTATEGENERATOR", from: html),
              let eventValidation = extractHiddenField(named: "__EVENTVALIDATION", from: html) else {
            throw TandemLoginError.parseError("Missing ASP.NET form fields")
        }

        let postBody = buildLoginBody(
            email: email,
            password: password,
            viewState: viewState,
            viewStateGenerator: viewStateGenerator,
            eventValidation: eventValidation
        )

        var postRequest = URLRequest(url: loginURL)
        postRequest.httpMethod = "POST"
        postRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        postRequest.setValue(randomUserAgent(), forHTTPHeaderField: "User-Agent")
        postRequest.setValue(loginURL.absoluteString, forHTTPHeaderField: "Referer")
        postRequest.httpBody = postBody.data(using: .utf8)
        postRequest.cachePolicy = .reloadIgnoringLocalCacheData

        let (postData, postResponse) = try await session.data(for: postRequest)

        guard let postHTTPResponse = postResponse as? HTTPURLResponse else {
            throw TandemLoginError.parseError("No HTTP response from login POST")
        }

        // HTTP 200 with .notice_error means bad credentials
        if postHTTPResponse.statusCode == 200 {
            if let body = String(data: postData, encoding: .utf8),
               let errorStart = body.range(of: "notice_error"),
               let closeSpan = body[errorStart.upperBound...].range(of: "</span>") {
                let errorStartIdx = body[errorStart.upperBound...].range(of: ">")
                let startIdx = errorStartIdx?.upperBound ?? errorStart.upperBound
                let errorText = String(body[startIdx..<closeSpan.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                throw TandemLoginError.parseError(errorText.isEmpty ? "Check your login credentials." : errorText)
            }
            // Might be a redirect in body
            if let body = String(data: postData, encoding: .utf8), !body.contains("LoginControl") {
                // Login succeeded but we got a 200 (unusual but handled)
            } else {
                throw TandemLoginError.invalidCredentials
            }
        }

        if postHTTPResponse.statusCode != 302 && postHTTPResponse.statusCode != 200 {
            throw TandemLoginError.httpError(postHTTPResponse.statusCode)
        }

        guard let fields = postHTTPResponse.allHeaderFields as? [String: String] else {
            throw TandemLoginError.parseError("No response headers from login")
        }

        let url = postHTTPResponse.url ?? loginURL

        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)

        guard let userGuidCookie = cookies.first(where: { $0.name == "UserGUID" }) else {
            throw TandemLoginError.missingCookies
        }

        // Follow redirect if HTTP 302
        if postHTTPResponse.statusCode == 302,
           let location = fields["Location"] {
            var followURL = URL(string: location, relativeTo: url) ?? url
            if location.starts(with: "/") {
                followURL = URL(string: "https://tconnect.tandemdiabetes.com\(location)")!
            }

            var followRequest = URLRequest(url: followURL)
            followRequest.httpMethod = "POST"
            followRequest.setValue(randomUserAgent(), forHTTPHeaderField: "User-Agent")
            followRequest.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: cookies)

            let _ = try? await session.data(for: followRequest)
        }

        return (cookies, userGuidCookie.value)
    }

    // MARK: - OAuth2 Login

    private func oauthLogin(email: String, password: String) async throws -> (String, Date) {
        let tokenURL = baseURL.appendingPathComponent(oauthTokenPath)

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Dalvik/2.1.0 (Linux; U; Android 12; Pixel 4a Build/SP2A.220305.012)", forHTTPHeaderField: "User-Agent")

        let authString = "\(clientId):\(clientSecret)"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")

        let params: [String: String] = [
            "username": email,
            "password": password,
            "grant_type": "password",
            "scope": oauthScopes
        ]

        let bodyString = params.map { "\($0.key)=\(percentEncode($0.value))" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.appDefault.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TandemLoginError.noAccessToken
        }

        if httpResponse.statusCode != 200 {
            throw TandemLoginError.httpError(httpResponse.statusCode)
        }

        let authResponse = try JSONDecoder().decode(TandemOAuthResponse.self, from: data)

        guard let token = authResponse.accessToken.nilIfEmpty else {
            throw TandemLoginError.noAccessToken
        }

        let expiry = parseISO8601(authResponse.accessTokenExpiresAt) ?? Date().addingTimeInterval(3600)

        return (token, expiry)
    }

    // MARK: - Helpers

    private func percentEncode(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private func extractHiddenField(named name: String, from html: String) -> String? {
        let patterns: [String] = [
            "id=\"\(name)\"[^>]*value=\"([^\"]+)\"",
            "id=\(name)\\s[^>]*value=\"([^\"]+)\"",
            "name=\"\(name)\"[^>]*value=\"([^\"]+)\""
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = regex.firstMatch(in: html, options: [], range: range),
               let valueRange = Range(match.range(at: 1), in: html) {
                return String(html[valueRange])
            }
        }

        return nil
    }

    private func buildLoginBody(email: String, password: String,
                                 viewState: String, viewStateGenerator: String,
                                 eventValidation: String) -> String {
        let fields: [(String, String)] = [
            ("__LASTFOCUS", ""),
            ("__EVENTTARGET", "ctl00$ContentBody$LoginControl$linkLogin"),
            ("__EVENTARGUMENT", ""),
            ("__VIEWSTATE", percentEncode(viewState)),
            ("__VIEWSTATEGENERATOR", percentEncode(viewStateGenerator)),
            ("__EVENTVALIDATION", percentEncode(eventValidation)),
            ("ctl00$ContentBody$LoginControl$txtLoginEmailAddress", percentEncode(email)),
            ("ctl00$ContentBody$LoginControl$txtLoginPassword", percentEncode(password)),
        ]

        return fields.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    private func parseISO8601(_ dateString: String?) -> Date? {
        guard let dateString = dateString?.nilIfEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString)
    }

    private func randomUserAgent() -> String {
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
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
