//
//  LibreLinkUp.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-12-01.
//

import Foundation
import SwiftUI

public enum LibreServer: String, CaseIterable, Identifiable {
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
    public var region: String {
        switch self {
        case .eu:
            return "eu"
        case .eu2:
            return "eu2"
        case .ae:
            return "ae"
        case .ap:
            return "ap"
        case .au:
            return "au"
        case .de:
            return "de"
        case .fr:
            return "fr"
        case .jp:
            return "jp"
        case .us:
            return "us"
        }
    }

//    private extension LibreLinkResponseUser {
//        var apiRegion: String {
//            if ["ae", "ap", "au", "de", "eu", "fr", "jp", "us"].contains(country.lowercased()) {
//                return country.lowercased()
//            }
//
//            if country.lowercased() == "gb" {
//                return "eu2"
//            }
//
//            return "eu"
//        }
//    }

    public var url: String {
        return "https://api.libreview.io/llu"
    }
}

class LibreLinkUp: Provider {

    public var validSettings: Bool = true
    public var settingsError: String = ""

    private let httpTimeout = 30.0
    private var auth: LibreLinkUpAuthTicket?

    var username: String
    var password: String
    var server: String = "https://api.libreview.io/llu"
    var lluVersion: String = "4.7.0"
    var apiRegion: String = ""

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d/yyyy h:mm:ss a"
        return formatter
    }()

    private lazy var jsonDecoder: JSONDecoder? = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(dateFormatter)

        return decoder
    }()

    private func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        guard let jsonDecoder = jsonDecoder else {
            throw LibreLinkError.decoderError
        }

        return try jsonDecoder.decode(T.self, from: data)
    }

    private var requestHeaders = [
        "User-Agent": "Mozilla/5.0", // TODO: Emulate LLU app
        "Content-Type": "application/json",
        "Accept": "application/json",
        "product": "llu.ios",
    ]

    init(username: String, password: String) {
        if username.isEmpty {
            validSettings = false
            settingsError = "Username can not be empty"
        }

        if password.isEmpty {
            validSettings = false
            settingsError = "Password can not be empty"
        }

        self.username = username
        self.password = password

        // Add version header
        self.requestHeaders["version"] = lluVersion

        super.init()
        self.type = .librelinkup
    }

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
        let minimumVersion: String? // holds minimum version if current coded version is too old (status is 920)
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
        enum CodingKeys: String, CodingKey { case timestamp = "Timestamp"
            case value = "ValueInMgPerDl"
            case trend = "TrendArrow"
        }

        let timestamp: Date
        let value: Double
        let trend: Int?
    }

    private struct LibreLinkResponseConnection: Codable {
        let glucoseMeasurement: LibreLinkResponseGlucose?
    }

    override internal func fetch() async {
        logger.debug("LibreLinkUp.fetch")

        if !isAuthValid() {
            logger.debug("calling authenticate from fetch")
            if await authenticate() {
                await self.fetch()
            }
            return
        }

        if self.connectionID == "" {
            logger.debug("No connectionID set. Skipping!")
            self.lastFetch = Date()
            return
        }

        let path = "/connections/\(self.connectionID)/graph"
        var request = createRequest(path: path, method: "GET")
        request.setValue("Bearer \(self.auth!.token)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                self.logger.error("fetch error: \(String(describing: error))")
                return
            }

            let res = response as! HTTPURLResponse
            if res.statusCode > 499 {
                // TODO: handle error
                return
            }

            do {
                let result = try self.decode(LibreLinkResponse<LibreLinkResponseFetch>.self, data: data)

                var previous: GlucoseEntry? = nil
                var graphData: [LibreLinkResponseGlucose] = []

                var forceFull = false
                if self.lastFetch.timeIntervalSinceNow < -400 {
                    self.logger.info("last fetch was more than 400 seconds ago, do a full refresh")

                    forceFull = true
                }

                if self.GlucoseEntries.count > 0 {
                    previous = self.GlucoseEntries[0]
                }

                if self.GlucoseEntries.count == 0 || forceFull {
                    graphData.append(contentsOf: result.data!.graphData!)
                }

                graphData.append(result.data!.connection!.glucoseMeasurement!)

                var mappedGlucoseEntries = self.LibreLinkUpToGlucoseEntries(input: graphData, previous: previous)

                mappedGlucoseEntries.sort(by: { $0.date.compare($1.date) == .orderedDescending })

                self.GlucoseEntries.insert(contentsOf: mappedGlucoseEntries, at: 0)

                if (-1 * self.GlucoseEntries.last!.date.timeIntervalSinceNow / 60 / 60) > 12 {
                    self.GlucoseEntries.removeLast()
                }

                self.lastFetch = Date()
            } catch {
                self.logger.error("failed decoding graph data: \(String(describing: error))")
                return
            }
        }

        task.resume()
    }

    private enum LLUTrendMap: Int, CaseIterable {
        case downDown = 1
        case down = 2
        case flat = 3
        case up = 4
        case upUp = 5
        case notComputable = 0

        init?(_ trendArrow: Int) {
            for trend in LLUTrendMap.allCases {
                if trendArrow == trend.rawValue {
                    self = trend
                    return
                }
            }
            return nil
        }

        public var glucoseTrend: GlucoseEntry.GlucoseTrend {
            switch self {
            case .downDown:
                return GlucoseEntry.GlucoseTrend.downDown
            case .down:
                return GlucoseEntry.GlucoseTrend.down
            case .flat:
                return GlucoseEntry.GlucoseTrend.flat
            case .up:
                return GlucoseEntry.GlucoseTrend.up
            case .upUp:
                return GlucoseEntry.GlucoseTrend.upUp
            default:
                return GlucoseEntry.GlucoseTrend.notComputable
            }
        }
    }

    private func LibreLinkUpToGlucoseEntries(input: [LibreLinkResponseGlucose], previous: GlucoseEntry?) -> [GlucoseEntry] {

        var ge: [GlucoseEntry] = []
        var lastValue: Double = 0.0
        input.forEach { lluEntry in
            
            var changeRate = 0.0
            if lastValue > 0 {
                changeRate = lastValue - lluEntry.value
            }

            var trend: LLUTrendMap = LLUTrendMap(0)!
            if lluEntry.trend != nil {
                trend = LLUTrendMap(lluEntry.trend!)!
            }

            let entry = GlucoseEntry(glucose: lluEntry.value, date: lluEntry.timestamp, trend: trend.glucoseTrend, changeRate: changeRate)
            ge.append(entry)

            lastValue = lluEntry.value
        }

        return ge
    }

