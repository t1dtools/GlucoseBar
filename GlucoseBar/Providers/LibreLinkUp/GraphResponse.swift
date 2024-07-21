//
//  GraphResponse.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-12-21.
//

import Foundation

// MARK: - LibreLinkUpGraphResponse
struct LibreLinkUpGraphResponse: Codable {
    let status: Int
    let data: DataClass

    enum CodingKeys: String, CodingKey {
        case status = "status"
        case data = "data"
    }
}

// MARK: - DataClass
struct DataClass: Codable {
//    let connection: Connection
//    let activeSensors: [ActiveSensor]
    let graphData: [LibreLinkUpGraphData]

    enum CodingKeys: String, CodingKey {
        case graphData = "graphData"
    }
}

// MARK: - ActiveSensor
//struct ActiveSensor: Codable {
//    let sensor: Sensor
//    let device: Device
//}

// MARK: - Device
//struct Device: Codable {
//    let did: String
//    let dtid: Int
//    let v: String
//    let ll, hl, u: Int
//    let fixedLowAlarmValues: FixedLowAlarmValues
//    let alarms: Bool
//    let fixedLowThreshold: Int
//}

// MARK: - FixedLowAlarmValues
//struct FixedLowAlarmValues: Codable {
//    let mgdl: Int
//    let mmoll: Double
//}

// MARK: - Sensor
//struct Sensor: Codable {
//    let deviceID, sn: String
//    let a, w, pt: Int
//    let s, lj: Bool
//
//    enum CodingKeys: String, CodingKey {
//        case deviceID = "deviceId"
//        case sn, a, w, pt, s, lj
//    }
//}

// MARK: - Connection
//struct Connection: Codable {
//    let id, patientID, country: String
//    let status: Int
//    let firstName, lastName: String
//    let targetLow, targetHigh, uom: Int
//    let sensor: Sensor
//    let alarmRules: AlarmRules
//    let glucoseMeasurement, glucoseItem: LibreLinkUpGraphData
//    let glucoseAlarm: JSONNull?
//    let patientDevice: Device
//    let created: Int
//
//    enum CodingKeys: String, CodingKey {
//        case id
//        case patientID = "patientId"
//        case country, status, firstName, lastName, targetLow, targetHigh, uom, sensor, alarmRules, glucoseMeasurement, glucoseItem, glucoseAlarm, patientDevice, created
//    }
//}

// MARK: - AlarmRules
//struct AlarmRules: Codable {
//    let c: Bool
//    let h: H
//    let f, l: F
//    let nd: Nd
//    let p, r: Int
//    let std: Std
//}

// MARK: - F
//struct F: Codable {
//    let th: Int
//    let thmm: Double
//    let d, tl: Int
//    let tlmm: Double
//}

// MARK: - H
//struct H: Codable {
//    let th: Int
//    let thmm: Double
//    let d: Int
//    let f: Double
//}

// MARK: - Nd
//struct Nd: Codable {
//    let i, r, l: Int
//}

// MARK: - Std
//struct Std: Codable {
//    let sd: Bool
//}

// MARK: - GlucoseItem
struct LibreLinkUpGraphData: Codable {
    let factoryTimestamp, timestamp: String
    let type, valueInMgPerDL: Int
    let trendArrow: Int?
    let trendMessage: JSONNull?
    let measurementColor, glucoseUnits: Int
    let value: Double
    let isHigh, isLow: Bool

    enum CodingKeys: String, CodingKey {
        case factoryTimestamp = "FactoryTimestamp"
        case timestamp = "Timestamp"
        case type
        case valueInMgPerDL = "ValueInMgPerDl"
        case trendArrow = "TrendArrow"
        case trendMessage = "TrendMessage"
        case measurementColor = "MeasurementColor"
        case glucoseUnits = "GlucoseUnits"
        case value = "Value"
        case isHigh, isLow
    }
}

// MARK: - Ticket
//struct Ticket: Codable {
//    let token: String
//    let expires, duration: Int
//}

// MARK: - Encode/decode helpers

class JSONNull: Codable, Hashable {

    public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
        return true
    }

    public var hashValue: Int {
        return 0
    }

    public init() {}

    public required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if !container.decodeNil() {
            throw DecodingError.typeMismatch(JSONNull.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for JSONNull"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}
