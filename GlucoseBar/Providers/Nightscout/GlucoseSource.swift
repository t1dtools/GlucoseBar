//
//  DeviceStatus.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-05-24.
//

import Foundation
import OSLog

public enum GlucoseSourceDevice: String, CaseIterable, Identifiable, Sendable {
    case null
    case unknown
    case trio
    case openaps
    case aaps
    case loop
    public var id: String { self.rawValue }
    public var presentable: String {
        switch self {
        case .null:
            return String(localized: "No extras")
        case .unknown:
            return String(localized: "Unknown or no AID detected")
        case .trio:
            return "Trio"
        case .openaps:
            return "OpenAPS"
        case .aaps:
            return "AAPS"
        case .loop:
            return "Loop"
        }
    }
    
    static func fromDS(status: DeviceStatusResult) -> GlucoseSourceDevice {
        if status.device == "Trio" {
            return .trio
        } else if status.device?.starts(with: "openaps://") == true {
            if (status.app == "AAPS") {
                return .aaps
            } else {
                return .openaps
            }
        } else if status.device?.starts(with: "loop://") == true {
            return .loop
        } else {
            return .unknown
        }
        
    }
}

public enum ForecastDisplay: String, CaseIterable, Identifiable {
    case cone
    case lines
    public var id: String { self.rawValue }
    public var presentable: String {
        switch self {
        case .cone:
            return String(localized: "Cone", comment: "Used for the forecast display selector in Trio integration to select the Cone of Uncertainty")
        case .lines:
            return String(localized: "Lines", comment: "Used for the forecast display selector in Trio integration to select the prediction lines")
        }
    }
}

struct GlucoseSource {
    let baseURL: String
    let token: String
    let aidEnabled: Bool
    private let logger = Logger(subsystem: "tools.t1d.GlucoseBarChart", category: "GlucoseSource")
    private let httpTimeout = 120.0

    func checkDeviceStatusForGSE() async throws -> (device: GlucoseSourceDevice, error: String?) {
        logger.debug("Nightscout.GlucoseSource.checkDeviceStatusForGSE")

        if !aidEnabled {
            logger.debug("AID integration not enabled, bailing out.")
            return (.null, nil)
        }

        let url = "\(baseURL)/api/v3/devicestatus?sort%24desc=created_at&limit=1&skip=0&fields=_all"

        do {
            var request = URLRequest(url: URL(string: url)!, timeoutInterval: httpTimeout)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)

            let res = response as? HTTPURLResponse
            if res == nil {
                self.logger.error("Unable to cast response to HTTPURLResponse")
                return (.unknown, nil)
            }

            if res!.statusCode != 200 {
                return (.unknown, nil)
            }

            do {
                let result = try JSONDecoder().decode(DeviceStatusResponse.self, from: data)
                if result.result.first == nil {
                    return (.unknown, nil)
                }

                let handled = await handleGSE(result.result.first!)
                return (handled.device, nil)
            } catch {
                self.logger.error("Unable to decode NS response when checking for GSE: \(String(describing: error), privacy: .public)")
                return (.unknown, String(describing: error))
            }

        } catch {

            var err = String(describing: error)
            if (error as? URLError)?.code == .timedOut {
                err = String(localized: "Unable to get Trio data: Request timed out")
            }

            self.logger.error("Error parsing NS response: \(err, privacy: .public)")
            return (.unknown, err)
        }
    }

    func getGlucoseSourceExtras() async -> GlucoseSourceExtraProperties {
        let empty = GlucoseSourceExtraProperties(aid: .unknown)

        logger.debug("Nightscout.GlucoseSource.getGlucoseSourceExtras")

        let url = "\(baseURL)/api/v3/devicestatus?sort%24desc=created_at&limit=1&skip=0&fields=_all"

        do {
            var request = URLRequest(url: URL(string: url)!, timeoutInterval: httpTimeout)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)

            let res = response as? HTTPURLResponse
            if res == nil {
                self.logger.error("Unable to cast response to HTTPURLResponse")
                return empty
            }

            if res!.statusCode != 200 {
                return empty
            }

            do {
                let result = try JSONDecoder().decode(DeviceStatusResponse.self, from: data)
                if (result.result.first == nil) {
                    return empty
                }

                let gse = await handleGSE(result.result.first!)
//                await MainActor.run {
//                    self.GlucoseSourceExtras = gse.gse
//                }
                return gse.gse
            } catch {
                self.logger.error("Unable to decode NS response when checking for GSE: \(String(describing: error), privacy: .public)")
            }
        } catch {
            var err = String(describing: error)
            if (error as? URLError)?.code == .timedOut {
                err = String(localized: "Unable to get Trio data: Request timed out")
            }

            self.logger.error("Error fetching GlucoseSourceExtra: \(err, privacy: .public)")
        }

        return empty
    }
}
