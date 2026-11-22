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

    func testDraggingDownLandsAfterTheTargetAndKeepsHiddenAccountsInPlace() async {
        let preferences = InMemoryDashboardPreferences()
        let store = makeStore(preferences: preferences)
        await store.reload()

        XCTAssertTrue(store.moveAccount("a", onto: "c"))

        XCTAssertEqual(store.visibleAccounts.map(\.id), ["b", "c", "a"])
        XCTAssertEqual(store.orderedAccounts.map(\.id), ["manual", "b", "c", "a"])
        XCTAssertEqual(preferences.orderByOrigin[local], ["manual", "b", "c", "a"])
    }

    func testDraggingUpLandsBeforeTheTargetAndKeepsHiddenAccountsInPlace() async {
        let preferences = InMemoryDashboardPreferences()
        let store = makeStore(preferences: preferences)
        await store.reload()

        XCTAssertTrue(store.moveAccount("c", onto: "a"))

        XCTAssertEqual(store.visibleAccounts.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(store.orderedAccounts.map(\.id), ["c", "a", "manual", "b"])
        XCTAssertEqual(preferences.orderByOrigin[local], ["c", "a", "manual", "b"])
    }

    func testMoveKeepsSavedIDsThatAreAbsentFromTheDashboard() async {
        let preferences = InMemoryDashboardPreferences(orderByOrigin: [local: ["gone", "b", "gone"]])
        let store = makeStore(preferences: preferences)
        await store.reload()

        XCTAssertTrue(store.moveAccount("c", onto: "b"))

        XCTAssertEqual(preferences.orderByOrigin[local], ["gone", "c", "b", "a", "manual"])
        XCTAssertEqual(store.orderedAccounts.map(\.id), ["c", "b", "a", "manual"])
    }

    func testDropRejectsUnknownHiddenAndEqualIDsWithoutSaving() async {
        let preferences = InMemoryDashboardPreferences()
        let store = makeStore(preferences: preferences)
        await store.reload()

        XCTAssertFalse(store.moveAccount("zzz", onto: "a"))
        XCTAssertFalse(store.moveAccount("a", onto: "zzz"))
        XCTAssertFalse(store.moveAccount("manual", onto: "a"))
        XCTAssertFalse(store.moveAccount("a", onto: "manual"))
        XCTAssertFalse(store.moveAccount("a", onto: "a"))
        XCTAssertFalse(store.moveAccount("1:a2:5h:1", onto: "b"))

        XCTAssertEqual(preferences.orderByOrigin, [:])
        XCTAssertEqual(store.orderedAccounts.map(\.id), ["a", "manual", "b", "c"])
        XCTAssertFalse(store.hasCustomOrder)
    }

    func testMoveByDirectionSkipsHiddenNeighbours() async {
        let preferences = InMemoryDashboardPreferences()
        let store = makeStore(preferences: preferences)
        await store.reload()

        XCTAssertTrue(store.moveAccount("a", .down))
        XCTAssertEqual(store.orderedAccounts.map(\.id), ["manual", "b", "a", "c"])

        XCTAssertTrue(store.moveAccount("a", .up))
        XCTAssertEqual(store.orderedAccounts.map(\.id), ["manual", "a", "b", "c"])

        XCTAssertTrue(store.moveAccount("b", .up))
        XCTAssertEqual(store.orderedAccounts.map(\.id), ["manual", "b", "a", "c"])
        XCTAssertEqual(preferences.orderByOrigin[local], ["manual", "b", "a", "c"])
    }

    func testMoveByDirectionRejectsEndsHiddenAndUnknownIDsWithoutSaving() async {
        let preferences = InMemoryDashboardPreferences()
        let store = makeStore(preferences: preferences)
        await store.reload()

        XCTAssertFalse(store.moveAccount("a", .up))
        XCTAssertFalse(store.moveAccount("c", .down))
        XCTAssertFalse(store.moveAccount("manual", .down))
        XCTAssertFalse(store.moveAccount("zzz", .up))

        XCTAssertEqual(preferences.orderByOrigin, [:])
    }

    func testMoveWithoutAnEndpointReturnsFalse() async {
        let preferences = InMemoryDashboardPreferences(selectedSource: .tailscale)
        let store = makeStore(preferences: preferences)
        await store.reload()

        XCTAssertNil(store.currentEndpoint)
        XCTAssertFalse(store.moveAccount("a", onto: "b"))
        XCTAssertFalse(store.moveAccount("a", .down))
        XCTAssertEqual(preferences.orderByOrigin, [:])
    }

    func testMovesLeavePinAndVisibilityUnchanged() async {
        let preferences = InMemoryDashboardPreferences()
        let store = makeStore(preferences: preferences)
        await store.reload()
        store.togglePin(quotaID: "1:b2:5h:1")
        store.setAccountVisibility(false, providerID: "c")

        XCTAssertTrue(store.moveAccount("b", onto: "a"))
        XCTAssertTrue(store.moveAccount("a", .up))

        XCTAssertEqual(store.visibleAccounts.map(\.id), ["a", "b"])
        XCTAssertEqual(store.pinnedQuotaID, "1:b2:5h:1")
        XCTAssertEqual(preferences.pinsByOrigin[local], "1:b2:5h:1")
        XCTAssertEqual(preferences.visibilityOverridesByOrigin[local], ["c": false])
        XCTAssertEqual(store.hiddenAccountCount, 2)
    }

    func testOrderPersistsPerSourceAndResetOnlyClearsTheSelectedSource() async {
        let suiteName = "DashboardOrderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = makeStore(preferences: UserDefaultsDashboardPreferences(userDefaults: defaults))
        await first.reload()
        XCTAssertFalse(first.hasCustomOrder)
        XCTAssertTrue(first.moveAccount("c", onto: "a"))
        XCTAssertTrue(first.hasCustomOrder)
        first.setAccountVisibility(true, providerID: "manual")
        first.selectSource(.tailscale)
        XCTAssertTrue(first.updateTailscaleOrigin(origin))
        await first.reload()
        XCTAssertFalse(first.hasCustomOrder)
        XCTAssertTrue(first.moveAccount("b", .up))

        let restored = makeStore(preferences: UserDefaultsDashboardPreferences(userDefaults: defaults))
        await restored.reload()
        XCTAssertTrue(restored.hasCustomOrder)
        XCTAssertEqual(restored.visibleAccounts.map(\.id), ["b", "a", "c"])

        restored.resetAccountOrder()
        XCTAssertFalse(restored.hasCustomOrder)
        XCTAssertEqual(restored.visibleAccounts.map(\.id), ["a", "b", "c"])

        restored.selectSource(.local)
        await restored.reload()
        XCTAssertTrue(restored.hasCustomOrder)
        XCTAssertEqual(restored.orderedAccounts.map(\.id), ["c", "a", "manual", "b"])

        restored.resetVisibilityOverrides()
        XCTAssertTrue(restored.hasCustomOrder)
        XCTAssertEqual(restored.orderedAccounts.map(\.id), ["c", "a", "manual", "b"])
        XCTAssertEqual(restored.visibleAccounts.map(\.id), ["c", "a", "b"])
    }

    func testResetOrderLeavesVisibilityOverrides() async {
        let preferences = InMemoryDashboardPreferences()
        let store = makeStore(preferences: preferences)
        await store.reload()
        store.setAccountVisibility(false, providerID: "a")
        XCTAssertTrue(store.moveAccount("c", onto: "b"))

        store.resetAccountOrder()

        XCTAssertFalse(store.hasCustomOrder)
        XCTAssertNil(preferences.orderByOrigin[local])
        XCTAssertTrue(store.hasVisibilityOverrides)
        XCTAssertEqual(preferences.visibilityOverridesByOrigin[local], ["a": false])
        XCTAssertEqual(store.visibleAccounts.map(\.id), ["b", "c"])
    }

    func testChangingTailscaleOriginKeepsThePreviousOriginsOrder() async {
        let store = makeStore(preferences: InMemoryDashboardPreferences(
            selectedSource: .tailscale,
            tailscaleOriginInput: origin
        ))
        await store.reload()
        XCTAssertTrue(store.moveAccount("a", .down))

        XCTAssertTrue(store.updateTailscaleOrigin("https://other.tailnet.ts.net"))
        await store.reload()
        XCTAssertFalse(store.hasCustomOrder)
        XCTAssertEqual(store.visibleAccounts.map(\.id), ["a", "b", "c"])

        XCTAssertTrue(store.updateTailscaleOrigin(origin))
        await store.reload()
        XCTAssertTrue(store.hasCustomOrder)
        XCTAssertEqual(store.visibleAccounts.map(\.id), ["b", "a", "c"])
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
