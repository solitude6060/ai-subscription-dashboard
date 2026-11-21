import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import AisubdashCore

final class UsageContractTests: XCTestCase {
    func testReadAndRefreshUseTheirOwnBoundedSessionTimeouts() {
        for timeout: TimeInterval in [12, 120] {
            let session = URLSessionUsageTransport.makeConfiguration(timeout: timeout)
            XCTAssertEqual(session.timeoutIntervalForRequest, timeout)
            XCTAssertEqual(session.timeoutIntervalForResource, timeout)
            let settings = session.connectionProxyDictionary ?? [:]
            for key in ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable"] {
                XCTAssertEqual(settings[key] as? Int, 0, key)
            }
        }
    }

    func testDecodesEnabledProvidersJoinsExactIDsAndPreservesZeroAndDates() throws {
        let providersJSON = Data("""
        [
          {
            "providerId": "codex",
            "name": "Codex",
            "enabled": true,
            "lastRefreshAt": "2026-11-22T02:59:00Z",
            "lastError": null
          },
          {
            "providerId": "codex:work",
            "name": "Codex Work",
            "enabled": true,
            "lastRefreshAt": "2026-11-22T03:00:00.500Z",
            "lastError": "secret internal stack trace"
          },
          {
            "providerId": "disabled-provider",
            "name": "Disabled",
            "enabled": false,
            "lastError": null
          },
          {
            "providerId": "minimax",
            "name": "MiniMax",
            "enabled": true
          }
        ]
        """.utf8)

        let snapshotsJSON = Data("""
        [
          {
            "providerId": "codex",
            "startedAt": "2026-11-22T02:30:00.123Z",
            "raw": {
              "lines": [
                {
                  "type": "progress",
                  "label": "5h",
                  "used": 0,
                  "limit": 100,
                  "format": {
                    "kind": "percent"
                  },
                  "resetsAt": "2026-11-22T07:30:00Z"
                },
                {
                  "type": "progress",
                  "label": "Credits",
                  "used": 12.5,
                  "limit": 50,
                  "format": {
                    "kind": "usd"
                  }
                },
                {
                  "type": "progress",
                  "label": "Broken",
                  "used": "not-a-number"
                },
                {
                  "type": "badge",
                  "label": "Plan",
                  "text": "Pro"
                }
              ]
            }
          },
          {
            "providerId": "disabled-provider",
            "startedAt": "2026-11-22T02:30:00Z",
            "raw": {
              "lines": [
                {
                  "type": "progress",
                  "label": "5h",
                  "used": 50,
                  "limit": 100,
                  "format": {
                    "kind": "percent"
                  }
                }
              ]
            }
          },
          {
            "providerId": "minimax",
            "startedAt": "2026-11-22T02:45:00Z",
            "raw": {
              "quota": {
                "label": "Coding Plan",
                "used": 0,
                "limit": 300,
                "suffix": "prompts",
                "resetsAt": "2026-11-22T08:00:00.000Z",
                "format": "count"
              }
            }
          }
        ]
        """.utf8)

        let dashboard: UsageDashboard = try UsageContractDecoder.decode(
            providersData: providersJSON,
            snapshotsData: snapshotsJSON
        )

        XCTAssertEqual(dashboard.accounts.map(\.id), ["codex", "codex:work", "minimax"])

        let codex = dashboard.accounts[0]
        XCTAssertEqual(codex.name, "Codex")
        XCTAssertFalse(codex.refreshFailed)
        XCTAssertNotNil(codex.observedAt)
        XCTAssertEqual(codex.quotas.count, 2)
        XCTAssertEqual(codex.quotas[0].label, "5h")
        XCTAssertEqual(codex.quotas[0].used, 0)
        XCTAssertEqual(codex.quotas[0].limit, 100)
        XCTAssertEqual(codex.quotas[0].format, .percent)
        XCTAssertNotNil(codex.quotas[0].resetsAt)
        XCTAssertEqual(codex.quotas[1].label, "Credits")
        XCTAssertEqual(codex.quotas[1].used, 12.5)
        XCTAssertEqual(codex.quotas[1].limit, 50)
        XCTAssertEqual(codex.quotas[1].format, .usd)

        let codexWork = dashboard.accounts[1]
        XCTAssertTrue(codexWork.refreshFailed)
        XCTAssertNil(codexWork.observedAt)
        XCTAssertTrue(codexWork.quotas.isEmpty)

        let minimax = dashboard.accounts[2]
        XCTAssertFalse(minimax.refreshFailed)
        XCTAssertNotNil(minimax.observedAt)
        XCTAssertEqual(minimax.quotas.count, 1)
        XCTAssertEqual(minimax.quotas[0].used, 0)
        XCTAssertEqual(minimax.quotas[0].limit, 300)
        XCTAssertEqual(minimax.quotas[0].format, .count(suffix: "prompts"))
        XCTAssertNotNil(minimax.quotas[0].resetsAt)

        let secondDecode = try UsageContractDecoder.decode(
            providersData: providersJSON,
            snapshotsData: snapshotsJSON
        )
        XCTAssertEqual(dashboard.accounts.map(\.quotas), secondDecode.accounts.map(\.quotas))
    }

    func testMixedSnapshotsDisabledProvidersAndZeroVersusMissing() throws {
        let providersJSON = Data("""
        [
          {
            "providerId": "claude",
            "name": "Claude",
            "enabled": true,
            "lastError": ""
          },
          {
            "providerId": "claude:personal",
            "name": "Claude Personal",
            "enabled": true
          },
          {
            "providerId": "cursor",
            "name": "Cursor",
            "enabled": false
          }
        ]
        """.utf8)

        let snapshotsJSON = Data("""
        [
          {
            "providerId": "claude",
            "startedAt": "2026-11-22T03:00:00Z",
            "raw": {
              "lines": [
                {
                  "type": "progress",
                  "label": "Session",
                  "used": 0,
                  "limit": 100,
                  "format": {
                    "kind": "percent"
                  }
                }
              ]
            }
          },
          {
            "providerId": "cursor",
            "startedAt": "2026-11-22T03:00:00Z",
            "raw": {
              "lines": [
                {
                  "type": "progress",
                  "label": "Fast",
                  "used": 10,
                  "limit": 500,
                  "format": {
                    "kind": "count",
                    "suffix": "requests"
                  }
                }
              ]
            }
          },
          {
            "providerId": "orphan",
            "startedAt": "2026-11-22T03:00:00Z",
            "raw": {
              "lines": []
            }
          }
        ]
        """.utf8)

        let dashboard = try UsageContractDecoder.decode(
            providersData: providersJSON,
            snapshotsData: snapshotsJSON
        )

        XCTAssertEqual(dashboard.accounts.map(\.id), ["claude", "claude:personal"])
        XCTAssertFalse(dashboard.accounts[0].refreshFailed)
        XCTAssertEqual(dashboard.accounts[0].quotas.first?.used, 0)
        XCTAssertNotNil(dashboard.accounts[0].observedAt)

        // Missing snapshot must not invent a zero quota or observation timestamp.
        XCTAssertTrue(dashboard.accounts[1].quotas.isEmpty)
        XCTAssertNil(dashboard.accounts[1].observedAt)
    }

    func testDecodesUsageAsEmittedByTheBunAPI() throws {
        let providers = Data("""
        [
          {
            "providerId": "codex:work",
            "name": "Codex Work",
            "enabled": true
          },
          {
            "providerId": "minimax",
            "name": "MiniMax",
            "enabled": true
          }
        ]
        """.utf8)
        let snapshots = Data("""
        [
          {
            "id": "snapshot-1",
            "providerId": "codex:work",
            "startedAt": "2026-11-22T02:30:00.123Z",
            "tool": "OpenUsage Plugin Snapshot",
            "source": "api",
            "raw": {
              "lines": [
                {
                  "type": "progress",
                  "label": "Session",
                  "used": "0",
                  "limit": "100"
                },
                {
                  "type": "progress",
                  "label": "Weekly",
                  "used": 25,
                  "limit": 100,
                  "format": {
                    "kind": "percent"
                  }
                },
                {
                  "type": "progress",
                  "label": "Weekly",
                  "used": 40,
                  "limit": 100,
                  "format": {
                    "kind": "percent"
                  }
                },
                {
                  "type": "progress",
                  "label": "Weekly#2",
                  "used": 5,
                  "limit": 100
                },
                {
                  "type": "progress",
                  "label": "Invalid",
                  "used": 3,
                  "limit": 0
                }
              ]
            }
          },
          {
            "id": "snapshot-2",
            "providerId": "minimax",
            "startedAt": "2026-11-22T02:30:00Z",
            "raw": {
              "quota": {
                "used": 2,
                "limit": 100,
                "format": "count",
                "suffix": "prompts"
              }
            }
          }
        ]
        """.utf8)
        let accounts = try UsageContractDecoder.decode(
            providersData: providers, snapshotsData: snapshots
        ).accounts

        let quotas = accounts[0].quotas
        XCTAssertEqual(quotas.map(\.used), [0, 25, 40, 5])
        XCTAssertEqual(quotas.first?.format, .percent)
        XCTAssertEqual(Set(quotas.map(\.id)).count, 4)
        XCTAssertEqual(accounts[1].quotas.first?.format, .count(suffix: "prompts"))
    }

    func testUsageClientLoadAndRefreshLocalWithMockTransport() async throws {
        let providersData = Data("""
        [
          {
            "providerId": "codex",
            "name": "Codex",
            "enabled": true
          }
        ]
        """.utf8)
        let snapshotsData = Data("""
        [
          {
            "providerId": "codex",
            "startedAt": "2026-11-22T03:05:00Z",
            "raw": {
              "lines": [
                {
                  "type": "progress",
                  "label": "Requests",
                  "used": 0,
                  "limit": 200,
                  "format": {
                    "kind": "count",
                    "suffix": "req"
                  }
                }
              ]
            }
          }
        ]
        """.utf8)
        let refreshData = Data("""
        {
          "ok": true,
          "results": [
            {
              "providerId": "codex",
              "ok": true
            },
            {
              "providerId": "codex:work",
              "ok": false
            },
            {
              "providerId": "minimax",
              "ok": false
            }
          ]
        }
        """.utf8)

        let transport = MockUsageTransport { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertFalse(request.httpShouldHandleCookies)

            switch (request.httpMethod, url.path) {
            case ("GET", "/api/providers"):
                XCTAssertEqual(request.timeoutInterval, 12)
                return (providersData, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            case ("GET", "/api/usage/latest-snapshots"):
                XCTAssertEqual(request.timeoutInterval, 12)
                return (snapshotsData, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            case ("POST", "/api/providers/refresh"):
                XCTAssertEqual(url.absoluteString, "http://127.0.0.1:6736/api/providers/refresh")
                XCTAssertEqual(request.timeoutInterval, 120)
                return (refreshData, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "") \(url.absoluteString)")
                throw UsageClientError.invalidResponse
            }
        }

        let client = UsageClient(transport: transport)
        let endpoint = try XCTUnwrap(UsageEndpoint(tailscale: "https://server.my-tailnet.ts.net:8443"))
        let dashboard = try await client.load(endpoint)
        XCTAssertEqual(dashboard.accounts.count, 1)
        XCTAssertEqual(dashboard.accounts[0].quotas.first?.format, .count(suffix: "req"))

        let failedCount = try await client.refreshLocal()
        XCTAssertEqual(failedCount, 2)
    }

    func testUsageClientThrowsHighLevelErrorOnHTTPFailure() async throws {
        let transport = MockUsageTransport { request in
            let url = try XCTUnwrap(request.url)
            return (Data(), HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }

        let client = UsageClient(transport: transport)
        do {
            _ = try await client.refreshLocal()
            XCTFail("Expected HTTP error")
        } catch let error as UsageClientError {
            XCTAssertEqual(error, .httpError(statusCode: 503))
        }
    }
}

private final class MockUsageTransport: UsageTransport, @unchecked Sendable {
    private let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    init(handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}
