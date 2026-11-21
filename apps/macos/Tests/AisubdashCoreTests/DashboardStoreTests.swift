import Foundation
import XCTest
@testable import AisubdashCore

@MainActor
final class DashboardStoreTests: XCTestCase {
    func testPersistsOnlySourceEndpointAndPinWithoutReadings() async {
        let suiteName = "DashboardStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let remoteDashboard = Self.makeDashboard(accountID: "codex:work", quotaLabel: "5h", used: 42, limit: 100)
        let store1 = DashboardStore(
            preferences: UserDefaultsDashboardPreferences(userDefaults: defaults),
            loadDashboard: { endpoint in
                XCTAssertFalse(endpoint.isLocal)
                return remoteDashboard
            },
            refreshLocalProviders: { 0 }
        )

        store1.selectSource(.tailscale)
        store1.updateTailscaleOrigin("https://box.tailnet.ts.net")
        await store1.reload()
        store1.togglePin(quotaID: "codex:work::5h")

        XCTAssertEqual(store1.selectedSource, .tailscale)
        XCTAssertEqual(store1.currentEndpoint?.origin.absoluteString, "https://box.tailnet.ts.net")
        XCTAssertEqual(store1.pinnedQuotaID, "codex:work::5h")
        XCTAssertEqual(store1.dashboard, remoteDashboard)

        // New store instance restores selection, endpoint, and pin, but NOT dashboard readings.
        let store2 = DashboardStore(
            preferences: UserDefaultsDashboardPreferences(userDefaults: defaults),
            loadDashboard: { _ in throw UsageClientError.networkError },
            refreshLocalProviders: { 0 }
        )

        XCTAssertEqual(store2.selectedSource, .tailscale)
        XCTAssertEqual(store2.tailscaleOriginInput, "https://box.tailnet.ts.net")
        XCTAssertEqual(store2.currentEndpoint?.origin.absoluteString, "https://box.tailnet.ts.net")
        XCTAssertEqual(store2.pinnedQuotaID, "codex:work::5h")
        XCTAssertNil(store2.dashboard)
    }

    func testRejectsAnInvalidRemoteOriginWithoutPersistingItsCredentials() {
        let preferences = InMemoryDashboardPreferences()
        let store = DashboardStore(preferences: preferences)
        store.selectSource(.tailscale)
        store.updateTailscaleOrigin("https://box.tailnet.ts.net")
        store.updateTailscaleOrigin("https://user:secret@box.tailnet.ts.net")
        XCTAssertEqual(preferences.tailscaleOriginInput, "https://box.tailnet.ts.net")
        XCTAssertEqual(store.currentEndpoint?.origin.absoluteString, "https://box.tailnet.ts.net")
    }

    func testPinsFollowTheirEndpointWhenBothSourcesHaveTheSameQuota() {
        let store = DashboardStore(preferences: InMemoryDashboardPreferences())
        store.togglePin(quotaID: "codex:work::5h")
        store.selectSource(.tailscale)
        store.updateTailscaleOrigin("https://box.tailnet.ts.net")
        XCTAssertNil(store.pinnedQuotaID)
        store.togglePin(quotaID: "codex:work::5h")
        XCTAssertEqual(store.pinnedQuotaID, "codex:work::5h")
        store.selectSource(.local)
        XCTAssertEqual(store.pinnedQuotaID, "codex:work::5h")
    }

    func testDelayedLocalToRemoteToLocalDiscardsStaleLocalGeneration() async {
        let staleLocalDashboard = Self.makeDashboard(accountID: "local:old", quotaLabel: "5h", used: 10, limit: 100)
        let freshLocalDashboard = Self.makeDashboard(accountID: "local:new", quotaLabel: "5h", used: 75, limit: 100)
        let remoteDashboard = Self.makeDashboard(accountID: "remote:1", quotaLabel: "5h", used: 20, limit: 100)

        let gate = AsyncGate<UsageDashboard>()
        let localCalls = LockedBox(0)

        let store = DashboardStore(
            preferences: InMemoryDashboardPreferences(),
            loadDashboard: { endpoint in
                if endpoint.isLocal {
                    let count = localCalls.withLock { value -> Int in
                        value += 1
                        return value
                    }
                    if count == 1 {
                        return try await gate.wait()
                    }
                    return freshLocalDashboard
                }
                return remoteDashboard
            },
            refreshLocalProviders: { 0 }
        )

        let initialLoad = Task { @MainActor in
            await store.reload()
        }
        await gate.waitUntilSuspended()

        // Switch local -> tailscale -> local before first local GET resolves.
        store.selectSource(.tailscale)
        store.updateTailscaleOrigin("https://box.tailnet.ts.net")
        store.selectSource(.local)

        await store.reload()
        XCTAssertEqual(store.dashboard, freshLocalDashboard)

        // Now complete the delayed first local GET; it must be ignored.
        await gate.resume(returning: staleLocalDashboard)
        await initialLoad.value

        XCTAssertEqual(store.currentEndpoint, .local)
        XCTAssertEqual(store.dashboard, freshLocalDashboard)
    }

