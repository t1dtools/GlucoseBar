//
//  TandemResponseModels.swift
//  GlucoseBar
//
//

import Foundation

// MARK: - Android API OAuth2

struct TandemOAuthResponse: Codable {
    let accessToken: String
    let accessTokenExpiresAt: String
    let refreshToken: String?
    let refreshTokenExpiresAt: String?
    let user: TandemOAuthUser?
    let patientObjectId: String?
    let userGuid: String?
}

struct TandemOAuthUser: Codable {
    let id: String?
    let firstName: String?
    let lastName: String?
    let emailAddress: String?
}

// MARK: - User Profile

struct TandemUserProfile: Codable {
    let userID: String?
    let targetBgHigh: Int?
    let targetBgLow: Int?
    let hypoThreshold: Int?
    let hyperThreshold: Int?
    let hasCGM: Bool?
    let hasBASALIQ: Bool?
    let hasControlIQ: Bool?
    let patientFullName: String?
}

// MARK: - Therapy Thresholds

struct TandemTherapyThresholds: Codable {
    let targetBGHigh: Int?
    let targetBGLow: Int?
    let hypoThreshold: Int?
    let hyperThreshold: Int?
    let siteChangeThreshold: Int?
    let cartridgeChangeThreshold: Int?
    let tubingChangeThreshold: Int?
}

// MARK: - Pump Features

struct TandemPumpFeatures: Codable {
    let serialNumber: String?
    let features: TandemPumpFeaturesDetail?
}

struct TandemPumpFeaturesDetail: Codable {
    let controlIQ: TandemControlIQFeature?
}

struct TandemControlIQFeature: Codable {
    let feature: Int?
    let dateTimeFirstDetected: String?
    let unixTimestamp: Int?
}

// MARK: - Last Event Uploaded

struct TandemLastEventUploaded: Codable {
    let maxPumpEventIndex: Int?
    let processingStatus: Int?
}

// MARK: - Dashboard Summary

struct TandemDashboardSummary: Codable {
    let averageReading: Int?
    let timeInUseMinutes: Int?
    let controlIqSetToOffMinutes: Int?
    let cgmInactiveMinutes: Int?
    let pumpInactiveMinutes: Int?
    let averageDailySleepMinutes: Int?
    let weeklyExerciseEvents: Int?
    let timeInUsePercent: Int?
    let controlIqOffPercent: Int?
    let cgmInactivePercent: Int?
    let pumpInactivePercent: Int?
    let totalDays: Int?
}

// MARK: - ControlIQ Therapy Timeline (basal events)

struct TandemTherapyTimelineResponse: Codable {
    let event: [TandemTherapyTimelineEvent]?
}

struct TandemTherapyTimelineEvent: Codable {
    let type: String?
    let x: Int?
    let y: Double?
    let duration: Int?
    let basalRate: Double?
    let egv: Int?
    let eventId: Int?
    let eventType: Int?
    let continuation: Bool?
    let suspendReason: String?
    let standard: TandemBolusEvent?
    let insulinDelivered: Double?
    let requestedInsulin: Double?
    let carbSize: Double?
    let bg: String?
    let userOverride: String?
    let description: String?
    let completionStatus: String?

    enum CodingKeys: String, CodingKey {
        case type, x, y, duration, basalRate, egv, eventId, eventType
        case continuation, suspendReason, standard, insulinDelivered
        case requestedInsulin, carbSize, bg, userOverride, description
        case completionStatus
    }
}

struct TandemBolusEvent: Codable {
    let bolusId: String?
    let requestDateTime: String?
    let completionDateTime: String?
    let insulinDelivered: Double?
    let actualTotalBolusRequested: Double?
    let carbSize: Double?
    let bg: String?
    let userOverride: String?
    let extendedBolus: Bool?
    let bolexCompletionDateTime: String?
    let bolexStartDateTime: String?
    let completionStatus: String?
    let description: String?
}

// MARK: - Therapy Events response (CIQ)

struct TandemTherapyEventsResponse: Codable {
    let event: [TandemTherapyEvent]?
}

struct TandemTherapyEvent: Codable {
    let type: String?
    let eventDateTime: String?
    let egv: Int?
    let basalRate: Double?
    let insulinDelivered: Double?
    let requestedInsulin: Double?
    let carbSize: Double?
    let bg: String?
    let userOverride: String?
    let description: String?
    let completionStatus: String?
    let extendedBolus: Bool?
    let bolexCompletionDateTime: String?
    let bolexStartDateTime: String?
}

// MARK: - WS2 CSV Therapy Timeline

struct TandemWS2TherapyTimeline {
    let readingData: [[String: String]]
    let iobData: [[String: String]]
    let basalData: [[String: String]]
    let bolusData: [[String: String]]

    init(reading: [[String: String]] = [],
         iob: [[String: String]] = [],
         basal: [[String: String]] = [],
         bolus: [[String: String]] = []) {
        self.readingData = reading
        self.iobData = iob
        self.basalData = basal
        self.bolusData = bolus
    }
}

// MARK: - Basal Suspension (WS2)

struct TandemBasalSuspensionResponse: Codable {
    let BasalSuspension: [TandemBasalSuspensionEvent]?
}

struct TandemBasalSuspensionEvent: Codable {
    let EventDateTime: String?
    let SuspendReason: String?
}
