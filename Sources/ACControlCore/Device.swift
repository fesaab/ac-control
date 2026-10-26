import Foundation

public struct AccountDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let model: String?
    public let type: String
    public var isControllable: Bool { type == "DEVICE_AIR_CONDITIONER" }
    public var kindDescription: String {
        switch type {
        case "DEVICE_AIR_CONDITIONER": "Ar-condicionado"
        case "DEVICE_WASHER": "Lavadora"
        case "DEVICE_DRYER": "Secadora"
        case "DEVICE_REFRIGERATOR": "Geladeira"
        case "DEVICE_AIR_PURIFIER": "Purificador de ar"
        case "DEVICE_DISH_WASHER": "Lava-louças"
        case "DEVICE_ROBOT_CLEANER": "Robô aspirador"
        case "DEVICE_DEHUMIDIFIER": "Desumidificador"
        case "DEVICE_CEILING_FAN": "Ventilador"
        default: "Dispositivo LG"
        }
    }
    public var symbol: String {
        switch type {
        case "DEVICE_AIR_CONDITIONER": "snowflake"
        case "DEVICE_WASHER", "DEVICE_DRYER": "washer"
        case "DEVICE_REFRIGERATOR": "refrigerator"
        default: "house"
        }
    }
    public init?(json: JSONValue) {
        let info = json["deviceInfo"]
        guard let id = json["deviceId"].string, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.id = id
        self.type = info["deviceType"].string ?? "UNKNOWN"
        let alias = info["alias"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = alias.flatMap { $0.isEmpty ? nil : $0 } ?? "Dispositivo LG"
        self.model = info["modelName"].string
    }
}

public enum DeviceSelection: Equatable, Sendable {
    case selected(String)
    case needsSelection
    case unavailable
    case noSupportedDevices

    public static func resolve(devices: [AccountDevice], savedID: String?) -> Self {
        let supported = devices.filter(\.isControllable)
        // An explicit choice must never silently fall back to a different room.
        if let choice = savedID, !choice.isEmpty {
            return supported.contains(where: { $0.id == choice }) ? .selected(choice) : .unavailable
        }
        return supported.isEmpty ? .noSupportedDevices : .needsSelection
    }
}

public struct TemperatureRange: Equatable, Sendable {
    public let min: Double
    public let max: Double
    public let step: Double
    public let excluded: [Double]
    public init?(json: JSONValue) {
        guard let min = json["min"].number, let max = json["max"].number,
              min < max, max - min <= 100 else { return nil }
        let step = json["step"].number ?? 1
        guard step > 0, step <= max - min, (max - min) / step <= 10000 else { return nil }
        self.min = min; self.max = max; self.step = step
        self.excluded = json["except"].array?.compactMap(\.number) ?? []
    }
    public func contains(_ value: Double) -> Bool {
        guard value.isFinite, value >= min, value <= max, !excluded.contains(where: { abs($0 - value) < 0.00001 }) else { return false }
        let steps = (value - min) / step
        return abs(steps - steps.rounded()) < 0.00001
    }
    public func snapped(_ value: Double) -> Double {
        let count = Int(((max - min) / step).rounded(.down))
        let values = (0...count).map { min + Double($0) * step }.filter(contains)
        return values.min(by: { abs($0 - value) < abs($1 - value) }) ?? min
    }
}

public struct TemperatureControl: Equatable, Sendable {
    public let property: String
    public let range: TemperatureRange
    public func payload(value: Double) throws -> JSONValue {
        guard range.contains(value) else { throw ACError.unsupported("Temperatura fora dos valores permitidos pela LG.") }
        return .object(["temperatureInUnits": .object(["unit": .string("C"), property: .number(value)])])
    }
}

public struct ACProfile: Equatable, Sendable {
    private let property: JSONValue
    public init(json: JSONValue) throws {
        guard json["property"].object != nil else { throw ACError.invalidResponse }
        property = json["property"]
    }
    public var fanSpeedControl: FanSpeedControl? { FanSpeedControl(airFlow: property["airFlow"]) }
    private var power: JSONValue { property["operation"]["airConOperationMode"] }
    public var canSwitchPower: Bool {
        power["mode"].strings.contains("w") && ["POWER_ON", "POWER_OFF"].allSatisfy(power["value"]["w"].strings.contains)
    }
    public func powerPayload(on: Bool) throws -> JSONValue {
        guard canSwitchPower else { throw ACError.unsupported("Este perfil LG não permite ligar/desligar remotamente.") }
        return .object(["operation": .object(["airConOperationMode": .string(on ? "POWER_ON" : "POWER_OFF")])])
    }
    public func temperatureControl(jobMode: String?) -> TemperatureControl? {
        if ["FAN", "DRY", "AIR_CLEAN"].contains(jobMode ?? "") { return nil }
        guard let celsius = property["temperatureInUnits"].array?.first(where: { $0["unit"].string == "C" }) else { return nil }
        let modeProperty: String? = switch jobMode {
        case "COOL": "coolTargetTemperature"
        case "HEAT": "heatTargetTemperature"
        case "AUTO", "AI": "autoTargetTemperature"
        default: nil
        }
        let keys = [modeProperty, "targetTemperature"].compactMap { $0 }
        for key in keys {
            let prop = celsius[key]
            if prop["mode"].strings.contains("w"), prop["type"].string == "range",
               let range = TemperatureRange(json: prop["value"]["w"]) {
                return TemperatureControl(property: key, range: range)
            }
        }
        return nil
    }
}

public struct ACSnapshot: Equatable, Sendable {
    public let isOn: Bool
    public let target: Double?
    public let room: Double?
    public let jobMode: String?
    public let fanValues: JSONValue
    public let queriedAt: Date

    public init(json: JSONValue, queriedAt: Date = Date()) throws {
        let connection = json["connectionState"].string ?? json["deviceState"].string
        if ["OFFLINE", "DISCONNECTED"].contains(connection ?? "") { throw ACError.offline }
        switch json["operation"]["airConOperationMode"].string {
        case "POWER_ON": isOn = true
        case "POWER_OFF": isOn = false
        default: throw ACError.invalidResponse
        }
        jobMode = json["airConJobMode"]["currentJobMode"].string
        let celsius = json["temperatureInUnits"].array?.first { $0["unit"].string == "C" } ?? .null
        let modeKey: String = switch jobMode {
        case "COOL": "coolTargetTemperature"
        case "HEAT": "heatTargetTemperature"
        case "AUTO", "AI": "autoTargetTemperature"
        default: "targetTemperature"
        }
        target = celsius[modeKey].number ?? celsius["targetTemperature"].number
        room = celsius["currentTemperature"].number
        let airFlow = json["airFlow"]
        fanValues = .object(["windStrengthDetail": airFlow["windStrengthDetail"], "windStrength": airFlow["windStrength"], "windStep": airFlow["windStep"]])
        self.queriedAt = queriedAt
    }

    /// Query time is not the sensor's sampling time; the cloud can serve cached values.
    public func isStale(now: Date = Date(), interval: TimeInterval) -> Bool {
        now.timeIntervalSince(queriedAt) > max(180, interval * 3)
    }
    public func barTitle() -> String? {
        guard let room else { return nil }
        if isOn {
            guard let target else { return nil }
            return "\(temperatureLabel(target)) / \(temperatureLabel(room))"
        }
        return temperatureLabel(room)
    }
}

public func temperatureLabel(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1))) + "°"
}
