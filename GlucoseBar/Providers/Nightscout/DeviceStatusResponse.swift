//
//  DeviceStatusResponse.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-05-24.
//

import Foundation

// MARK: - DeviceStatusResponse
struct DeviceStatusResponse: Codable {
    let status: Int
    let result: [DeviceStatusResult]
}

// MARK: - Result
struct DeviceStatusResult: Codable {
    let app: String?
    let device: String?
    let openaps: Openaps?
    let loop: Loop?

    enum CodingKeys: String, CodingKey {
        case app, device, openaps, loop
    }
}

// MARK: - Loop
struct Loop: Codable {
    let predicted: LoopPredicted?
    let cob: LoopCOB?
    let iob: LoopIOB?
    let timestamp: String?
}

struct LoopPredicted: Codable {
    let startDate: String?
    let values: [Double]?
}

struct LoopCOB: Codable {
    let timestamp: String?
    let cob: Double?
}

struct LoopIOB: Codable {
    let timestamp: String?
    let iob: Double?
}

// MARK: - Openaps
struct Openaps: Codable {
    let iob: Iob?
    let suggested: Ted?
    let enacted: Ted?
}

// MARK: - Ted
struct Ted: Codable {
    let insulinForManualBolus: Double?
    let received: Bool?
    let sensitivityRatio: Double?
    let insulinReq: Double?
    let minDelta, reservoir, tdd: Double?
    let reason: String?
    let manualBolusErrorString: Double?
    let currentTarget, duration: Double?
    let expectedDelta: Double?
    let timestamp: String?
    let bg: Double?
    let id: String?
    let eventualBG, threshold: Double?
    let cob: Double?
    let iob: Double?
    let rate: Double?
    let deliverAt, temp: String?
    let predBGs: PredBGs?
    let isf, cr: Double?
    let dynamicIsf: Double?

    enum CodingKeys: String, CodingKey {
        case insulinForManualBolus
        case iob = "IOB"
        case received, sensitivityRatio, insulinReq, minDelta, reservoir
        case tdd = "TDD"
        case reason, manualBolusErrorString
        case currentTarget = "current_target"
        case duration, expectedDelta, timestamp, bg, id, eventualBG
        case cob = "COB"
        case threshold, rate, deliverAt, temp, predBGs
        case isf = "ISF"
        case dynamicIsf = "variable_sens"
        case cr = "CR"
    }
}

// MARK: - PredBGs
struct PredBGs: Codable {
    let zt, iob, cob, uam: [Int]?

    enum CodingKeys: String, CodingKey {
        case zt = "ZT"
        case iob = "IOB"
        case cob = "COB"
        case uam = "UAM"
    }
}

// MARK: - Iob
struct Iob: Codable {
    let basaliob: Double?
    let lastTemp: LastTemp?
    let netbasalinsulin, iob: Double?
    let time: String?
    let lastBolusTime: Int?
    let bolusiob: Double?
    let iobWithZeroTemp: IobWithZeroTemp?
    let activity, bolusinsulin: Double?
}

// MARK: - IobWithZeroTemp
struct IobWithZeroTemp: Codable {
    let basaliob: Double?
    let time: String?
    let netbasalinsulin, iob, bolusiob, activity: Double?
    let bolusinsulin: Double?
}

// MARK: - LastTemp
struct LastTemp: Codable {
    let timestamp: String?
    let date: Int?
    let duration: Double?
    let startedAt: String?
    let rate: Double?

    enum CodingKeys: String, CodingKey {
        case timestamp, date, duration
        case startedAt = "started_at"
        case rate
    }
}

// MARK: - Pump
struct Pump: Codable {
    let clock: String?
    let battery: Battery?
    let status: Status?
}

// MARK: - Battery
struct Battery: Codable {
    let display: Bool?
    let percent: Int?
    let string: String?
}

// MARK: - Status
struct Status: Codable {
    let bolusing: Bool?
    let timestamp, status: String?
    let suspended: Bool?
}

// MARK: - Uploader
struct Uploader: Codable {
    let battery: Int?
    let isCharging: Bool?
}
