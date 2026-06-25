//
//  LibreLinkUp.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-12-01.
//

import Foundation
import SwiftUI

public enum LibreServer: String, CaseIterable, Identifiable, Codable {
    case eu
    case eu2
    case ae
    case ap
    case au
    case de
    case fr
    case jp
    case us

    public var id: String { self.rawValue }

    public var url: String {
        return "https://api-\(region).libreview.io/llu"
    }

    public var region: String {
        switch self {
        case .eu:  return "eu"
        case .eu2: return "eu2"
        case .ae:  return "ae"
        case .ap:  return "ap"
        case .au:  return "au"
        case .de:  return "de"
        case .fr:  return "fr"
        case .jp:  return "jp"
        case .us:  return "us"
        }
    }

    public var presentable: String {
        switch self {
        case .eu:  return "Europe"
        case .eu2: return "United Kingdom"
        case .ae:  return "United Arab Emirates"
        case .ap:  return "Asia Pacific"
        case .au:  return "Australia"
        case .de:  return "Germany"
        case .fr:  return "France"
        case .jp:  return "Japan"
        case .us:  return "United States"
        }
    }
}

class LibreLinkUp: Provider, @unchecked Sendable {

    private let httpTimeout = 30.0

    var username: String
    var password: String
    var serverURL: String
    var lluVersion: String = "4.7.0"

