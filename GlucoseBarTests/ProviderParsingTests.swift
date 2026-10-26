//
//  ProviderParsingTests.swift
//  GlucoseBarTests
//

import XCTest
@testable import GlucoseBar

/// Decoding tests for the provider payloads, using fixtures shaped like the real
/// responses. These are the code paths that break whenever a vendor changes an
/// endpoint (the Tandem `eventIds` -> `eventCodes` rename being the obvious
/// precedent), and the failures are otherwise only visible to users.
final class ProviderParsingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Nightscout entries

    func testDecodesNightscoutEntriesResponse() throws {
        let json = """
        {
          "status": 200,
          "result": [
            {
              "identifier": "65f1c2",
              "date": 1750000000000,
              "sgv": 112,
              "trend": 4,
              "direction": "Flat",
              "trendRate": 0.1
            }
          ]
        }
        """

        let response = try decode(Nightscout.NightscoutEntriesResponse.self, json)

        XCTAssertEqual(response.status, 200)
        let entry = try XCTUnwrap(response.result.first)
        XCTAssertEqual(entry.identifier, "65f1c2")
        XCTAssertEqual(entry.sgv, 112)
        XCTAssertEqual(entry.date, 1750000000000)
        XCTAssertEqual(entry.direction, "Flat")
    }

    /// Entries without an sgv (calibrations, meter readings) must still decode;
    /// they are filtered later rather than failing the whole response.
    func testDecodesEntryWithoutSgv() throws {
        let json = """
        {"status": 200, "result": [{"identifier": "cal1", "date": 1750000000000, "direction": "Flat"}]}
        """

        let response = try decode(Nightscout.NightscoutEntriesResponse.self, json)
        XCTAssertNil(response.result.first?.sgv)
    }

    // MARK: - AID / devicestatus

    func testDecodesLoopDeviceStatus() async throws {
        let json = """
        {
          "status": 200,
          "result": [
            {
              "device": "loop://iPhone",
              "app": "loop",
              "mills": 1750000000000,
              "loop": {
                "timestamp": "2026-07-05T10:03:40Z",
                "cob": { "timestamp": "2026-07-05T10:03:40Z", "cob": 12.5 },
                "iob": { "timestamp": "2026-07-05T10:03:40Z", "iob": 1.75 },
                "predicted": {
                  "startDate": "2026-07-05T10:03:40Z",
                  "values": [120, 118, 115, 111]
                }
              }
            }
          ]
        }
        """

        let response = try decode(DeviceStatusResponse.self, json)
        let status = try XCTUnwrap(response.result.first)

        XCTAssertEqual(GlucoseSourceDevice.fromDS(status: status), .loop)

        let (device, extras) = await handleGSE(status)
        XCTAssertEqual(device, .loop)
        XCTAssertEqual(extras.cob, 12.5)
        XCTAssertEqual(extras.iob, 1.75)
        XCTAssertEqual(extras.aid, .loop)
        // The first predicted value is "now" and is dropped.
        XCTAssertEqual(extras.forecasts.loop, [118, 115, 111])
    }

    func testDecodesTrioEnactedDeviceStatus() async throws {
        let json = """
        {
          "status": 200,
          "result": [
            {
              "device": "Trio",
              "app": "Trio",
              "mills": 1750000000000,
              "openaps": {
                "enacted": {
                  "deliverAt": "2026-07-05T10:03:40.000Z",
                  "reason": "COB: 12.5, IOB: 1.75",
                  "eventualBG": 118,
                  "current_target": 100,
                  "COB": 12.5,
                  "IOB": 1.75,
                  "predBGs": {
                    "ZT": [120, 119],
                    "IOB": [118, 115],
                    "COB": [118, 120],
                    "UAM": [121, 124]
                  }
                }
              }
            }
          ]
        }
        """

        let response = try decode(DeviceStatusResponse.self, json)
        let status = try XCTUnwrap(response.result.first)

        XCTAssertEqual(GlucoseSourceDevice.fromDS(status: status), .trio)

        let (device, extras) = await handleGSE(status)
        XCTAssertEqual(device, .trio)
        XCTAssertEqual(extras.cob, 12.5)
        XCTAssertEqual(extras.iob, 1.75)
        XCTAssertEqual(extras.eventualGlucose, 118)
        XCTAssertEqual(extras.glucoseTarget, 100)
        XCTAssertEqual(extras.reason, "COB: 12.5, IOB: 1.75")
        XCTAssertEqual(extras.forecasts.iob, [118, 115])
        XCTAssertEqual(extras.forecasts.zt, [120, 119])
        XCTAssertNotNil(extras.enactedAt)
    }

    func testIdentifiesEachSupportedAidSystem() throws {
        let cases: [(device: String, app: String?, expected: GlucoseSourceDevice)] = [
            ("Trio", "Trio", .trio),
            ("openaps://AndroidAPS", "AAPS", .aaps),
            ("openaps://pi", "openaps", .openaps),
            ("loop://iPhone", "loop", .loop),
            ("Some Other Uploader", nil, .unknown),
        ]

        for testCase in cases {
            let json = """
            {"status": 200, "result": [{"device": "\(testCase.device)", "app": \(testCase.app.map { "\"\($0)\"" } ?? "null")}]}
            """
            let response = try decode(DeviceStatusResponse.self, json)
            let status = try XCTUnwrap(response.result.first)

            XCTAssertEqual(
                GlucoseSourceDevice.fromDS(status: status),
                testCase.expected,
                "wrong device for \(testCase.device)"
            )
        }
    }

    // MARK: - Tandem pump logs

    func testDecodesPumpLogsResponse() throws {
        let json = """
        {
          "events": [
            {
              "deviceAssignmentId": "389e86df-7f91-44fe-a6f9-f884b223639f",
              "eventCode": 279,
              "sequenceGroup": 0,
              "sequenceNumber": 3289576,
              "pumpDateTime": "2026-07-05T06:02:46",
              "estimatedDateTime": "2026-07-05T10:03:40Z",
              "eventProperties": {
                "commandedRateSource": 3,
                "commandedRate": 290,
                "profileBasalRate": 290,
                "algorithmRate": 290,
                "tempRate": 65535
              }
            }
          ],
          "clockChanges": []
        }
        """

        let response = try decode(PumpLogsResponse.self, json)

        let event = try XCTUnwrap(response.events?.first)
        XCTAssertEqual(event.eventCode, 279)
        XCTAssertEqual(event.pumpDateTime, "2026-07-05T06:02:46")
        XCTAssertEqual(event.estimatedDateTime, "2026-07-05T10:03:40Z")

        // Rates arrive as milli-units; 65535 is the "no temp rate" marker and must
        // stay distinguishable from a real rate.
        XCTAssertEqual(event.eventProperties?["commandedRate"]?.doubleValue, 290)
        XCTAssertEqual(event.eventProperties?["tempRate"]?.intValue, 65535)
        XCTAssertEqual(event.eventProperties?["commandedRateSource"]?.intValue, 3)
    }

    /// `PumpLogProperty` is a heterogeneous bag: the same key can be a number, a
    /// string, a bool, an array or an object across pump models.
    func testDecodesHeterogeneousEventProperties() throws {
        let json = """
        {
          "events": [
            {
              "eventCode": 64,
              "eventProperties": {
                "carbAmount": 45,
                "bolusType": "Standard",
                "isExtended": false,
                "featuresBitmask": [],
                "nested": { "rate": 1.5 },
                "nothing": null
              }
            }
          ]
        }
        """

        let response = try decode(PumpLogsResponse.self, json)
        let props = try XCTUnwrap(response.events?.first?.eventProperties)

        XCTAssertEqual(props["carbAmount"]?.doubleValue, 45)
        XCTAssertEqual(props["bolusType"]?.stringValue, "Standard")
        XCTAssertEqual(props["isExtended"]?.boolValue, false)
        XCTAssertEqual(props["featuresBitmask"]?.arrayValue?.count, 0)
        XCTAssertEqual(props["nested"]?.dictionaryValue?["rate"]?.doubleValue, 1.5)
    }

    func testDecodesPumperInfoResponse() throws {
        let json = """
        {
          "firstName": "Ada",
          "lastName": "Lovelace",
          "name": "Ada Lovelace",
          "lowGlucoseThreshold": 70,
          "highGlucoseThreshold": 180,
          "pumps": [
            {
              "assignmentId": "389e86df-7f91-44fe-a6f9-f884b223639f",
              "serialNumber": "12345678",
              "modelName": "t:slim X2",
              "softwareVersion": "7.9.0.1",
              "algorithm": "Control-IQ",
              "lastUploadDate": "2026-07-05T10:03:40Z",
              "settings": {
                "id": "settings-1",
                "details": {
                  "dda": 300,
                  "maxBasalRate": 2.5,
                  "pumpId": "P-1"
                }
              }
            }
          ]
        }
        """

        let pumper = try decode(BffPumper.self, json)

        XCTAssertEqual(pumper.name, "Ada Lovelace")
        let pump = try XCTUnwrap(pumper.pumps?.first)
        XCTAssertEqual(pump.modelName, "t:slim X2")
        XCTAssertEqual(pump.algorithm, "Control-IQ")

        let details = try XCTUnwrap(pump.settings?.details)
        XCTAssertEqual(details.dda, 300)
        XCTAssertEqual(details.basalRate, 2.5)
        XCTAssertEqual(details.pumpId, "P-1")
        XCTAssertTrue(details.allKeys.contains("maxBasalRate"))
        // With no profile data the active insulin duration falls back to `dda`.
        XCTAssertEqual(details.activeProfileDiaMinutes, 300)
    }

    // MARK: - Formatting helpers

    func testFormatsIOBForDisplay() {
        XCTAssertEqual(formatIOBForDisplay(iob: 1.75), "1.8")
        XCTAssertEqual(formatIOBForDisplay(iob: -0.25), "-0.25")
    }

    func testFormatsCOBForDisplay() {
        XCTAssertEqual(formatCOBForDisplay(cob: 12.4), "12")
        XCTAssertEqual(formatCOBForDisplay(cob: 12.6), "13")
        XCTAssertEqual(formatCOBForDisplay(cob: 0), "0")
    }
}