    func testLocalPostCompletionAfterSwitchDoesNotFollowWithGetOrTouchRemoteState() async {
        let remoteDashboard = Self.makeDashboard(accountID: "remote:1", quotaLabel: "5h", used: 33, limit: 100)
        let postGate = AsyncGate<Int>()
        let getEndpoints = LockedBox<[UsageEndpoint]>([])

        let store = DashboardStore(
            preferences: InMemoryDashboardPreferences(),
            loadDashboard: { endpoint in
                getEndpoints.withLock { $0.append(endpoint) }
                return remoteDashboard
            },
            refreshLocalProviders: {
                try await postGate.wait()
            }
        )

        let postTask = Task { @MainActor in
            await store.fetchProviderUsage()
        }
        await postGate.waitUntilSuspended()

        XCTAssertTrue(store.isRefreshingLocal)

        // Switch to tailscale while local POST is in flight.
        store.selectSource(.tailscale)
        store.updateTailscaleOrigin("https://box.tailnet.ts.net")
        await store.reload()

        XCTAssertEqual(store.dashboard, remoteDashboard)
        XCTAssertEqual(getEndpoints.withLock { $0.count }, 1)
        XCTAssertFalse(getEndpoints.withLock { $0[0].isLocal })

        // Finish local POST; it must NOT trigger a local GET or overwrite remote state.
        await postGate.resume(returning: 0)
        await postTask.value

        XCTAssertEqual(getEndpoints.withLock { $0.count }, 1)
        XCTAssertEqual(store.selectedSource, .tailscale)
        XCTAssertEqual(store.dashboard, remoteDashboard)
        XCTAssertFalse(store.isRefreshingLocal)
    }

    func testSingleInFlightRefreshAndPeriodicGetDoesNotCancelOrOverlapLocalPost() async {
        let localDashboard = Self.makeDashboard(accountID: "local:1", quotaLabel: "5h", used: 55, limit: 100)
        let postGate = AsyncGate<Int>()
        let postCalls = LockedBox(0)
        let getCalls = LockedBox(0)

        let store = DashboardStore(
            preferences: InMemoryDashboardPreferences(),
            loadDashboard: { _ in
                getCalls.withLock { $0 += 1 }
                return localDashboard
            },
            refreshLocalProviders: {
                postCalls.withLock { $0 += 1 }
                return try await postGate.wait()
            }
        )

        let postTask = Task { @MainActor in
            await store.fetchProviderUsage()
        }
        await postGate.waitUntilSuspended()

        // Overlapping periodic GET and duplicate POST must be ignored while POST is in flight.
        await store.reload()
        await store.fetchProviderUsage()

        XCTAssertEqual(postCalls.withLock { $0 }, 1)
        XCTAssertEqual(getCalls.withLock { $0 }, 0)
        XCTAssertTrue(store.isRefreshingLocal)

        await postGate.resume(returning: 0)
        await postTask.value

        XCTAssertEqual(postCalls.withLock { $0 }, 1)
        XCTAssertEqual(getCalls.withLock { $0 }, 1)
        XCTAssertEqual(store.dashboard, localDashboard)
    }

    func testPostFailureDoesNotAutoRetry() async {
        let postCalls = LockedBox(0)
        let fallbackDashboard = Self.makeDashboard(accountID: "a", quotaLabel: "5h", used: 0, limit: 100)
        let store = DashboardStore(
            preferences: InMemoryDashboardPreferences(),
            loadDashboard: { _ in fallbackDashboard },
            refreshLocalProviders: {
                postCalls.withLock { $0 += 1 }
                throw UsageClientError.httpError(statusCode: 500)
            }
        )

        await store.fetchProviderUsage()

        XCTAssertEqual(postCalls.withLock { $0 }, 1)
        XCTAssertEqual(store.lastRefreshWarning, "Provider refresh failed. Server returned HTTP 500.")
        XCTAssertEqual(store.dashboard, fallbackDashboard)
    }

