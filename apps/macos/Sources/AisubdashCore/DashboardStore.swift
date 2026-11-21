import Foundation
import Observation

public enum UsageSourceKind: String, CaseIterable, Sendable, Hashable {
    case local
    case tailscale
}

public enum RequestStatus: Equatable, Sendable {
    case idle
    case loading
    case refreshingLocal
    case failed(String)
}

public enum PinnedQuotaState: Equatable, Sendable {
    case none
    case unavailable
    case missing(id: String)
    case available(account: UsageAccount, quota: UsageQuota, isStale: Bool)
}

public protocol DashboardPreferences: AnyObject {
    var selectedSource: UsageSourceKind { get set }
    var tailscaleOriginInput: String { get set }
    var pinsByOrigin: [String: String] { get set }
}

public final class UserDefaultsDashboardPreferences: DashboardPreferences {
    private enum Keys {
        static let selectedSource = "aisubdash.selectedSource"
        static let tailscaleOriginInput = "aisubdash.tailscaleOriginInput"
        static let pinsByOrigin = "aisubdash.pinsByOrigin"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var selectedSource: UsageSourceKind {
        get {
            guard let raw = userDefaults.string(forKey: Keys.selectedSource),
                  let kind = UsageSourceKind(rawValue: raw)
            else {
                return .local
            }
            return kind
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Keys.selectedSource)
        }
    }

    public var tailscaleOriginInput: String {
        get { userDefaults.string(forKey: Keys.tailscaleOriginInput) ?? "" }
        set { userDefaults.set(newValue, forKey: Keys.tailscaleOriginInput) }
    }

    public var pinsByOrigin: [String: String] {
        get { userDefaults.dictionary(forKey: Keys.pinsByOrigin) as? [String: String] ?? [:] }
        set { userDefaults.set(newValue, forKey: Keys.pinsByOrigin) }
    }
}

public final class InMemoryDashboardPreferences: DashboardPreferences {
    public var selectedSource: UsageSourceKind
    public var tailscaleOriginInput: String
    public var pinsByOrigin: [String: String]

    public init(
        selectedSource: UsageSourceKind = .local,
        tailscaleOriginInput: String = "",
        pinsByOrigin: [String: String] = [:]
    ) {
        self.selectedSource = selectedSource
        self.tailscaleOriginInput = tailscaleOriginInput
        self.pinsByOrigin = pinsByOrigin
    }
}

@MainActor
@Observable
public final class DashboardStore {
    public static let staleAgeThresholdSeconds: TimeInterval = 3600

    public private(set) var selectedSource: UsageSourceKind
    public private(set) var tailscaleOriginInput: String
    public private(set) var pinnedQuotaID: String?
    public private(set) var dashboard: UsageDashboard?
    public private(set) var status: RequestStatus = .idle
    public private(set) var isUsingCachedFallback: Bool = false
    public private(set) var lastRefreshWarning: String?

    public var currentEndpoint: UsageEndpoint? {
        switch selectedSource {
        case .local:
            return .local
        case .tailscale:
            return UsageEndpoint(tailscale: tailscaleOriginInput)
        }
    }

    public var isLoading: Bool { status == .loading }
    public var isRefreshingLocal: Bool { status == .refreshingLocal }
    public var isBusy: Bool { isLoading || isRefreshingLocal }
    public var canFetchProviderUsage: Bool {
        currentEndpoint?.isLocal == true && inFlightPostGeneration == nil && !isBusy
    }

    private let preferences: DashboardPreferences
    private let loadDashboard: @Sendable (UsageEndpoint) async throws -> UsageDashboard
    private let refreshLocalProviders: @Sendable () async throws -> Int

    private var lastGoodByEndpoint: [UsageEndpoint: UsageDashboard] = [:]
    private var failedEndpoints: Set<UsageEndpoint> = []
    private var generation: UInt64 = 0
    private var inFlightGetGeneration: UInt64?
    private var inFlightPostGeneration: UInt64?

