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
            return String(localized: "No extras")
        case .trio:
            return "Trio"
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

class GlucoseSource: Nightscout, @unchecked Sendable {

    private let httpTimeout = 120.0

    @MainActor
    public func checkDeviceStatusForGSE() async -> GlucoseSourceDevice {
        logger.debug("Nightscout.GlucoseSource.checkDeviceStatusForGSE")
        while isAuthenticating {
            usleep(1000)
        }

        let url = "\(baseURL)/api/v3/devicestatus?sort%24desc=created_at&limit=1&skip=0&fields=_all"

        do {
            var request = URLRequest(url: URL(string: url)!, timeoutInterval: httpTimeout)
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
                    let enacted = result.result.first!.openaps.enacted

                    var gsep = GlucoseSourceExtraProperties()
                    gsep.cob = enacted.cob ?? 0
                    gsep.iob = enacted.iob ?? 0
                    gsep.eventualGlucose = enacted.eventualBG
                    gsep.reason = enacted.reason
                    
                    var oapsf = OpenAPSForecasts()
                    if let iob = enacted.predBGs.iob {
                        oapsf.iob = iob
                    }
                    
                    if let cob = enacted.predBGs.cob {
                        oapsf.cob = cob
                    }
                    
                    if let uam = enacted.predBGs.uam {
                        oapsf.uam = uam
                    }
                    
                    if let zt = enacted.predBGs.zt {
                        oapsf.zt = zt
                    }
                    gsep.forecasts = oapsf
                    gsep.glucoseTarget = enacted.currentTarget
                    
                    DispatchQueue.global().sync {
                        self.GlucoseSourceExtras = gsep
                    }

                    return .trio
                }
                return .null
            } catch {
                self.logger.error("Unable to decode NS response when checking for GSE: \(String(describing: error), privacy: .public)")
                return .null
            }

        } catch {

            var err = String(describing: error)
            if (error as? URLError)?.code == .timedOut {
                err = String(localized: "Unable to get Trio data: Request timed out")
            }

            DispatchQueue.global().sync {
                var gsep = GlucoseSourceExtraProperties()
                gsep.error = err
                self.GlucoseSourceExtras = gsep
            }

            self.logger.error("Error parsing NS response: \(err, privacy: .public)")
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
            var request = URLRequest(url: URL(string: url)!, timeoutInterval: httpTimeout)
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
                    if let iob = enacted.predBGs.iob {
                        forecasts.iob = iob
                    }

                    if let cob = enacted.predBGs.cob {
                        forecasts.cob = cob
                    }

                    if let zt = enacted.predBGs.zt {
                        forecasts.zt = zt
                    }

                    if let uam = enacted.predBGs.uam {
                        forecasts.uam = uam
                    }

                    let dateFormatter = DateFormatter()
                    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                    dateFormatter.timeZone = TimeZone.init(secondsFromGMT: 0)
                    
                    let ts = dateFormatter.date(from: enacted.deliverAt)

                    return GlucoseSourceExtraProperties(iob: enacted.iob, cob: enacted.cob, eventualGlucose: enacted.eventualBG, reason: enacted.reason, enactedAt: ts, forecasts: forecasts, glucoseTarget: enacted.currentTarget)
                }
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
