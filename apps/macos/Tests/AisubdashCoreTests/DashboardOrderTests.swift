import Foundation
import XCTest
@testable import AisubdashCore

@MainActor
final class DashboardOrderTests: XCTestCase {
    private let origin = "https://box.tailnet.ts.net"
    private let local = UsageEndpoint.local.origin.absoluteString

    func testWithoutSavedOrderAccountsFollowServerOrder() async {
        let store = makeStore()
        await store.reload()

        XCTAssertEqual(store.orderedAccounts.map(\.id), ["a", "manual", "b", "c"])
        XCTAssertEqual(store.visibleAccounts.map(\.id), ["a", "b", "c"])
    }

    func testSavedOrderIsAppliedIgnoringUnknownIDsAndAppendingNewAccounts() async {
        let preferences = InMemoryDashboardPreferences(orderByOrigin: [local: ["c", "gone", "a"]])
        let store = makeStore(preferences: preferences)
        await store.reload()

        XCTAssertEqual(store.orderedAccounts.map(\.id), ["c", "a", "manual", "b"])
        XCTAssertEqual(store.visibleAccounts.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(preferences.orderByOrigin[local], ["c", "gone", "a"])
    }

    private func makeStore(preferences: DashboardPreferences = InMemoryDashboardPreferences()) -> DashboardStore {
        func quota(_ provider: String) -> UsageQuota {
            UsageQuota(
                id: "\(provider.count):\(provider)2:5h:1",
                label: "5h",
                used: 10,
                limit: 100,
                format: .percent
            )
        }
        let dashboard = UsageDashboard(accounts: [
            UsageAccount(id: "a", name: "A", quotas: [quota("a")]),
            UsageAccount(id: "manual", name: "Manual", quotas: []),
            UsageAccount(id: "b", name: "B", quotas: [quota("b")]),
            UsageAccount(id: "c", name: "C", quotas: [quota("c")]),
        ])
        return DashboardStore(preferences: preferences, loadDashboard: { _ in dashboard })
    }
}
