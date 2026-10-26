import Testing
import Foundation
@testable import ACControlCore

let fixtureProfile = #"""
{"property":{
 "operation":{"airConOperationMode":{"mode":["r","w"],"type":"enum","value":{"r":["POWER_ON","POWER_OFF"],"w":["POWER_ON","POWER_OFF"]}}},
 "temperatureInUnits":[
 {"unit":"F","targetTemperature":{"mode":["r","w"],"type":"range","value":{"w":{"min":64,"max":86,"step":1}}}},
 {"unit":"C","currentTemperature":{"mode":["r"],"type":"range","value":{"r":{"min":0,"max":50,"step":0.5}}},
 "targetTemperature":{"mode":["r","w"],"type":"range","value":{"w":{"min":18,"max":30,"step":1}}},
 "coolTargetTemperature":{"mode":["r","w"],"type":"range","value":{"w":{"min":19,"max":29,"step":0.5,"except":[20.5]}}}}
 ]}}
"""#

func fixtureState(on: Bool = true, room: String = "26", target: String = "22", job: String = "COOL") throws -> ACSnapshot {
    try ACSnapshot(json: .decode("{\"operation\":{\"airConOperationMode\":\"\(on ? "POWER_ON" : "POWER_OFF")\"},\"airConJobMode\":{\"currentJobMode\":\"\(job)\"},\"temperatureInUnits\":[{\"unit\":\"F\",\"currentTemperature\":78,\"targetTemperature\":71},{\"unit\":\"C\",\"targetTemperature\":\(target),\"currentTemperature\":\(room)}]}"))
}

struct DeviceTests {
    @Test func testProfileUsesCelsiusWriteBoundsAndModeSpecificProperty() throws {
        let profile = try ACProfile(json: .decode(fixtureProfile))
        let control = try requireValue(profile.temperatureControl(jobMode: "COOL"))
        expectEqual(control.property, "coolTargetTemperature")
        expectEqual(control.range.min, 19)
        expectEqual(control.range.max, 29)
        expectEqual(control.range.step, 0.5)
        expectFalse(control.range.contains(20.5))
        expectFalse(control.range.contains(20.2))
        expectFalse(control.range.contains(30))
        expectTrue(control.range.contains(21.5))
        expectTrue(control.range.contains(control.range.snapped(20.5)))
    }
    @Test func testDoesNotGuessWriteCapabilitiesOrChangeMode() throws {
        let readOnly = try ACProfile(json: .decode(#"{"property":{"temperatureInUnits":[{"unit":"C","targetTemperature":{"mode":["r"],"type":"range","value":{"r":{"min":18,"max":30,"step":1}}}}]}}"#))
        expectNil(readOnly.temperatureControl(jobMode: "COOL"))
        expectFalse(readOnly.canSwitchPower)
        expectThrows(try readOnly.powerPayload(on: true))
        let profile = try ACProfile(json: .decode(fixtureProfile))
        expectNil(profile.temperatureControl(jobMode: "FAN"))
        expectNil(profile.temperatureControl(jobMode: "DRY"))
    }
    @Test func testPowerOnlyChangesOperationPreservingExistingTemperatureAndMode() throws {
        let profile = try ACProfile(json: .decode(fixtureProfile))
        expectEqual(try profile.powerPayload(on: true), try .decode(#"{"operation":{"airConOperationMode":"POWER_ON"}}"#))
        expectEqual(try profile.powerPayload(on: false), try .decode(#"{"operation":{"airConOperationMode":"POWER_OFF"}}"#))
    }
    @Test func testTemperaturePayloadContainsCelsiusAndNoOtherSettings() throws {
        let profile = try ACProfile(json: .decode(fixtureProfile))
        let control = try requireValue(profile.temperatureControl(jobMode: "COOL"))
        expectEqual(try control.payload(value: 23.5), try .decode(#"{"temperatureInUnits":{"unit":"C","coolTargetTemperature":23.5}}"#))
        expectThrows(try control.payload(value: 18))
        expectThrows(try control.payload(value: 20.5))
    }
    @Test func testBarShowsBothWhenOnOnlyRoomWhenOffAndNoInventedReading() throws {
        expectEqual(try fixtureState().barTitle(), "22° / 26°")
        expectEqual(try fixtureState(on: false).barTitle(), "26°")
        expectNil(try fixtureState(room: "null").barTitle())
        expectNil(try fixtureState(target: "null").barTitle())
        expectEqual(try fixtureState(on: false, target: "null").barTitle(), "26°")
    }
    @Test func testUnknownPowerOrOfflineIsNotTreatedAsOff() throws {
        expectThrows(try ACSnapshot(json: .decode(#"{"operation":{"airConOperationMode":"UNKNOWN"}}"#)))
        expectThrows(try ACSnapshot(json: .decode(#"{"connectionState":"OFFLINE","operation":{"airConOperationMode":"POWER_OFF"}}"#)))
    }
    @Test func testMissingSensorAndFahrenheitDoNotProduceFictitiousCelsius() throws {
        let value = try fixtureState(room: "null")
        expectNil(value.room)
        expectEqual(value.target, 22)
        let onlyF = try ACSnapshot(json: .decode(#"{"operation":{"airConOperationMode":"POWER_ON"},"temperatureInUnits":[{"unit":"F","currentTemperature":78}]}"#))
        expectNil(onlyF.room)
    }
    @Test func testQueryAgeInvalidatesOldDataAfterSleep() throws {
        let value = try fixtureState()
        expectFalse(value.isStale(now: value.queriedAt.addingTimeInterval(179), interval: 60))
        expectTrue(value.isStale(now: value.queriedAt.addingTimeInterval(181), interval: 60))
    }
    @Test func testInvalidRangesCannotEnableSlider() throws {
        for text in [#"{"min":30,"max":18}"#, #"{"min":18,"max":30,"step":0}"#, #"{"min":18,"max":30,"step":-1}"#] {
            expectNil(TemperatureRange(json: try .decode(text)))
        }
    }
    @Test func testDeviceDiscoveryIncludesOtherAppliancesForIdentification() throws {
        expectNotNil(AccountDevice(json: try .decode(#"{"deviceId":"ac-1","deviceInfo":{"deviceType":"DEVICE_AIR_CONDITIONER","alias":"Quarto"}}"#)))
        let washer = try requireValue(AccountDevice(json: try .decode(#"{"deviceId":"washer","deviceInfo":{"deviceType":"DEVICE_WASHER"}}"#)))
        expectFalse(washer.isControllable)
    }
}
