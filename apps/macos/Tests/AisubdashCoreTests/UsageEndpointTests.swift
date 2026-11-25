import XCTest
@testable import AisubdashCore

final class UsageEndpointTests: XCTestCase {
    func testLocalOriginIsFixedToLoopback() {
        XCTAssertEqual(UsageEndpoint.local.origin.absoluteString, "http://127.0.0.1:6736")
        XCTAssertTrue(UsageEndpoint.local.isLocal)
    }

    func testAcceptsExistingTailnetIPv4AndServeHTTPS() {
        for url in ["http://100.64.0.1:6736", "http://100.127.255.254:6736",
                    "https://server.my-tailnet.ts.net:8443"] {
            XCTAssertNotNil(UsageEndpoint(tailscale: url), url)
            XCTAssertEqual(UsageEndpoint(tailscale: url)?.isLocal, false, url)
        }
    }

    func testRejectsNonTailnetOriginsAndURLComponents() {
        for url in ["http://127.0.0.1:6736", "http://100.63.255.255:6736",
                    "http://100.128.0.1:6736", "https://server.example.com",
                    "http://server.my-tailnet.ts.net",
                    "https://server.my-tailnet.ts.net.example.com",
                    "https://user:pass@server.my-tailnet.ts.net",
                    "https://server.my-tailnet.ts.net/api",
                    "http://100.64.0.1:6736?x=1",
                    "http://100.64.0.1:6736#fragment",
                    "http://100.64.0.1:0", "http://100.64.0.1:65536"] {
            XCTAssertNil(UsageEndpoint(tailscale: url), url)
        }
    }

    func testTrimsWhitespaceNormalizesTrailingRootSlashAndCase() {
        let ip = UsageEndpoint(tailscale: "  http://100.64.10.20:6736/ \n")
        XCTAssertEqual(ip?.origin.absoluteString, "http://100.64.10.20:6736")
        XCTAssertEqual(ip?.isLocal, false)

        let host = UsageEndpoint(tailscale: "\tHTTPS://Server.My-Tailnet.TS.NET:8443/\t")
        XCTAssertEqual(host?.origin.absoluteString, "https://server.my-tailnet.ts.net:8443")
        XCTAssertEqual(host?.isLocal, false)
    }

    func testRejectsMalformedPortsNonCanonicalIPv4AndShortTailnetHost() {
        for url in [
            "http://100.64.0.1:",
            "http://100.64.0.1:abc",
            "http://100.64.0.1:06736",
            "https://server.my-tailnet.ts.net:-1",
            "http://100.064.0.1:6736",
            "http://100.64.0.01:6736",
            "http://1681915905:6736",
            "http://100.64.0.1:6736//",
            "https://ts.net",
            "https://my-tailnet.ts.net",
        ] {
            XCTAssertNil(UsageEndpoint(tailscale: url), url)
        }
    }
}
