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
    public var id: String { self.rawValue }
    public var presentable: String {
        switch self {
        case .null:
            return "No extras"
        case .trio:
            return "Trio"
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

                if result.result.first!.device == "Trio" {
                    self.logger.info("IT IS TRIO! WOOHOO!!!!")
                    self.logger.info("IOB: \(result.result.first?.openaps.enacted.iob ?? 1000.0)u")
                    let enacted = result.result.first!.openaps.enacted

                    var gsep = GlucoseSourceExtraProperties()
                    gsep.cob = enacted.cob ?? 0
                    gsep.iob = enacted.iob ?? 0
                    gsep.eventualGlucose = enacted.eventualBG
                    gsep.reason = enacted.reason
                    
                    var oapsf = OpenAPSForecasts()
                    if enacted.predBGs.iob != nil {
                        oapsf.iob = enacted.predBGs.iob
                    }
                    
                    if enacted.predBGs.cob != nil {
                        oapsf.cob = enacted.predBGs.cob
                    }
                    
                    if enacted.predBGs.uam != nil {
                        oapsf.uam = enacted.predBGs.uam
                    }
                    
                    if enacted.predBGs.zt != nil {
                        oapsf.zt = enacted.predBGs.zt
                    }
                    gsep.forecasts = oapsf
                    
                    DispatchQueue.global().sync {
                        self.GlucoseSourceExtras = gsep
                    }

                    return .trio
                }
                return .null
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

                if result.result.first!.device == "Trio" {
                    let enacted = result.result.first!.openaps.enacted
                    var forecasts = OpenAPSForecasts()
                    if enacted.predBGs.iob != nil {
                        forecasts.iob = enacted.predBGs.iob
                    }
                    
                    if enacted.predBGs.cob != nil {
                        forecasts.cob = enacted.predBGs.cob
                    }
                    
                    if enacted.predBGs.zt != nil {
                        forecasts.zt = enacted.predBGs.zt
                    }
                    
                    if enacted.predBGs.uam != nil {
                        forecasts.uam = enacted.predBGs.uam
                    }
                    
                    
                    return GlucoseSourceExtraProperties(iob: enacted.iob, cob: enacted.cob, eventualGlucose: enacted.eventualBG, reason: enacted.reason, forecasts: forecasts)
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
