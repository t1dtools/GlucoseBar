//
//  TandemResponseModels.swift
//  GlucoseBar
//
//

import Foundation

// MARK: - BFF Pumper

struct BffPumper: Codable {
    let firstName: String?
    let lastName: String?
    let name: String?
    let lowGlucoseThreshold: Int?
    let highGlucoseThreshold: Int?
    let pumps: [BffPump]?
}

struct BffPump: Codable {
    let assignmentId: String?
    let serialNumber: String?
    let modelNumber: String?
    let modelName: String?
    let softwareVersion: String?
    let algorithm: String?
    let glucoseUnit: String?
    let lastUploadDate: String?
    let maxDateOfEvents: String?
    let partNumber: String?
    let lastUploadClientType: String?
    let availableDataRange: BffAvailableDataRange?
    let settings: BffPumpSettings?
}

struct BffAvailableDataRange: Codable {
    let start: String?
    let end: String?
}

struct BffPumpSettings: Codable {
    let id: String?
    let deviceAssignmentId: String?
    let uploadedTimeStamp: String?
    let settingsHash: String?
    let uploadId: String?
    let details: BffPumpSettingsDetails?
}

struct BffPumpSettingsDetails: Codable {
    private var storage: [String: PumpLogProperty] = [:]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        storage = try container.decode([String: PumpLogProperty].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage)
    }

    subscript(key: String) -> PumpLogProperty? { storage[key] }

    var dda: Double? { storage["dda"]?.doubleValue }
    var basalRate: Double? { storage["maxBasalRate"]?.doubleValue }
    var pumpId: String? { storage["pumpId"]?.stringValue }
}

// MARK: - Pump Logs

struct PumpLogsResponse: Codable {
    let events: [PumpLogEvent]?
    let clockChanges: [PumpLogEvent]?
}

struct PumpLogEvent: Codable {
    let deviceAssignmentId: String?
    let eventCode: Int?
    let sequenceGroup: Int?
    let sequenceNumber: Int?
    let pumpDateTime: String?
    let estimatedDateTime: String?
    let eventProperties: [String: PumpLogProperty]?
}

enum PumpLogProperty: Codable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)
    case array([PumpLogProperty])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self = .double(doubleVal)
        } else if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let stringVal = try? container.decode(String.self) {
            self = .string(stringVal)
        } else if let arrayVal = try? container.decode([PumpLogProperty].self) {
            self = .array(arrayVal)
        } else if container.decodeNil() {
            self = .null
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    var intValue: Int? { if case .int(let v) = self { return v }; if case .double(let v) = self { return Int(v) }; return nil }
    var doubleValue: Double? { if case .double(let v) = self { return v }; if case .int(let v) = self { return Double(v) }; return nil }
    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
}

// MARK: - Basal Chart Data

struct BasalSegment: Identifiable, Sendable {
    var id = UUID()
    let date: Date
    let profileRate: Double  // scheduled basal (profile rate / 1000 U/hr)
    let actualRate: Double   // delivered basal (commanded rate / 1000 U/hr)
}

// MARK: - Bolus History

struct BolusRecord: Identifiable, Sendable {
    var id = UUID()
    let date: Date
    let insulinDelivered: Double
    let insulinRequested: Double?
    let carbAmount: Double?
    let bolusType: String?
    let bg: Double?
    let isExtended: Bool
    let eventCode: Int
}
