//
//  DeviceStatus.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-05-24.
//

import Foundation

public enum GlucoseSourceDevice: String, CaseIterable, Identifiable, Sendable {
    case null
    case trio
    case openaps
    case aaps
    public var id: String { self.rawValue }
    public var presentable: String {
        switch self {
        case .null:
            return "No extras"
        case .trio:
            return "Trio"
        case .openaps:
            return "OpenAPS"
        case .aaps:
            return "AAPS"
        }
    }
    
    static func fromDS(status: DeviceStatusResult) -> GlucoseSourceDevice {
        if status.device == "Trio" {
            return .trio
        } else if status.device.starts(with: "openaps://") {
            if (status.app == "AAPS") {
                return .aaps
            } else {
                return .openaps
            }
        } else {
            return .null
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
            return "Cone"
        case .lines:
            return "Lines"
        }
    }
}

class GlucoseSource: Nightscout, @unchecked Sendable {

    @MainActor
    public func checkDeviceStatusForGSE() async -> GlucoseSourceDevice {
        logger.debug("Nightscout.GlucoseSource.checkDeviceStatusForGSE")
        while isAuthenticating {
            usleep(1000)
        }

        let url = "\(baseURL)/api/v3/devicestatus?sort%24desc=created_at&limit=1&skip=0&fields=_all"

        do {
            var request = URLRequest(url: URL(string: url)!, timeoutInterval: 60)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            request.httpMethod = "GET"

            let (data, response) = try await URLSession.shared.data(for: request)

            let res = response as? HTTPURLResponse
            if res == nil {
                self.logger.error("Unable to cast response to HTTPURLResponse")
                return .null
            }

            if res!.statusCode != 200 {
                return .null
            }
            
            do {
                let result = try JSONDecoder().decode(DeviceStatusResponse.self, from: data)
    
                let firstResult = result.result.first
                if firstResult == nil {
                    self.logger.error("No result found in DeviceStatus")
                    return .null
                }
                
                let device = GlucoseSourceDevice.fromDS(status: firstResult!)
                if device != GlucoseSourceDevice.null {
                    let enacted = firstResult!.openaps?.enacted ?? firstResult!.openaps?.suggested
                    if enacted == nil {
                        self.logger.error("No enacted/suggested found in DeviceStatus")
                        return .null
                    }

                    var gsep = GlucoseSourceExtraProperties()
                    gsep.cob = enacted!.cob ?? 0
                    gsep.iob = enacted!.iob ?? 0
                    gsep.eventualGlucose = enacted!.eventualBG
                    gsep.reason = enacted!.reason
                    gsep.forecasts = OpenAPSForecasts.fromPredBGs(predBGs: enacted!.predBGs)
                    gsep.glucoseTarget = enacted!.currentTarget
                    
                    DispatchQueue.global().sync {
                        self.GlucoseSourceExtras = gsep
                    }
                }
                return device
            } catch {
                self.logger.error("Unable to decode NS response when checking for GSE: \(String(describing: error))")
                return .null
            }

        } catch {
            self.logger.error("Error parsing NS response: \(String(describing: error))")
            return .null
        }
    }

    @MainActor
    public func getGlucoseSourceExtras() async -> GlucoseSourceExtraProperties {
        let empty = GlucoseSourceExtraProperties()

        logger.debug("Nightscout.GlucoseSource.getGlucoseSourceExtras")
        while isAuthenticating {
            usleep(1000)
        }

        let url = "\(baseURL)/api/v3/devicestatus?sort%24desc=created_at&limit=1&skip=0&fields=_all"

        do {
            var request = URLRequest(url: URL(string: url)!, timeoutInterval: 60)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            request.httpMethod = "GET"

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
                
                let firstResult = result.result.first
                if firstResult == nil {
                    self.logger.error("No result found in DeviceStatus")
                    return empty
                }
                
                let device = GlucoseSourceDevice.fromDS(status: firstResult!)
                if device != GlucoseSourceDevice.null {
                    let enacted = firstResult!.openaps?.enacted ?? firstResult!.openaps?.suggested
                    if enacted == nil {
                        self.logger.error("No enacted/suggested found in DeviceStatus")
                        return empty
                    }

                    let dateFormatter = DateFormatter()
                    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                    dateFormatter.timeZone = TimeZone.init(secondsFromGMT: 0)

                    return GlucoseSourceExtraProperties(
                        iob: enacted!.iob,
                        cob: enacted!.cob,
                        eventualGlucose: enacted!.eventualBG,
                        reason: enacted!.reason,
                        enactedAt: dateFormatter.date(from: enacted!.deliverAt),
                        forecasts: OpenAPSForecasts.fromPredBGs(predBGs: enacted!.predBGs),
                        glucoseTarget: enacted!.currentTarget
                    )
                }
            } catch {
                self.logger.error("Unable to decode NS response when checking for GSE: \(String(describing: error))")
            }
        } catch {
            self.logger.error("Error parsing NS response: \(String(describing: error))")
        }

        return empty
    }
}
