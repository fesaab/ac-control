import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        config.urlCache = nil
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ACError.invalidResponse }
        return (data, http)
    }
}

public struct ThinQClient: Sendable {
    public let configuration: LGConfiguration
    private let transport: any HTTPTransport
    // Published client key from LG's Apache-2.0 SDK; this is not the personal PAT.
    private let sdkClientKey = "v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3"

    public init(configuration: LGConfiguration, transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration; self.transport = transport
    }
    public func devices() async throws -> [AccountDevice] {
        let data = try await request(path: ["devices"])
        guard let list = data.array else { throw ACError.invalidResponse }
        var seen = Set<String>()
        return list.compactMap(AccountDevice.init).filter { seen.insert($0.id).inserted }
    }
    public func profile(id: String) async throws -> ACProfile {
        try ACProfile(json: await request(path: ["devices", id, "profile"]))
    }
    public func state(id: String) async throws -> ACSnapshot {
        try ACSnapshot(json: await request(path: ["devices", id, "state"]))
    }
    public func control(id: String, payload: JSONValue) async throws {
        _ = try await request(path: ["devices", id, "control"], payload: payload)
    }
    public func request(path: [String], payload: JSONValue? = nil) async throws -> JSONValue {
        var url = URL(string: "https://api-\(configuration.region.lowercased()).lgthinq.com")!
        for component in path { url.appendPathComponent(component) }
        var request = URLRequest(url: url)
        request.httpMethod = payload == nil ? "GET" : "POST"
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.country, forHTTPHeaderField: "x-country")
        request.setValue(configuration.clientID, forHTTPHeaderField: "x-client-id")
        var uuid = UUID().uuid
        let messageID = withUnsafeBytes(of: &uuid) { Data($0) }.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        request.setValue(messageID, forHTTPHeaderField: "x-message-id")
        request.setValue(sdkClientKey, forHTTPHeaderField: "x-api-key")
        request.setValue("OP", forHTTPHeaderField: "x-service-phase")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let payload {
            request.setValue("true", forHTTPHeaderField: "x-conditional-control")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
        }
        let (data, response) = try await transport.send(request)
        let body = try? JSONDecoder().decode(JSONValue.self, from: data)
        if let code = body?["error"]["code"].string {
            // Server text can contain device data. Only the error code is surfaced.
            let safeCode = code.count <= 12 && code.allSatisfy(\.isNumber) ? code : "desconhecido"
            throw ACError.api(safeCode)
        }
        guard (200..<300).contains(response.statusCode) else { throw ACError.http(response.statusCode) }
        if response.statusCode == 204, payload != nil { return .null }
        guard let body, body.object?["response"] != nil else { throw ACError.invalidResponse }
        return body["response"]
    }
}
