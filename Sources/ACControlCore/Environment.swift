import Foundation

public enum DotEnv {
    /// Reads data only: no shell evaluation, interpolation, or sourcing of this file.
    public static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard !line.hasPrefix("#"), let equal = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equal]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: equal)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            if let quote = value.first, ["\"", "'"].contains(String(quote)), value.count >= 2, value.last == quote {
                value = String(value.dropFirst().dropLast())
            } else if let comment = value.range(of: " #") { value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces) }
            result[key] = value
        }
        return result
    }
}

public struct LGConfiguration: Sendable {
    public let token: String
    public let country: String
    public let region: String
    public let clientID: String

    public init(values: [String: String], fallbackClientID: String) throws {
        let token = values["LG_THINQ_PAT", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ACError.missingToken }
        let country = values["LG_THINQ_COUNTRY", default: "BR"].uppercased()
        let region = values["LG_THINQ_REGION", default: "AIC"].uppercased()
        guard country.count == 2, country.allSatisfy({ $0.isASCII && $0.isLetter }), ["AIC", "EIC", "KIC"].contains(region) else {
            throw ACError.configuration("Confira LG_THINQ_COUNTRY e LG_THINQ_REGION no .env.")
        }
        self.token = token; self.country = country; self.region = region
        let suppliedID = values["LG_THINQ_CLIENT_ID", default: ""]
        self.clientID = suppliedID.isEmpty ? fallbackClientID : suppliedID
        guard UUID(uuidString: clientID) != nil else { throw ACError.configuration("LG_THINQ_CLIENT_ID precisa ser um UUID estável.") }
    }
}

public enum ACError: Error, LocalizedError, Equatable, Sendable {
    case missingToken, invalidResponse, noDevices, selectionRequired, offline
    case unsupported(String), configuration(String), api(String), http(Int)

    public var errorDescription: String? {
        switch self {
        case .missingToken: "Configure LG_THINQ_PAT no arquivo .env e recarregue as configurações."
        case .invalidResponse: "A LG retornou dados que não permitem confirmar o estado do aparelho."
        case .noDevices: "Nenhum ar-condicionado disponível nesta conta LG ThinQ Connect."
        case .selectionRequired: "Escolha o ar-condicionado em Configurações."
        case .offline: "Aparelho indisponível na LG. Confira Wi-Fi e energia."
        case .unsupported(let text), .configuration(let text): text
        case .http(let status): "Falha de comunicação com a LG (HTTP \(status))."
        case .api(let code):
            switch code {
            case "1103", "1218", "1302": "Token LG inválido ou revogado. Gere outro PAT e atualize o .env."
            case "1222": "Aparelho desconectado da LG. Confira Wi-Fi e energia."
            case "1306": "Limite da API LG atingido. O app aguardará antes de consultar novamente."
            case "1308", "1305", "1309": "PAT sem permissão para esta operação. Confira os três escopos do token."
            case "1219", "1220", "1221", "2101", "2201", "2202": "Modelo ou função indisponível no ThinQ Connect."
            case "2301", "2302", "2303", "2304", "2305": "Comando indisponível no estado ou modo atual do aparelho."
            default: "A LG não confirmou a operação (código \(code)). Atualize o estado antes de tentar novamente."
            }
        }
    }
}
