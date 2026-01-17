//
//  GlucoseOps.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-15.
//

import Foundation

func convertGlucose(_ settings: SettingsStore, glucose: Double) -> Double {
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

func printFormattedGlucose(settings: SettingsStore, glucose: Double) -> String {
    if (settings.glucoseUnit == .mmoll) {
        return String(format: "%.1f mmol/L", glucose)
    }

    return String(format: "%.0f mg/dL", glucose)
}