    @Published var patientConnections: [LibreLinkUpConnectionsResponse] = []
    @Published var isAuthenticated: Bool = false

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d/yyyy h:mm:ss a"
        return formatter
    }()

    private lazy var isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let requestHeaders: [String: String]

    init(username: String, password: String, server: LibreServer = .eu, connectionID: String = "") {
        self.username = username
        self.password = password
        self.serverURL = server.url
        self.requestHeaders = [
            "User-Agent": "Mozilla/5.0",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "product": "llu.ios",
            "version": lluVersion,
        ]

        super.init()
        self.type = .librelinkup
        self.isBaseProvider = false
        self.connectionID = connectionID
    }

    // MARK: - Timestamp parsing

    private func parseTimestamp(_ string: String) -> Date? {
        if let date = dateFormatter.date(from: string) {
            return date
        }
        if let date = isoDateFormatter.date(from: string) {
            return date
        }
        return nil
    }

    // MARK: - Response models

    struct LibreLinkUpResponse<T: Codable>: Codable {
        let status: Int
        let data: T?
    }

    struct LibreLinkUpAuthResponse: Codable {
        let user: LibreLinkUpUser?
        let authTicket: LibreLinkUpAuthTicket?
        let data: LibreLinkUpData?
        let redirect: Bool?
        let region: String?
    }

    struct LibreLinkUpConnectionsResponse: Codable, Hashable {
        enum CodingKeys: String, CodingKey {
            case patientID = "patientId"
            case country = "country"
            case firstName = "firstName"
            case lastName = "lastName"
        }

        let patientID: String
        let country: String
        let firstName: String
        let lastName: String
    }

    struct LibreLinkUpUser: Codable {
        let id: String?
        let country: String
    }

    struct LibreLinkUpAuthTicket: Codable {
        let token: String
        let expires: Int64
    }

    struct LibreLinkUpData: Codable {
        let minimumVersion: String?
    }

    struct LibreLinkUpAuthRequest: Codable {
        let email: String
        let password: String
    }

    private struct LibreLinkResponse<T: Codable>: Codable {
        let status: Int
        let data: T?
    }

    private struct LibreLinkResponseFetch: Codable {
        let connection: LibreLinkResponseConnection?
        let graphData: [LibreLinkResponseGlucose]?
    }

    private struct LibreLinkResponseGlucose: Codable {
        enum CodingKeys: String, CodingKey {
            case timestamp = "Timestamp"
            case value = "ValueInMgPerDl"
            case trend = "TrendArrow"
        }

        let timestamp: String
        let value: Double
        let trend: Int?
    }

    private struct LibreLinkResponseConnection: Codable {
        let glucoseMeasurement: LibreLinkResponseGlucose?
    }

    // MARK: - Fetch

    override internal func fetch() async {
        plog("LibreLinkUp.fetch", category: "librelinkup", level: .debug)

        if username.isEmpty || password.isEmpty {
            self.providerIssue = "LibreLinkUp credentials not configured."
            return
        }

        if !isAuthValid() {
            plog("Auth invalid, authenticating", category: "librelinkup", level: .debug)
            let success = await authenticate()
            if !success {
                self.providerIssue = "Unable to authenticate with LibreLinkUp. Please check your credentials and region."
                return
            }
        }

        guard isAuthValid() else {
            self.providerIssue = "LibreLinkUp authentication failed."
            return
        }

        if connectionID.isEmpty {
            plog("No connectionID set, fetching connections", category: "librelinkup", level: .debug)
            await getConnections()
            if connectionID.isEmpty {
                self.providerIssue = "No LibreLinkUp connections found. Ensure you are following at least one FreeStyle Libre user."
                return
            }
        }

        self.providerIssue = nil
        lastFetch = Date()

        let path = "/connections/\(connectionID)/graph"
        guard let req = createRequest(path: path, method: "GET") else {
            self.providerIssue = "Invalid LibreLinkUp server URL."
            return
        }
        var request = req
        if let token = auth?.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.appDefault.data(for: request)
            let res = response as! HTTPURLResponse

            if res.statusCode == 401 {
                plog("Token expired during fetch, re-authenticating", category: "librelinkup", level: .info)
                auth = nil
                let success = await authenticate()
                if success {
                    await self.fetch()
                }
                return
            }

            if res.statusCode > 499 {
                self.providerIssue = "LibreLinkUp server error (HTTP \(res.statusCode))."
                return
            }

            let result = try JSONDecoder().decode(LibreLinkResponse<LibreLinkResponseFetch>.self, from: data)

            guard let fetchedData = result.data else {
                plog("No data in fetch response", category: "librelinkup", level: .error)
                return
            }

            var graphData: [LibreLinkResponseGlucose] = []

            var forceFull = false
            if lastFetch.timeIntervalSinceNow < -400 {
                plog("last fetch was more than 400 seconds ago, doing a full refresh", category: "librelinkup", level: .info)
                forceFull = true
            }

            let existingEntries = getSafeGlucoseEntries()
            if existingEntries.isEmpty || forceFull {
                if let gd = fetchedData.graphData {
                    graphData.append(contentsOf: gd)
                }
            }

            if let measurement = fetchedData.connection?.glucoseMeasurement {
                graphData.append(measurement)
            }

            var mapped = libreToGlucoseEntries(input: graphData)
            mapped.sort(by: { $0.date.compare($1.date) == .orderedDescending })

            var allEntries = getSafeGlucoseEntries()
            for newEntry in mapped {
                if !allEntries.contains(where: { $0.date == newEntry.date && $0.glucose == newEntry.glucose }) {
                    allEntries.append(newEntry)
                }
            }
            allEntries.sort(by: { $0.date.compare($1.date) == .orderedDescending })

            while allEntries.count > 288 {
                allEntries.removeLast()
            }

            setGlucoseEntries(allEntries)
        } catch let urlError as URLError where urlError.code == .timedOut {
            plog("fetch timed out: \(urlError.localizedDescription)", category: "librelinkup", level: .error)
            self.providerIssue = "LibreLinkUp request timed out."
        } catch {
            plog("fetch error: \(error.localizedDescription)", category: "librelinkup", level: .error)
            self.providerIssue = "Failed to fetch LibreLinkUp glucose data."
        }
    }

    // MARK: - Connections

    private func getConnections() async {
        plog("LibreLinkUp.getConnections", category: "librelinkup", level: .debug)

        let path = "/connections"
        guard let req = createRequest(path: path, method: "GET") else { return }
        var request = req
        if let token = auth?.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.appDefault.data(for: request)
            let res = response as! HTTPURLResponse

            if res.statusCode == 401 {
                plog("Token expired, re-authenticating", category: "librelinkup", level: .info)
                auth = nil
                let success = await authenticate()
                if success {
                    await getConnections()
                }
                return
            }

            if res.statusCode > 499 {
                return
            }

            let result = try JSONDecoder().decode(LibreLinkUpResponse<[LibreLinkUpConnectionsResponse]>.self, from: data)

            switch result.status {
            case 0:
                if let connections = result.data, !connections.isEmpty {
                    patientConnections = connections
                    connectionID = connections.first!.patientID
                    plog("Got \(connections.count) connection(s)", category: "librelinkup", level: .info)
                }
            case 920:
                plog("Version too low, bumping", category: "librelinkup", level: .info)
            default:
                plog("Unexpected status from connections: \(result.status)", category: "librelinkup", level: .debug)
            }
        } catch {
            plog("getConnections error: \(error.localizedDescription)", category: "librelinkup", level: .error)
        }
    }

    // MARK: - Authentication

    private func authenticate() async -> Bool {
        plog("LibreLinkUp.authenticate", category: "librelinkup", level: .debug)

        isAuthenticating = true
        defer { isAuthenticating = false }

        let path = "/auth/login"
        let requestBody = LibreLinkUpAuthRequest(email: username, password: password)

        guard let req = createRequest(path: path, method: "POST") else {
            plog("Invalid server URL for auth", category: "librelinkup", level: .error)
            return false
        }
        var request = req

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            plog("Failed encoding auth request", category: "librelinkup", level: .error)
            return false
        }

        do {
            let (data, response) = try await URLSession.appDefault.data(for: request)
            let res = response as! HTTPURLResponse

            if res.statusCode > 499 {
                plog("Server error during auth: \(res.statusCode)", category: "librelinkup", level: .error)
                return false
            }

            let result = try JSONDecoder().decode(LibreLinkUpResponse<LibreLinkUpAuthResponse>.self, from: data)

            switch result.status {
            case 0:
                if let redirect = result.data?.redirect, redirect == true, let region = result.data?.region, !region.isEmpty {
                    plog("Following redirect to region \(region)", category: "librelinkup", level: .info)
                    let oldServer = serverURL
                    serverURL = "https://api-\(region.lowercased()).libreview.io/llu"
                    if serverURL != oldServer {
                        plog("Server changed from \(oldServer) to \(serverURL)", category: "librelinkup", level: .info)
                    }
                    return await authenticate()
                }

                guard let ticket = result.data?.authTicket, !ticket.token.isEmpty else {
                    plog("Auth response missing token", category: "librelinkup", level: .error)
                    return false
                }

                auth = ProviderAuth(token: ticket.token, expiry: Double(ticket.expires))
                isAuthenticated = true
                plog("Authentication successful", category: "librelinkup", level: .info)

                await getConnections()
                return true

            case 2:
                plog("Bad credentials", category: "librelinkup", level: .info)
                self.providerIssue = "Invalid LibreLinkUp credentials."
                return false

            case 4:
                plog("Terms of Use need accepting", category: "librelinkup", level: .info)
                self.providerIssue = "LibreLinkUp terms of use must be accepted. Please log in via the LibreLinkUp app first."
                return false

            case 920:
                if let minVersion = result.data?.data?.minimumVersion {
                    lluVersion = minVersion
                    plog("Bumping version to \(minVersion)", category: "librelinkup", level: .info)
                    return await authenticate()
                }
                return false

            default:
                plog("Unexpected auth status: \(result.status)", category: "librelinkup", level: .debug)
                return false
            }
        } catch let urlError as URLError where urlError.code == .timedOut {
            plog("Auth timed out", category: "librelinkup", level: .error)
            return false
        } catch {
            plog("Auth error: \(error.localizedDescription)", category: "librelinkup", level: .error)
            return false
        }
    }

    // MARK: - Credential verification

    func login() async -> Bool {
        return await authenticate()
    }

    override internal func verifyCredentials() async -> Bool {
        plog("librelinkup.verifyCredentials", category: "librelinkup", level: .debug)

        return await authenticate()
    }

    // MARK: - Auth validity

    override public func isAuthValid() -> Bool {
        guard let auth = auth, !auth.token.isEmpty else {
            return false
        }

        let expiryTime = Date(timeIntervalSince1970: auth.expiry)
        return expiryTime.timeIntervalSinceNow > 0
    }

    // MARK: - Trend mapping

    private enum LLUTrendMap: Int, CaseIterable {
        case notComputable = 0
        case downDown = 1
        case down = 2
        case flat = 3
        case up = 4
        case upUp = 5

        init?(_ trendArrow: Int) {
            self.init(rawValue: trendArrow)
        }

        var glucoseTrend: GlucoseEntry.GlucoseTrend {
            switch self {
            case .downDown:       return GlucoseEntry.GlucoseTrend.downDown
            case .down:           return GlucoseEntry.GlucoseTrend.down
            case .flat:           return GlucoseEntry.GlucoseTrend.flat
            case .up:             return GlucoseEntry.GlucoseTrend.up
            case .upUp:           return GlucoseEntry.GlucoseTrend.upUp
            case .notComputable:  return GlucoseEntry.GlucoseTrend.notComputable
            }
        }
    }

    // MARK: - Entry conversion

    private func libreToGlucoseEntries(input: [LibreLinkResponseGlucose]) -> [GlucoseEntry] {
        var entries: [GlucoseEntry] = []

        for llu in input {
            guard let date = parseTimestamp(llu.timestamp) else {
                plog("Could not parse timestamp: \(llu.timestamp)", category: "librelinkup", level: .error)
                continue
            }

            let trend: GlucoseEntry.GlucoseTrend = {
                if let raw = llu.trend, let mapped = LLUTrendMap(raw) {
                    return mapped.glucoseTrend
                }
                return .notComputable
            }()

            let entry = GlucoseEntry(
                glucose: llu.value,
                date: date,
                trend: trend,
                changeRate: nil
            )
            entries.append(entry)
        }

        return entries
    }

    // MARK: - Request builder

    private func createRequest(path: String, method: String) -> URLRequest? {
        let urlString = "\(serverURL)\(path)"
        guard let url = URL(string: urlString) else {
            plog("Invalid URL: \(urlString)", category: "librelinkup", level: .error)
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: httpTimeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        for (header, value) in requestHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }

        request.httpMethod = method
        return request
    }
}

