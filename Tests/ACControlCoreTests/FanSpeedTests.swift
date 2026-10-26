import Foundation
import Testing
@testable import ACControlCore

func fanProfile(_ flow: String) throws -> ACProfile {
    try ACProfile(json: .object(["property": .object(["airFlow": try .decode(flow)])]))
}
func fanSnapshot(_ flow: String) throws -> ACSnapshot {
    try ACSnapshot(json: .object([
        "operation": .object(["airConOperationMode": .string("POWER_ON")]),
        "airConJobMode": .object(["currentJobMode": .string("COOL")]),
        "airFlow": try .decode(flow),
        "temperatureInUnits": .array([.object(["unit": .string("C"), "targetTemperature": .number(22), "currentTemperature": .number(26)])])
    ]))
}

struct FanSpeedTests {
    @Test func detailedEnumUsesOnlyWritableOptionsAndPreservesRawTokens() throws {
        let profile = try fanProfile(#"{"windStrengthDetail":{"type":"enum","mode":["r","w"],"value":{"r":["AUTO","LOW","HIGH"],"w":["LOW","HIGH","HIGH"]}}}"#)
        let control = try requireValue(profile.fanSpeedControl)
        expectEqual(control.property, "windStrengthDetail")
        expectEqual(control.options.map(\.id), ["enum:LOW", "enum:HIGH"])
        expectEqual(control.options.map(\.title), ["Baixa", "Alta"])
        expectThrows(try control.payload(optionID: "enum:AUTO"))
    }
    @Test func detailedPropertyTakesPrecedenceOverCoarseEnum() throws {
        let profile = try fanProfile(#"{"windStrengthDetail":{"type":"enum","mode":["w"],"value":{"w":["AUTO","LOW_MID"]}},"windStrength":{"type":"enum","mode":["w"],"value":{"w":["LOW","HIGH"]}}}"#)
        expectEqual(profile.fanSpeedControl?.property, "windStrengthDetail")
        expectEqual(profile.fanSpeedControl?.options.map(\.title), ["Automático", "Baixa / média"])
    }
    @Test func fallsBackToLegacyWritableFieldWhenDetailedFieldIsReadOnly() throws {
        let profile = try fanProfile(#"{"windStrengthDetail":{"type":"enum","mode":["r"],"value":{"r":["AUTO","LOW"]}},"windStrength":{"type":"enum","mode":["r","w"],"value":{"w":["LOW","MID","HIGH"]}}}"#)
        let control = try requireValue(profile.fanSpeedControl)
        expectEqual(control.property, "windStrength")
        expectEqual(try control.payload(optionID: "enum:MID"), try .decode(#"{"airFlow":{"windStrength":"MID"}}"#))
    }
    @Test func absentOrReadOnlyCapabilitiesDoNotEnableFanControl() throws {
        for flow in [#"{}"#, #"{"windStrength":{"type":"enum","mode":["r"],"value":{"r":["AUTO","LOW"]}}}"#, #"{"windStrength":{"type":"enum","mode":["w"],"value":{"w":[]}}}"#] {
            expectNil(try fanProfile(flow).fanSpeedControl)
        }
    }
    @Test func numericLevelsRespectBoundsStepAndExceptionsAndRemainNumbers() throws {
        let profile = try fanProfile(#"{"windStep":{"type":"range","mode":["r","w"],"value":{"w":{"min":1,"max":6,"step":2,"except":[3]}}}}"#)
        let control = try requireValue(profile.fanSpeedControl)
        expectEqual(control.property, "windStep")
        expectEqual(control.options.map(\.id), ["step:1", "step:5"])
        expectEqual(control.options.map(\.title), ["Nível 1", "Nível 5"])
        expectEqual(try control.payload(optionID: "step:5"), try .decode(#"{"airFlow":{"windStep":5}}"#))
        expectThrows(try control.payload(optionID: "step:3"))
        expectThrows(try control.payload(optionID: "enum:5"))
    }
    @Test func invalidNumericRangesCannotCrashOrEnableWrites() throws {
        for range in [#"{"min":6,"max":1}"#, #"{"min":1,"max":6,"step":0}"#, #"{"min":1,"max":6,"step":1.5}"#, #"{"min":1,"max":6,"step":1e100}"#, #"{"min":-1,"max":6}"#] {
            expectNil(try fanProfile("{\"windStep\":{\"type\":\"range\",\"mode\":[\"w\"],\"value\":{\"w\":\(range)}}}").fanSpeedControl)
        }
    }
    @Test func confirmationReadsTheExactControlledProperty() throws {
        let control = try requireValue(fanProfile(#"{"windStrengthDetail":{"type":"enum","mode":["r","w"],"value":{"w":["AUTO","HIGH"]}}}"#).fanSpeedControl)
        let wrongField = try fanSnapshot(#"{"windStrength":"HIGH"}"#)
        expectFalse(control.isConfirmed(optionID: "enum:HIGH", snapshot: wrongField))
        let exact = try fanSnapshot(#"{"windStrengthDetail":"HIGH","windStrength":"LOW"}"#)
        expectTrue(control.isConfirmed(optionID: "enum:HIGH", snapshot: exact))
        expectEqual(control.currentOption(in: exact)?.title, "Alta")
        expectFalse(control.isConfirmed(optionID: "enum:INVALID", snapshot: exact))
    }
    @Test func missingOrUnknownStateDoesNotInventAutomaticFanSpeed() throws {
        let control = try requireValue(fanProfile(#"{"windStrength":{"type":"enum","mode":["r","w"],"value":{"w":["AUTO","LOW"]}}}"#).fanSpeedControl)
        expectNil(control.currentOption(in: try fanSnapshot(#"{}"#)))
        expectNil(control.currentOption(in: try fanSnapshot(#"{"windStrength":"UNKNOWN"}"#)))
    }
    @Test func fanPayloadPreservesTemperatureModeAndPower() throws {
        let control = try requireValue(fanProfile(#"{"windStrengthDetail":{"type":"enum","mode":["r","w"],"value":{"w":["AUTO","HIGH"]}}}"#).fanSpeedControl)
        let payload = try control.payload(optionID: "enum:HIGH")
        expectEqual(payload, try .decode(#"{"airFlow":{"windStrengthDetail":"HIGH"}}"#))
        expectNil(payload.object?["operation"])
        expectNil(payload.object?["airConJobMode"])
        expectNil(payload.object?["temperatureInUnits"])
    }
    @Test func integerStepZeroIsNotMislabelledAsAutomatic() throws {
        let control = try requireValue(fanProfile(#"{"windStep":{"type":"range","mode":["w"],"value":{"w":{"min":0,"max":2,"step":1}}}}"#).fanSpeedControl)
        expectEqual(control.options.first?.title, "Nível 0")
        expectFalse(control.options.contains(where: { $0.title == "Automático" }))
    }
    @Test func fanWriteUsesSingleOfficialRequestAndOnlyAirFlowPayload() async throws {
        let transport = FixtureTransport()
        let configuration = try LGConfiguration(values: ["LG_THINQ_PAT":"fan-test-token"], fallbackClientID: UUID().uuidString)
        let client = ThinQClient(configuration: configuration, transport: transport)
        let control = try requireValue(fanProfile(#"{"windStrength":{"type":"enum","mode":["w"],"value":{"w":["AUTO","LOW"]}}}"#).fanSpeedControl)
        try await client.control(id: "ac-selected", payload: control.payload(optionID: "enum:LOW"))
        let requests = await transport.captured()
        expectEqual(requests.count, 1)
        let request = try requireValue(requests.first)
        expectEqual(request.url?.path, "/devices/ac-selected/control")
        expectEqual(request.httpMethod, "POST")
        expectEqual(try JSONDecoder().decode(JSONValue.self, from: requireValue(request.httpBody)), try .decode(#"{"airFlow":{"windStrength":"LOW"}}"#))
    }
}
