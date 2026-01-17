//
//  DeviceStatus.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-05-24.
//

import Foundation

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

class GlucoseSource: Nightscout, @unchecked Sendable {

    private let httpTimeout = 120.0

    @MainActor
    public func checkDeviceStatusForGSE() async -> GlucoseSourceDevice {
        logger.debug("Nightscout.GlucoseSource.checkDeviceStatusForGSE")

        if !aidEnabled {
            logger.debug("AID integration not enabled, bailing out.")
            return .null
        }

        // Wait for authentication to complete using proper async pattern
        var retryCount = 0
        while isAuthenticating && retryCount < 30 { // Max 30 seconds wait
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            retryCount += 1
        }

        if isAuthenticating {
            logger.warning("Timeout waiting for authentication to complete")
            return .null
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
                return .unknown
            }

            if res!.statusCode != 200 {
                return .unknown
            }
            
            do {
                let result = try JSONDecoder().decode(DeviceStatusResponse.self, from: data)
                if result.result.first == nil {
                    return .unknown
                }

                let device = GlucoseSourceDevice.fromDS(status: result.result.first!)
                if device != GlucoseSourceDevice.null {

                    var gsep = GlucoseSourceExtraProperties()
                    switch device {
                    case .loop:
                        let loop = result.result.first!.loop
                        if loop == nil {
                            self.logger.error("unable to get loop from DeviceStatus")
                            return .unknown
                        }

                        gsep.cob = loop!.cob?.cob ?? 0
                        gsep.iob = loop!.iob?.iob ?? 0
                        gsep.forecasts = AIDForecasts.fromLoopPredicted(loop?.predicted)
                        gsep.aid = device

                        await MainActor.run {
                            self.GlucoseSourceExtras = gsep
                        }
                        break
                    case .trio, .aaps, .openaps:
                        let enacted = result.result.first!.openaps?.enacted ?? result.result.first!.openaps?.suggested
                        if enacted == nil {
                            self.logger.error("No enacted/suggested found in DeviceStatus")
                            return .unknown
                        }

                        let dateFormatter = DateFormatter()
                        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                        dateFormatter.timeZone = TimeZone.init(secondsFromGMT: 0)

                        let ts = dateFormatter.date(from: enacted?.deliverAt ?? " ") // " " because that causes nil instead of now

                        gsep.cob = enacted!.cob ?? 0
                        gsep.iob = enacted!.iob ?? 0
                        gsep.eventualGlucose = enacted!.eventualBG
                        gsep.reason = enacted!.reason
                        gsep.forecasts = AIDForecasts.fromPredBGs(predBGs: enacted!.predBGs)
                        gsep.glucoseTarget = enacted!.currentTarget
                        gsep.enactedAt = ts
                        gsep.aid = device

                        await MainActor.run {
                            self.GlucoseSourceExtras = gsep
                        }
                        break
                    default:
                        self.logger.error("Invalid or unknown device: \(device.presentable, privacy: .public)")
                        return .unknown
                    }
                }
                return device
            } catch {
                self.logger.error("Unable to decode NS response when checking for GSE: \(String(describing: error), privacy: .public)")
                return .unknown
            }

        } catch {

            var err = String(describing: error)
            if (error as? URLError)?.code == .timedOut {
                err = String(localized: "Unable to get Trio data: Request timed out")
            }

            await MainActor.run {
                var gsep = GlucoseSourceExtraProperties()
                gsep.error = err
                self.GlucoseSourceExtras = gsep
            }

            self.logger.error("Error parsing NS response: \(err, privacy: .public)")
            return .unknown
        }
    }

    @MainActor
    public func getGlucoseSourceExtras() async -> GlucoseSourceExtraProperties {
        let empty = GlucoseSourceExtraProperties(aid: .unknown)

        logger.debug("Nightscout.GlucoseSource.getGlucoseSourceExtras")

        // Wait for authentication to complete using proper async pattern
        var retryCount = 0
        while isAuthenticating && retryCount < 30 { // Max 30 seconds wait
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            retryCount += 1
        }

        if isAuthenticating {
            logger.warning("Timeout waiting for authentication to complete")
            return empty
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
                if (result.result.first == nil) {
                    return empty
                }

                let device = GlucoseSourceDevice.fromDS(status: result.result.first!)
                if device != GlucoseSourceDevice.null {

                    var gsep = GlucoseSourceExtraProperties()
                    switch device {
                    case .loop:
                        let loop = result.result.first!.loop
                        if loop == nil {
                            self.logger.error("unable to get loop from DeviceStatus")
                            return empty
                        }

                        gsep.cob = loop!.cob?.cob ?? 0
                        gsep.iob = loop!.iob?.iob ?? 0
                        gsep.forecasts = AIDForecasts.fromLoopPredicted(loop!.predicted)
                        gsep.aid = device

                        return gsep
                    case .trio, .aaps, .openaps:
                        let enacted = result.result.first!.openaps?.enacted ?? result.result.first!.openaps?.suggested
                        if enacted == nil {
                            self.logger.error("No enacted/suggested found in DeviceStatus")
                            return empty
                        }

                        let dateFormatter = DateFormatter()
                        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                        dateFormatter.timeZone = TimeZone.init(secondsFromGMT: 0)

                        let ts = dateFormatter.date(from: enacted?.deliverAt ?? " ") // " " because that causes nil instead of now

                        gsep.cob = enacted!.cob ?? 0
                        gsep.iob = enacted!.iob ?? 0
                        gsep.eventualGlucose = enacted!.eventualBG
                        gsep.reason = enacted!.reason
                        gsep.forecasts = AIDForecasts.fromPredBGs(predBGs: enacted!.predBGs)
                        gsep.glucoseTarget = enacted!.currentTarget
                        gsep.enactedAt = ts
                        gsep.aid = device

                        return gsep

                    default:
                        self.logger.error("Invalid or unknown device: \(device.presentable, privacy: .public)")
                        return empty
                    }
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