//    @ViewBuilder
//    override func getConnectionView(s: SettingsStore) -> some View {
//
//        @ObservedObject var settings: SettingsStore = s
//
//        Picker("", selection: $settings.libreConnectionID) {
//            ForEach(self.connections, id: \.patientID) {
//                Text("\($0.firstName) \($0.lastName)").tag($0.patientID)
//            }
//        }
//
//    }

    private func getConnections() async -> (connections: [LibreLinkUp.LibreLinkUpConnectionsResponse], success: Bool) {
        self.logger.debug("LibreLinkUp.getConnections")

        let path = "/connections"
        var request = createRequest(path: path, method: "GET")
        request.setValue("Bearer \(self.auth!.token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let res = response as! HTTPURLResponse

            if res.statusCode > 499 {
                // TODO: Handle error
                self.logger.error("High status code, not yet handled")
                return (connections: [], success: false)
            }

            do {
                let result = try JSONDecoder().decode(LibreLinkUpResponse<[LibreLinkUpConnectionsResponse]>.self, from: data)

                switch result.status {
                case 0:
//                    DispatchQueue.main.async {
                        self.logger.info("Status 0, updating values")
                        // TODO: Success
                        self.logger.info("Connection count: \(self.connections.count)")
                        self.connections = result.data!
                        self.connectionID = result.data!.first?.patientID ?? ""// self.connections.first?.patientID ?? ""
                        self.logger.debug("got connections: \(self.connections)")
//                    }
                    return (connections: result.data!, success: true)
//                    return true
                case 920: // Version bump needed
                          //                    self.logger.info("Version too low, bumping and retrying")
                          //                    self.lluVersion = result.data!.minimumVersion ?? "0"
                          //                    completion(false, true)
                    return (connections: [], success: false)
//                    return false
                default:
                    self.logger.debug("Default case triggered for status: \(result.status)")
                }
            } catch {
                self.logger.error("failed handling decode and actions from response \(String(describing: error))")
                self.logger.error("DEBUG: \(String(data: data, encoding: .utf8)!)")
                return (connections: [], success: false)
//                return false
            }
        } catch {
            self.logger.error("Catastrophic failure creating request.")
            return (connections: [], success: false)
//            return false
        }

        return (connections: [], success: false)
//        return false
    }

    private func authenticate() async -> Bool {
        self.logger.debug("LibreLinkUp.authenticate")
        self.providerIssue = nil

        let path = "/auth/login"
        let requestBody = LibreLinkUpAuthRequest(email: self.username, password: self.password)

        var request = createRequest(path: path, method: "POST")
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
        } catch {
            logger.info("failed marshalling json, aborting authenticate")
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            self.logger.error("DEBUG: \(String(data: data, encoding: .utf8)!)")

            let res = response as! HTTPURLResponse
            if res.statusCode > 499 {
                self.logger.error("Response code in 500 range. Dunno what to do! Code: \(res.statusCode)")
                return false
            }

            if res.statusCode > 399 {
                self.logger.error("Response code in 400 range. Something wrong? Rate limiting? Code: \(res.statusCode)")
                if res.statusCode == 430 || res.statusCode == 429 {
                    self.logger.error("Rate limited, surfacing to user.")
                    self.providerIssue = "Libre LinkUp is rate limiting you. Please close GlucoseBar try again in 5 minutes or more."
                }
                return false
            }


            let result = try JSONDecoder().decode(LibreLinkUpResponse<LibreLinkUpAuthResponse>.self, from: data)

            switch result.status {
            case 0:
                // TODO: Success
                // Check if redirect
                if let redirect = result.data!.redirect, let region = result.data!.region, redirect, !region.isEmpty {
                    self.apiRegion = result.data!.region!
                    return await self.authenticate()
                }

                guard let authToken = result.data!.authTicket?.token,
                      !authToken.isEmpty else {
                    self.logger.error("auth response did not satisfy requirements")
                    return false
                }

                // COMPLETED AUTH
                self.auth = result.data!.authTicket!

                // Getting connections
//                Task {
                let conns = await self.getConnections()
                self.connections = conns.connections
                return conns.success
//                    return await self.getConnections()
//                }
            case 2:
                // Bad credentials?
                self.logger.info("Bad credentials")
                return false
            case 4:
                // TODO: Request TOU
                self.logger.info("TOU needs calling")
//                    return await self.authenticate()
                return false

            case 920: // Version bump needed
                self.logger.info("Version too low, bumping and retrying")
                self.lluVersion = result.data!.data?.minimumVersion ?? "0"
                return await self.authenticate()
            default:
                self.logger.debug("Default case triggered for status: \(result.status)")

            }
        } catch {
            self.logger.error("failed handling decode and actions from response: \(String(describing: error))")
        }

        return false
    }

    override internal func verifyCredentials() async -> Bool {
        self.logger.debug("librelinkup.verifyCredentials")
        let authSuccess = await self.authenticate()

        if authSuccess {
            self.logger.debug("librelinkup auth success: \(self.connectionID)")

            let conns = await self.getConnections()
//            let connectionSuccess = await self.getConnections()
            if conns.success {
                self.connections = conns.connections
                self.logger.debug("librelinkup got connections successfully")
                return true
            }

            return false
        }

        self.logger.debug("librelinkup auth failure")
        return false

    }

    override public func isAuthValid() -> Bool {
        if auth == nil {
            return false
        }

        if auth!.token != "" {
            let expiryTime = Date(timeIntervalSince1970: Double(auth!.expires))

            return expiryTime.timeIntervalSinceNow > 0
        }

        return false
    }

    private func createRequest(path: String, method: String) -> URLRequest {

        var domain = self.server
        if self.apiRegion != "" {
            domain = self.server.replacingOccurrences(of: "api.", with: "api-\(self.apiRegion).")
        }

        let url = "\(domain)\(path)"
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: httpTimeout)

        for (header, value) in requestHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }

        request.httpMethod = method

        return request
    }

}

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

// MARK: CustomStringConvertible

extension LibreLinkError: CustomStringConvertible {
    var description: String {
        switch self {
        case .unknownError:
            return "Unknown error"
        case .missingStatusCode:
            return "Missing status code"
        case .maintenance:
            return "Maintenance"
        case .invalidURL:
            return "Invalid url"
        case .serializationError:
            return "Serialization error"
        case .missingUserOrToken:
            return "Missing user or token"
        case .missingLoginSession:
            return "Missing login session"
        case .missingPatientID:
            return "Missing patient id"
        case .invalidCredentials:
            return "Invalid credentials (check 'Settings' > 'Connection Settings')"
        case .missingCredentials:
            return "Missing credentials (check 'Settings' > 'Connection Settings')"
        case .notAuthenticated:
            return "Not authenticated"
        case .decoderError:
            return "Decoder error"
        case .missingData:
            return "Missing data"
        case .parsingError:
            return "Parsing error"
        case .cannotLock:
            return "Cannot lock"
        }
    }
}
