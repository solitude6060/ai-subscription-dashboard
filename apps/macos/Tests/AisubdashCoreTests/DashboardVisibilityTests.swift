import Foundation
import XCTest
@testable import AisubdashCore

@MainActor
final class DashboardVisibilityTests: XCTestCase {
    private let origin = "https://box.tailnet.ts.net"
    private let pin = UsageQuota(id: "10:codex:work2:5h:1", label: "5h", used: 95, limit: 100, format: .percent)
    private let otherQuota = UsageQuota(id: "5:codex3:API:1", label: "API", used: 90, limit: 100, format: .percent)
    private let warning = UsageQuota(id: "5:codex3:API:2", label: "API", used: 89, limit: 100, format: .percent)

    func testAutomaticVisibilityAndCountsFollowLoadedQuotas() async {
        let store = makeStore()

        await store.reload()

        XCTAssertEqual(store.dashboard?.accounts.map(\.id), ["manual", "codex:work", "codex"])
        XCTAssertEqual(store.visibleAccounts.map(\.id), ["codex:work", "codex"])
        XCTAssertEqual(store.hiddenAccountCount, 1)
        XCTAssertEqual(store.nearLimitCount, 2)
        XCTAssertFalse(store.hasVisibilityOverrides)
    }

    func testOverridesMatchExactAccountIDsAndPreserveServerOrder() async {
        let store = makeStore()
        await store.reload()

        store.setAccountVisibility(false, providerID: "codex")
        store.setAccountVisibility(true, providerID: "manual")

        XCTAssertEqual(store.visibleAccounts.map(\.id), ["manual", "codex:work"])
        XCTAssertEqual(store.hiddenAccountCount, 1)
        XCTAssertEqual(store.nearLimitCount, 1)
        XCTAssertTrue(store.hasVisibilityOverrides)
    }

    func testHiddenProviderKeepsThePinAndItsMenuBarReading() async {
        let store = makeStore()
        await store.reload()
        store.togglePin(quotaID: pin.id)

        store.setAccountVisibility(false, providerID: "codex:work")

        XCTAssertEqual(store.visibleAccounts.map(\.id), ["codex"])
        XCTAssertEqual(store.pinnedQuotaID, pin.id)
        guard case .available(let account, let quota, _) = store.pinnedQuotaState(now: store.clock) else {
            return XCTFail("Expected the hidden provider's pinned reading to remain available")
        }
        XCTAssertEqual(account.id, "codex:work")
        XCTAssertEqual(quota, pin)
    }

    func testVisibilityPersistsPerSourceAndResetOnlyAffectsTheSelectedSource() async {
        let suiteName = "DashboardVisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = makeStore(preferences: UserDefaultsDashboardPreferences(userDefaults: defaults))
        first.setAccountVisibility(false, providerID: "codex")
        first.selectSource(.tailscale)
        XCTAssertTrue(first.updateTailscaleOrigin(origin))
        first.setAccountVisibility(true, providerID: "manual")

        let restored = makeStore(preferences: UserDefaultsDashboardPreferences(userDefaults: defaults))
        await restored.reload()
        XCTAssertEqual(restored.selectedSource, .tailscale)
        XCTAssertEqual(restored.visibleAccounts.map(\.id), ["manual", "codex:work", "codex"])

        restored.resetVisibilityOverrides()
        XCTAssertFalse(restored.hasVisibilityOverrides)
        XCTAssertEqual(restored.visibleAccounts.map(\.id), ["codex:work", "codex"])
        restored.selectSource(.local)
        await restored.reload()
        XCTAssertTrue(restored.hasVisibilityOverrides)
        XCTAssertEqual(restored.visibleAccounts.map(\.id), ["codex:work"])
    }

    func testChangingTailscaleOriginKeepsThePreviousOriginsOverrides() async {
        let store = makeStore(preferences: InMemoryDashboardPreferences(
            selectedSource: .tailscale,
            tailscaleOriginInput: origin
        ))
        store.setAccountVisibility(true, providerID: "manual")

        XCTAssertTrue(store.updateTailscaleOrigin("https://other.tailnet.ts.net"))
        await store.reload()
        XCTAssertFalse(store.hasVisibilityOverrides)
        XCTAssertEqual(store.visibleAccounts.map(\.id), ["codex:work", "codex"])

        XCTAssertTrue(store.updateTailscaleOrigin(origin))
        await store.reload()
        XCTAssertTrue(store.hasVisibilityOverrides)
        XCTAssertEqual(store.visibleAccounts.map(\.id), ["manual", "codex:work", "codex"])
    }

    func testReloadKeepsOverridesForProvidersThatAreAbsent() async {
        let preferences = InMemoryDashboardPreferences()
        let store = DashboardStore(preferences: preferences, loadDashboard: { _ in UsageDashboard(accounts: []) })
        store.setAccountVisibility(false, providerID: "codex:work")

        await store.reload()

        XCTAssertTrue(store.hasVisibilityOverrides)
        XCTAssertEqual(preferences.visibilityOverridesByOrigin[UsageEndpoint.local.origin.absoluteString], [
            "codex:work": false,
        ])
        let restored = makeStore(preferences: preferences)
        await restored.reload()
        XCTAssertEqual(restored.visibleAccounts.map(\.id), ["codex"])
    }

    func testPinnedProviderCanBeIdentifiedWhenItsQuotaIsMissing() async {
        let preferences = InMemoryDashboardPreferences(
            pinsByOrigin: [UsageEndpoint.local.origin.absoluteString: "10:codex:work6:Weekly:1"]
        )
        let store = makeStore(preferences: preferences)
        await store.reload()

        XCTAssertEqual(store.pinnedQuotaState(now: store.clock), .missing(id: "10:codex:work6:Weekly:1"))
        XCTAssertEqual(store.pinnedProviderID, "codex:work")
    }

    private func makeStore(preferences: DashboardPreferences = InMemoryDashboardPreferences()) -> DashboardStore {
        let dashboard = UsageDashboard(accounts: [
            UsageAccount(id: "manual", name: "Manual", quotas: []),
            UsageAccount(id: "codex:work", name: "Codex Work", quotas: [pin]),
            UsageAccount(id: "codex", name: "Codex", quotas: [otherQuota, warning]),
        ])
        return DashboardStore(preferences: preferences, loadDashboard: { _ in dashboard })
    }
}
