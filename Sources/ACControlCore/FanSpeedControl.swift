import Foundation

public struct FanSpeedOption: Identifiable, Equatable, Sendable {
    public let value: JSONValue
    public var id: String {
        if let code = value.string { return "enum:" + code }
        return "step:" + String(Int(value.number ?? 0))
    }
    public var title: String {
        if let step = value.number { return "Nível " + String(Int(step)) }
        guard let code = value.string else { return "Não informado" }
        switch code.uppercased() {
        case "AUTO": return "Automático"
        case "SLOW", "LOWEST", "VERY_LOW": return "Muito baixa"
        case "SLOW_LOW": return "Muito baixa / baixa"
        case "LOW": return "Baixa"
        case "LOW_MID", "LOW_MEDIUM": return "Baixa / média"
        case "MID", "MEDIUM": return "Média"
        case "MID_HIGH", "MEDIUM_HIGH": return "Média / alta"
        case "HIGH": return "Alta"
        case "POWER", "TURBO": return "Turbo"
        case "NATURE", "NATURAL": return "Natural"
        default:
            if code.hasPrefix("STEP_"), let step = Int(code.dropFirst(5)) { return "Nível \(step)" }
            return code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

public struct FanSpeedControl: Equatable, Sendable {
    public let property: String
    public let options: [FanSpeedOption]

    init?(airFlow: JSONValue) {
        // Prefer the detailed enum when writable. Never invent values from a generic preset list.
        for key in ["windStrengthDetail", "windStrength"] {
            let definition = airFlow[key]
            guard definition["mode"].strings.contains("w"), definition["type"].string == "enum" else { continue }
            let values = definition["value"]["w"].strings.filter { code in
                !code.isEmpty && code.count <= 80 && !code.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            }
            var seen = Set<String>()
            let unique = values.filter { seen.insert($0).inserted }
            if !unique.isEmpty, unique.count <= 128 {
                property = key
                options = unique.map { FanSpeedOption(value: .string($0)) }
                return
            }
        }
        let definition = airFlow["windStep"]
        let range = definition["value"]["w"]
        guard definition["mode"].strings.contains("w"), definition["type"].string == "range",
              let min = range["min"].number, let max = range["max"].number,
              min >= 0, max <= 1000, min <= max, min.rounded() == min, max.rounded() == max else { return nil }
        let step = range["step"].number ?? 1
        guard step >= 1, step <= 1000, step.rounded() == step else { return nil }
        let excluded = range["except"].array?.compactMap(\.number) ?? []
        let values = stride(from: Int(min), through: Int(max), by: Int(step)).filter { !excluded.contains(Double($0)) }
        guard !values.isEmpty, values.count <= 128 else { return nil }
        property = "windStep"
        options = values.map { FanSpeedOption(value: .number(Double($0))) }
    }

    public func currentOption(in snapshot: ACSnapshot) -> FanSpeedOption? {
        options.first { $0.value == snapshot.fanValues[property] }
    }
    public func payload(optionID: String) throws -> JSONValue {
        guard let option = options.first(where: { $0.id == optionID }) else {
            throw ACError.unsupported("Velocidade do ventilador não permitida pelo aparelho.")
        }
        return .object(["airFlow": .object([property: option.value])])
    }
    public func isConfirmed(optionID: String, snapshot: ACSnapshot) -> Bool {
        guard let option = options.first(where: { $0.id == optionID }) else { return false }
        return snapshot.fanValues[property] == option.value
    }
}
