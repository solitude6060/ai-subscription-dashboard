import Foundation
import XCTest
@testable import AisubdashCore

final class UsageQuotaIDTests: XCTestCase {
    func testExtractsExactProviderIDFromDecoderOutputUsingUTF8Lengths() throws {
        let providers = ["codex", "codex:work", "雲端:🧪"]
        let providerData = try JSONSerialization.data(withJSONObject: providers.map {
            ["providerId": $0, "enabled": true] as [String: Any]
        })
        let snapshots = try JSONSerialization.data(withJSONObject: providers.map {
            [
                "providerId": $0,
                "raw": ["lines": [["type": "progress", "label": "使用:量", "used": 1, "limit": 100]]],
            ] as [String: Any]
        })
        let dashboard = try UsageContractDecoder.decode(providersData: providerData, snapshotsData: snapshots)

        XCTAssertEqual(dashboard.accounts.flatMap(\.quotas).map { UsageQuota.providerID(fromID: $0.id) }, providers.map { Optional($0) })
    }

    func testRejectsMalformedQuotaIDs() {
        for id in ["", "codex:work::5h", "10:codex", "5:codex", "5:codex2:5h", "5:codex2:5h:0", "2:雲2:5h:1"] {
            XCTAssertNil(UsageQuota.providerID(fromID: id), id)
        }
    }
}
