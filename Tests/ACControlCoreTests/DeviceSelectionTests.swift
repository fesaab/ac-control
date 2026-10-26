import Foundation
import Testing
@testable import ACControlCore

struct DeviceSelectionTests {
    private func device(_ id: String, type: String = "DEVICE_AIR_CONDITIONER", name: String = "Quarto") throws -> AccountDevice {
        try requireValue(AccountDevice(json: .decode("{\"deviceId\":\"\(id)\",\"deviceInfo\":{\"deviceType\":\"\(type)\",\"alias\":\"\(name)\"}}")))
    }
    @Test func firstRunRequiresScreenSelectionEvenWithOnlyOneAC() throws {
        expectEqual(DeviceSelection.resolve(devices: [try device("ac-1")], savedID: nil), .needsSelection)
    }
    @Test func savedChoiceIsRestoredAmongMultipleACsAndOtherDevices() throws {
        let devices = try [device("ac-1"), device("ac-2", name: "Escritório"), device("washer", type: "DEVICE_WASHER")]
        expectEqual(DeviceSelection.resolve(devices: devices, savedID: "ac-2"), .selected("ac-2"))
    }
    @Test func duplicateAliasesAreSelectedByID() throws {
        let devices = try [device("ac-1"), device("ac-2")]
        expectEqual(DeviceSelection.resolve(devices: devices, savedID: "ac-2"), .selected("ac-2"))
    }
    @Test func removedDeviceCannotSilentlySwitchToAnotherRoom() throws {
        expectEqual(DeviceSelection.resolve(devices: [try device("other-room")], savedID: "removed-ac"), .unavailable)
    }
    @Test func unsupportedDeviceCannotBecomeControlTarget() throws {
        let devices = try [device("ac-1"), device("washer", type: "DEVICE_WASHER")]
        expectEqual(DeviceSelection.resolve(devices: devices, savedID: "washer"), .unavailable)
    }
    @Test func accountWithNoACRetainsDevicesButCannotEnableControls() throws {
        let devices = try [device("washer", type: "DEVICE_WASHER"), device("unknown", type: "NEW_LG_DEVICE")]
        expectEqual(devices.count, 2)
        expectEqual(DeviceSelection.resolve(devices: devices, savedID: nil), .noSupportedDevices)
        expectFalse(devices[1].isControllable)
    }
    @Test func missingAliasAndUnknownTypeStillAppearButMissingIDIsRejected() throws {
        let device = try requireValue(AccountDevice(json: .decode(#"{"deviceId":"unknown-id","deviceInfo":{"alias":"   "}}"#)))
        expectEqual(device.name, "Dispositivo LG")
        expectFalse(device.isControllable)
        expectNil(AccountDevice(json: try .decode(#"{"deviceId":" ","deviceInfo":{"deviceType":"DEVICE_AIR_CONDITIONER"}}"#)))
    }
}