    public init(
        preferences: DashboardPreferences = UserDefaultsDashboardPreferences(),
        loadDashboard: @escaping @Sendable (UsageEndpoint) async throws -> UsageDashboard = { endpoint in
            try await UsageClient().load(endpoint)
        },
        refreshLocalProviders: @escaping @Sendable () async throws -> Int = {
            try await UsageClient().refreshLocal()
        }
    ) {
        self.preferences = preferences
        self.loadDashboard = loadDashboard
        self.refreshLocalProviders = refreshLocalProviders
        self.selectedSource = preferences.selectedSource
        self.tailscaleOriginInput =
            UsageEndpoint(tailscale: preferences.tailscaleOriginInput)?.origin.absoluteString ?? ""
        self.pinnedQuotaID = currentEndpoint.flatMap { preferences.pinsByOrigin[$0.origin.absoluteString] }
    }

    public func selectSource(_ source: UsageSourceKind) {
        guard selectedSource != source else { return }
        selectedSource = source
        preferences.selectedSource = source
        resetStateForEndpointChange()
    }

    @discardableResult
    public func updateTailscaleOrigin(_ draft: String) -> Bool {
        let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = UsageEndpoint(tailscale: input)
        guard input.isEmpty || endpoint != nil else { return false }

        let origin = endpoint?.origin.absoluteString ?? ""
        guard tailscaleOriginInput != origin else { return true }
        let previousOrigin = tailscaleOriginInput
        tailscaleOriginInput = origin
        preferences.tailscaleOriginInput = origin
        if !previousOrigin.isEmpty {
            preferences.pinsByOrigin.removeValue(forKey: previousOrigin)
            if let previous = UsageEndpoint(tailscale: previousOrigin) {
                lastGoodByEndpoint.removeValue(forKey: previous)
                failedEndpoints.remove(previous)
            }
        }
        if selectedSource == .tailscale {
            resetStateForEndpointChange()
        }
        return true
    }

    public func togglePin(quotaID: String) {
        guard let endpoint = currentEndpoint else { return }
        pinnedQuotaID = pinnedQuotaID == quotaID ? nil : quotaID
        preferences.pinsByOrigin[endpoint.origin.absoluteString] = pinnedQuotaID
    }

    public func reload() async {
        guard inFlightPostGeneration != generation,
              inFlightGetGeneration != generation
        else {
            return
        }
        await performGet()
    }

    public func fetchProviderUsage() async {
        guard canFetchProviderUsage, let endpoint = currentEndpoint else {
            return
        }

        let capturedEndpoint = endpoint
        let capturedGeneration = generation
        inFlightPostGeneration = capturedGeneration
        status = .refreshingLocal
        lastRefreshWarning = nil

        defer {
            if inFlightPostGeneration == capturedGeneration {
                inFlightPostGeneration = nil
            }
        }

        do {
            let failedCount = try await refreshLocalProviders()
            guard currentEndpoint == capturedEndpoint,
                  generation == capturedGeneration
            else {
                return
            }

            if failedCount > 0 {
                lastRefreshWarning = "\(failedCount) provider(s) failed to refresh."
            }

            await performGet(expectedEndpoint: capturedEndpoint, expectedGeneration: capturedGeneration)
        } catch {
            guard currentEndpoint == capturedEndpoint,
                  generation == capturedGeneration
            else {
                return
            }
            if Task.isCancelled || error is CancellationError {
                status = .idle
                return
            }
            lastRefreshWarning = "Provider refresh failed. \(Self.genericErrorMessage(for: error))"
            await performGet(expectedEndpoint: capturedEndpoint, expectedGeneration: capturedGeneration)
        }
    }

    public func isAccountStale(_ account: UsageAccount, now: Date = Date()) -> Bool {
        if isUsingCachedFallback {
            return true
        }
        if let observedAt = account.observedAt,
           now.timeIntervalSince(observedAt) > Self.staleAgeThresholdSeconds
        {
            return true
        }
        return account.quotas.contains { quota in
            if let resetsAt = quota.resetsAt {
                return resetsAt <= now
            }
            return false
        }
    }

