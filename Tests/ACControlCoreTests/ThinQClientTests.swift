import Foundation
import Testing
@testable import ACControlCore

actor FixtureTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let status: Int
    let body: String
    let shouldTimeout: Bool
    init(status: Int = 200, body: String = #"{"response":null}"#, shouldTimeout: Bool = false) {
        self.status = status; self.body = body; self.shouldTimeout = shouldTimeout
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if shouldTimeout { throw URLError(.timedOut) }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func captured() -> [URLRequest] { requests }
}

struct ThinQClientTests {
    func client(_ transport: FixtureTransport) throws -> ThinQClient {
        try ThinQClient(configuration: LGConfiguration(values: ["LG_THINQ_PAT":"fake-test-token"], fallbackClientID:"11111111-2222-4333-8444-555555555555"), transport: transport)
    }
    @Test func testControlContractUsesOfficialHeadersBodyAndOneRequest() async throws {
        let transport = FixtureTransport()
        let client = try client(transport)
        let profile = try ACProfile(json: .decode(fixtureProfile))
        try await client.control(id: "ac-1", payload: profile.powerPayload(on: true))
        let requests = await transport.captured()
        let req = try requireValue(requests.first)
        expectEqual(requests.count, 1)
        expectEqual(req.url?.absoluteString, "https://api-aic.lgthinq.com/devices/ac-1/control")
        expectEqual(req.httpMethod, "POST")
        expectEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer fake-test-token")
        expectEqual(req.value(forHTTPHeaderField: "x-country"), "BR")
        expectEqual(req.value(forHTTPHeaderField: "x-service-phase"), "OP")
        expectEqual(req.value(forHTTPHeaderField: "x-conditional-control"), "true")
        expectEqual(req.value(forHTTPHeaderField: "x-message-id")?.count, 22)
        expectEqual(try JSONDecoder().decode(JSONValue.self, from: requireValue(req.httpBody)), try profile.powerPayload(on: true))
    }
    @Test func testTimeoutNeverRetriesControlWrite() async throws {
        let transport = FixtureTransport(shouldTimeout: true)
        do {
            try await client(transport).control(id: "ac-1", payload: .object([:]))
            fail("Expected timeout")
        } catch { expectEqual((error as? URLError)?.code, .timedOut) }
        let requests = await transport.captured()
        expectEqual(requests.count, 1)
    }
    @Test func testAPIErrorCodeDoesNotExposeServerMessageOrPersonalData() async throws {
        let transport = FixtureTransport(status: 401, body: #"{"error":{"code":"1103","message":"sensitive-device-and-token"}}"#)
        do {
            _ = try await client(transport).devices()
            fail("Expected auth error")
        } catch {
            expectEqual(error as? ACError, .api("1103"))
            expectFalse(error.localizedDescription.contains("sensitive"))
        }
    }
    @Test func testMalformedSuccessCannotBecomeEmptyHealthyState() async throws {
        let transport = FixtureTransport(body: #"{"unexpected":true}"#)
        do { _ = try await client(transport).devices(); fail("Expected invalid response") }
        catch { expectEqual(error as? ACError, .invalidResponse) }
    }
    @Test func testDevicesUsesResponseEnvelopeAndGETWithoutControlHeader() async throws {
        let transport = FixtureTransport(body: #"{"response":[{"deviceId":"ac-1","deviceInfo":{"deviceType":"DEVICE_AIR_CONDITIONER","alias":"Quarto"}}]}"#)
        let devices = try await client(transport).devices()
        expectEqual(devices.map(\.name), ["Quarto"])
        let requests = await transport.captured()
        expectEqual(requests.first?.httpMethod, "GET")
        expectNil(requests.first?.value(forHTTPHeaderField: "x-conditional-control"))
    }
    @Test func accountDiscoveryRetainsAllTypesAndDeduplicatesDeviceIDs() async throws {
        let transport = FixtureTransport(body: #"{"response":[{"deviceId":"ac-1","deviceInfo":{"deviceType":"DEVICE_AIR_CONDITIONER","alias":"Quarto"}},{"deviceId":"washer","deviceInfo":{"deviceType":"DEVICE_WASHER","alias":"Lavanderia"}},{"deviceId":"ac-2","deviceInfo":{"deviceType":"DEVICE_AIR_CONDITIONER","alias":"Escritório"}},{"deviceId":"washer","deviceInfo":{"deviceType":"DEVICE_WASHER"}}]}"#)
        let devices = try await client(transport).devices()
        expectEqual(devices.map(\.id), ["ac-1", "washer", "ac-2"])
        expectEqual(devices.filter(\.isControllable).map(\.id), ["ac-1", "ac-2"])
        let requests = await transport.captured()
        expectEqual(requests.count, 1)
        expectEqual(requests.first?.url?.path, "/devices")
        expectEqual(requests.first?.httpMethod, "GET")
    }

}
