import Testing
import Foundation
@testable import ACControlCore

struct ConfigurationTests {
    @Test func testDotEnvIsDataAndPreservesQuotedTokens() {
        let values = DotEnv.parse("# header\nexport LG_THINQ_PAT='abc#123='\nLG_THINQ_COUNTRY=BR # note\nIGNORED\nCOMMAND=$(touch /tmp/never-executed)\n")
        expectEqual(values["LG_THINQ_PAT"], "abc#123=")
        expectEqual(values["LG_THINQ_COUNTRY"], "BR")
        expectEqual(values["COMMAND"], "$(touch /tmp/never-executed)")
    }
    @Test func testMissingTokenStopsBeforeAnyNetworkUse() {
        expectThrows(try LGConfiguration(values: [:], fallbackClientID: UUID().uuidString)) { expectEqual($0 as? ACError, .missingToken) }
    }
    @Test func testConfigurationUsesStableClientAndKnownLGRegionOnly() throws {
        let id = UUID().uuidString
        let configuration = try LGConfiguration(values: ["LG_THINQ_PAT": "test-only"], fallbackClientID: id)
        expectEqual(configuration.region, "AIC")
        expectEqual(configuration.country, "BR")
        expectEqual(configuration.clientID, id)
        expectThrows(try LGConfiguration(values: ["LG_THINQ_PAT":"test", "LG_THINQ_REGION":"evil.example"], fallbackClientID: id))
        expectThrows(try LGConfiguration(values: ["LG_THINQ_PAT":"test\r\nheader"], fallbackClientID: id))
    }
}
