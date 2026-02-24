//
//  GlucoseOps.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import Foundation

@MainActor func convertGlucose(_ settings: SettingsStore, glucose: Double) -> Double {
    if settings.glucoseUnit == .mmoll {
        return glucose / 18
    }

    return glucose
}

@MainActor func formatGlucoseForDisplay(settings: SettingsStore, glucose: Double) -> String {
    if (settings.glucoseUnit == .mmoll) {
        return String(format: "%.1f", glucose/18.0)
    }

    return String(format: "%.0f", glucose)
}

@MainActor func formatDeltaForDisplay(settings: SettingsStore, delta: Double) -> String {
    if (settings.glucoseUnit == .mmoll) {
        return delta > 0 ? String(format: "+%.1f", delta/18.0) : String(format: "%.1f", delta/18.0)
    }

    return delta > 0 ? String(format: "+%.0f", delta) : String(format: "%.0f", delta)
}

func formatIOBForDisplay(iob: Double) -> String {
    if iob < 0 {
        return String(format: "%.2f", iob)
    }
    return String(format: "%.1f", iob)
}

func formatCOBForDisplay(cob: Double) -> String {
    return String(format: "%.0f", cob)
}

@MainActor func printFormattedGlucose(settings: SettingsStore, glucose: Double) -> String {
    if (settings.glucoseUnit == .mmoll) {
        return String(format: "%.1f mmol/L", glucose)
    }

    return String(format: "%.0f mg/dL", glucose)
}

func handleGSE(_ data: DeviceStatusResult) async -> (device: GlucoseSourceDevice, gse: GlucoseSourceExtraProperties) {
    let device = GlucoseSourceDevice.fromDS(status: data)
    var gsep = GlucoseSourceExtraProperties()

    if device != GlucoseSourceDevice.null {
        switch device {
        case .loop:
            let loop = data.loop
            if loop == nil {
                return (.unknown, gsep)
            }

            gsep.cob = loop!.cob?.cob ?? 0
            gsep.iob = loop!.iob?.iob ?? 0
            gsep.forecasts = AIDForecasts.fromLoopPredicted(loop?.predicted)
            gsep.aid = device
            break
        case .trio, .aaps, .openaps:
            let enacted = data.openaps?.enacted ?? data.openaps?.suggested
            if enacted == nil {
                return (.unknown, gsep)
            }

            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
            dateFormatter.timeZone = TimeZone.init(secondsFromGMT: 0)

            let ts = dateFormatter.date(from: enacted?.deliverAt ?? " ") // nbsp (" ") because that causes nil instead of now

            gsep.cob = enacted!.cob ?? 0
            gsep.iob = enacted!.iob ?? 0
            gsep.eventualGlucose = enacted!.eventualBG
            gsep.reason = enacted!.reason
            gsep.forecasts = AIDForecasts.fromPredBGs(predBGs: enacted!.predBGs)
            gsep.glucoseTarget = enacted!.currentTarget
            gsep.enactedAt = ts
            gsep.aid = device
            break
        default:
            return (.unknown, gsep)
        }
    }

    return (device, gsep)
}