// MARK: - Errors

private enum LibreLinkError: Error {
    case unknownError
    case maintenance
    case invalidURL
    case serializationError
    case missingLoginSession
    case missingUserOrToken
    case missingPatientID
    case invalidCredentials
    case missingCredentials
    case notAuthenticated
    case decoderError
    case missingData
    case parsingError
    case cannotLock
    case missingStatusCode
}

extension LibreLinkError: CustomStringConvertible {
    var description: String {
        switch self {
        case .unknownError:        return "Unknown error"
        case .missingStatusCode:   return "Missing status code"
        case .maintenance:         return "Maintenance"
        case .invalidURL:          return "Invalid url"
        case .serializationError:  return "Serialization error"
        case .missingUserOrToken:  return "Missing user or token"
        case .missingLoginSession: return "Missing login session"
        case .missingPatientID:    return "Missing patient id"
        case .invalidCredentials:  return "Invalid credentials (check 'Settings' > 'Connection Settings')"
        case .missingCredentials:  return "Missing credentials (check 'Settings' > 'Connection Settings')"
        case .notAuthenticated:    return "Not authenticated"
        case .decoderError:        return "Decoder error"
        case .missingData:         return "Missing data"
        case .parsingError:        return "Parsing error"
        case .cannotLock:          return "Cannot lock"
        }
    }
}