    func testDistinguishesStaleReasonsAndAbsentVersusZero() async {
        let baseNow = Date(timeIntervalSince1970: 1_700_000_000)
        let freshAccount = UsageAccount(
            id: "codex:1",
            name: "Codex",
            quotas: [
                UsageQuota(
                    id: "codex:1::5h",
                    label: "5h",
                    used: 0,
                    limit: 100,
                    format: .percent,
                    resetsAt: baseNow.addingTimeInterval(600)
                )
            ],
            observedAt: baseNow.addingTimeInterval(-120),
            refreshFailed: false
        )

        let shouldFailGet = LockedBox(false)
        let store = DashboardStore(
            preferences: InMemoryDashboardPreferences(),
            loadDashboard: { _ in
                if shouldFailGet.withLock({ $0 }) {
                    throw UsageClientError.networkError
                }
                return UsageDashboard(accounts: [freshAccount])
            },
            refreshLocalProviders: { 0 }
        )

        await store.reload()

        // 1. Zero reading, fresh -> available, not stale.
        store.togglePin(quotaID: "codex:1::5h")
        if case let .available(_, quota, isStale) = store.pinnedQuotaState(now: baseNow) {
            XCTAssertEqual(quota.used, 0)
            XCTAssertFalse(isStale)
        } else {
            XCTFail("Expected available zero quota")
        }

        // 2. Reported age > 1h -> stale.
        let overOneHourLater = baseNow.addingTimeInterval(3601)
        if case let .available(_, _, isStale) = store.pinnedQuotaState(now: overOneHourLater) {
            XCTAssertTrue(isStale)
        } else {
            XCTFail("Expected stale quota when age > 1h")
        }

        // 3. Reset due -> stale (even if observation is within 1h).
        let atResetDue = baseNow.addingTimeInterval(600)
        if case let .available(_, _, isStale) = store.pinnedQuotaState(now: atResetDue) {
            XCTAssertTrue(isStale)
        } else {
            XCTFail("Expected stale quota when reset is due")
        }

        // 4. GET failed -> retains in-memory last good and marks stale.
        shouldFailGet.withLock { $0 = true }
        await store.reload()
        XCTAssertTrue(store.isUsingCachedFallback)
        if case let .available(_, quota, isStale) = store.pinnedQuotaState(now: baseNow) {
            XCTAssertEqual(quota.used, 0)
            XCTAssertTrue(isStale)
        } else {
            XCTFail("Expected cached last-good quota marked stale after GET failure")
        }

        // 5. Missing pin ID -> .missing, distinct from zero.
        store.togglePin(quotaID: "codex:1::nonexistent")
        XCTAssertEqual(store.pinnedQuotaState(now: baseNow), .missing(id: "codex:1::nonexistent"))
    }

    private nonisolated static func makeDashboard(
        accountID: String,
        quotaLabel: String,
        used: Double,
        limit: Double
    ) -> UsageDashboard {
        UsageDashboard(accounts: [
            UsageAccount(
                id: accountID,
                name: accountID,
                quotas: [
                    UsageQuota(
                        id: "\(accountID)::\(quotaLabel)",
                        label: quotaLabel,
                        used: used,
                        limit: limit,
                        format: .percent,
                        resetsAt: nil
                    )
                ],
                observedAt: Date(timeIntervalSince1970: 1_700_000_000),
                refreshFailed: false
            )
        ])
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

private actor AsyncGate<Value: Sendable> {
    private var pendingResult: CheckedContinuation<Value, Error>?
    private var pendingArrival: CheckedContinuation<Void, Never>?

    func wait() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            pendingResult = continuation
            pendingArrival?.resume()
            pendingArrival = nil
        }
    }

    func waitUntilSuspended() async {
        if pendingResult != nil { return }
        await withCheckedContinuation { pendingArrival = $0 }
    }

    func resume(returning value: Value) {
        pendingResult?.resume(returning: value)
        pendingResult = nil
    }
}