    public func isQuotaStale(_ quota: UsageQuota, in account: UsageAccount, now: Date = Date()) -> Bool {
        if isUsingCachedFallback {
            return true
        }
        if let observedAt = account.observedAt,
           now.timeIntervalSince(observedAt) > Self.staleAgeThresholdSeconds
        {
            return true
        }
        if let resetsAt = quota.resetsAt, resetsAt <= now {
            return true
        }
        return false
    }

    public func pinnedQuotaState(now: Date = Date()) -> PinnedQuotaState {
        guard let pinnedQuotaID else {
            return .none
        }
        guard let accounts = dashboard?.accounts else {
            return .unavailable
        }
        for account in accounts {
            if let quota = account.quotas.first(where: { $0.id == pinnedQuotaID }) {
                let stale = isQuotaStale(quota, in: account, now: now)
                return .available(account: account, quota: quota, isStale: stale)
            }
        }
        return .missing(id: pinnedQuotaID)
    }

    private func resetStateForEndpointChange() {
        generation &+= 1
        status = .idle
        lastRefreshWarning = nil
        if let endpoint = currentEndpoint {
            pinnedQuotaID = preferences.pinsByOrigin[endpoint.origin.absoluteString]
            dashboard = lastGoodByEndpoint[endpoint]
            isUsingCachedFallback = failedEndpoints.contains(endpoint) && dashboard != nil
        } else {
            pinnedQuotaID = nil
            dashboard = nil
            isUsingCachedFallback = false
        }
    }

    private func performGet(
        expectedEndpoint: UsageEndpoint? = nil,
        expectedGeneration: UInt64? = nil
    ) async {
        let capturedEndpoint: UsageEndpoint
        let capturedGeneration: UInt64

        if let expectedEndpoint, let expectedGeneration {
            capturedEndpoint = expectedEndpoint
            capturedGeneration = expectedGeneration
        } else {
            guard let endpoint = currentEndpoint else {
                dashboard = nil
                isUsingCachedFallback = false
                status = selectedSource == .tailscale
                    ? .failed("Enter a valid Tailscale origin.")
                    : .idle
                return
            }
            capturedEndpoint = endpoint
            capturedGeneration = generation
        }

        inFlightGetGeneration = capturedGeneration
        status = .loading

        defer {
            if inFlightGetGeneration == capturedGeneration {
                inFlightGetGeneration = nil
            }
        }

        do {
            let loaded = try await loadDashboard(capturedEndpoint)
            try Task.checkCancellation()
            guard currentEndpoint == capturedEndpoint,
                  generation == capturedGeneration
            else {
                return
            }
            lastGoodByEndpoint[capturedEndpoint] = loaded
            failedEndpoints.remove(capturedEndpoint)
            dashboard = loaded
            isUsingCachedFallback = false
            status = .idle
        } catch {
            guard currentEndpoint == capturedEndpoint,
                  generation == capturedGeneration
            else {
                return
            }
            if Task.isCancelled || error is CancellationError {
                status = .idle
                return
            }
            failedEndpoints.insert(capturedEndpoint)
            dashboard = lastGoodByEndpoint[capturedEndpoint]
            isUsingCachedFallback = (dashboard != nil)
            status = .failed(Self.genericErrorMessage(for: error))
        }
    }

    private static func genericErrorMessage(for error: Error) -> String {
        guard let clientError = error as? UsageClientError else {
            return "Unable to reach the selected source."
        }
        switch clientError {
        case .httpError(let statusCode):
            return "Server returned HTTP \(statusCode)."
        case .decodingFailed:
            return "Received an unexpected response format."
        case .invalidResponse:
            return "Invalid server response."
        case .networkError:
            return "Unable to reach the selected source."
        }
    }
}
