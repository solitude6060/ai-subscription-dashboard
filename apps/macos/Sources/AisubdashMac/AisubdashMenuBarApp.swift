#if os(macOS)
import AppKit
import SwiftUI
import AisubdashCore

@MainActor
final class MenuBarLifecycle: NSObject, NSApplicationDelegate {
    let store = DashboardStore()
    private var updates: Task<Void, Never>?
    private var clockUpdates: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        clockUpdates = Task {
            while !Task.isCancelled {
                store.tick()
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    break
                }
            }
        }
        updates = Task {
            while !Task.isCancelled {
                await store.reload()
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    break
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        updates?.cancel()
        clockUpdates?.cancel()
    }
}

@MainActor
struct AisubdashMenuBarApp: App {
    @NSApplicationDelegateAdaptor(MenuBarLifecycle.self) private var lifecycle

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: lifecycle.store)
        } label: {
            MenuBarLabelView(store: lifecycle.store)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabelView: View {
    let store: DashboardStore

    var body: some View {
        // A TimelineView in a MenuBarExtra label hides the status item on macOS 27.2.
        // The store clock ticks every 30 s, so stale markers age without a new snapshot.
        let now = store.clock
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            if let labelText = labelText(now: now) {
                Text(labelText)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityText(now: now))
    }

    private func labelText(now: Date) -> String? {
        switch store.pinnedQuotaState(now: now) {
        case .none:
            return nil
        case .unavailable:
            return "Pin: No Data"
        case .missing:
            return "Pin: Missing"
        case .available(_, let quota, let isStale):
            let formatted = QuotaFormatter.compactValue(quota)
            return isStale ? "\(formatted) (Stale)" : formatted
        }
    }

    private func accessibilityText(now: Date) -> String {
        switch store.pinnedQuotaState(now: now) {
        case .none:
            return "aisubdash usage monitor"
        case .unavailable:
            return "aisubdash, pinned quota data unavailable"
        case .missing:
            return "aisubdash, pinned quota missing"
        case .available(let account, let quota, let isStale):
            let formatted = QuotaFormatter.compactValue(quota)
            let stalePart = isStale ? ", stale" : ""
            return "aisubdash, \(account.name) \(quota.label) \(formatted)\(stalePart)"
        }
    }
}

private struct MenuBarContentView: View {
    @Bindable var store: DashboardStore
    @State private var tailscaleDraft: String = ""
    @State private var accountExpansion: [String: Bool] = [:]
    @State private var invalidOrigin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerSection
            sourceControlsSection
            statusSection(now: store.clock)
            Divider()
            accountsSection(now: store.clock)
            Divider()
            footerActionsSection
        }
        .padding(12)
        .frame(minWidth: 360, idealWidth: 390, maxWidth: 440)
        .onAppear {
            tailscaleDraft = store.tailscaleOriginInput
        }
        .task { await store.reload() }
    }

    private var headerSection: some View {
        HStack {
            Label("aisubdash", systemImage: "gauge.with.dots.needle.33percent")
                .font(.headline)
            Spacer()
            if store.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(store.isRefreshingLocal ? "Refreshing local providers" : "Loading usage")
            }
        }
    }

    private var sourceControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Source", selection: Binding(
                get: { store.selectedSource },
                set: { newSource in
                    store.selectSource(newSource)
                    Task { await store.reload() }
                }
            )) {
                Text("This Mac").tag(UsageSourceKind.local)
                Text("Tailscale").tag(UsageSourceKind.tailscale)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Usage source")

            if store.selectedSource == .tailscale {
                HStack(spacing: 6) {
                    TextField("https://host.tailnet.ts.net or http://100.x.x.x:6736", text: $tailscaleDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Tailscale endpoint URL")
                        .onSubmit {
                            applyTailscaleOrigin()
                        }
                    Button("Apply") {
                        applyTailscaleOrigin()
                    }
                    .disabled(tailscaleDraft == store.tailscaleOriginInput)
                    .accessibilityLabel("Apply Tailscale endpoint")
                }

                if invalidOrigin || store.currentEndpoint == nil {
                    Text("Enter a Tailscale HTTPS URL or direct Tailscale IPv4 address and port.")
                        .font(.caption)
                        .foregroundStyle(invalidOrigin ? .red : .secondary)
                }
            }
        }
    }

    private func statusSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(sourceSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(requestStatusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }
            .accessibilityElement(children: .combine)

            if let warning = store.lastRefreshWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if case .missing = store.pinnedQuotaState(now: now) {
                Text("Pinned quota unavailable.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func accountsSection(now: Date) -> some View {
        Group {
            if let accounts = store.dashboard?.accounts, !accounts.isEmpty {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(accounts) { account in
                            AccountRowView(
                                account: account,
                                now: now,
                                isStale: store.isAccountStale(account, now: now),
                                pinnedQuotaID: store.pinnedQuotaID,
                                isExpanded: Binding(
                                    get: { accountExpansion[account.id] ?? (accounts.count <= 3) },
                                    set: { accountExpansion[account.id] = $0 }
                                ),
                                onTogglePin: { quotaID in
                                    store.togglePin(quotaID: quotaID)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 160, maxHeight: 340)
            } else {
                ContentUnavailableView(
                    store.currentEndpoint == nil ? "No Endpoint Configured" : "No Usage Data",
                    systemImage: "tray",
                    description: Text(store.currentEndpoint == nil
                        ? "Configure a valid Tailscale origin to load snapshots."
                        : "Reload to fetch the latest provider snapshots.")
                )
                .frame(minHeight: 140, maxHeight: 200)
            }
        }
    }

    private var footerActionsSection: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.reload() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(store.isBusy || store.currentEndpoint == nil)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel("Reload usage snapshots")

            if store.selectedSource == .local {
                Button {
                    Task { await store.fetchProviderUsage() }
                } label: {
                    Label("Fetch Provider Usage", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!store.canFetchProviderUsage)
                .accessibilityLabel("Fetch local provider usage")
            }

            Spacer()

            Button {
                if let url = store.currentEndpoint?.origin {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open Dashboard", systemImage: "safari")
            }
            .disabled(store.currentEndpoint == nil)
            .accessibilityLabel("Open dashboard in browser")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityLabel("Quit aisubdash")
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
    }

    private func applyTailscaleOrigin() {
        invalidOrigin = !store.updateTailscaleOrigin(tailscaleDraft)
        guard !invalidOrigin else { return }
        tailscaleDraft = store.tailscaleOriginInput
        Task { await store.reload() }
    }

    private var sourceSummaryText: String {
        switch store.selectedSource {
        case .local:
            return "This Mac (127.0.0.1:6736)"
        case .tailscale:
            return store.currentEndpoint?.origin.absoluteString ?? "Tailscale (not configured)"
        }
    }

    private var requestStatusText: String {
        switch store.status {
        case .idle:
            return store.isUsingCachedFallback ? "Stale (cached)" : "Ready"
        case .loading:
            return "Loading…"
        case .refreshingLocal:
            return "Refreshing providers…"
        case .failed(let message):
            return store.isUsingCachedFallback ? "Stale: \(message)" : message
        }
    }

    private var statusColor: Color {
        switch store.status {
        case .idle:
            return store.isUsingCachedFallback ? .orange : .secondary
        case .loading, .refreshingLocal:
            return .secondary
        case .failed:
            return .red
        }
    }
}

private struct AccountRowView: View {
    let account: UsageAccount
    let now: Date
    let isStale: Bool
    let pinnedQuotaID: String?
    @Binding var isExpanded: Bool
    let onTogglePin: (String) -> Void

    // DisclosureGroup does not expand inside a .window MenuBarExtra on macOS 27.2.1;
    // a plain button toggling the same binding does (owner-Mac review, finding 12).
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 12, height: 16)
                        .foregroundStyle(.secondary)
                    header
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Keep the header (name, badges, reading age) as the label; expose state separately.
            .accessibilityElement(children: .combine)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapses the quotas" : "Shows the quotas")

            if isExpanded {
                details
                    .padding(.leading, 18)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var details: some View {
            VStack(alignment: .leading, spacing: 8) {
                if account.quotas.isEmpty {
                    Text("No quota data reported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(account.quotas) { quota in
                        QuotaRowView(
                            quota: quota,
                            now: now,
                            isPinned: pinnedQuotaID == quota.id,
                            onTogglePin: { onTogglePin(quota.id) }
                        )
                    }
                }
            }
            .padding(.top, 6)
    }

    private var header: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.subheadline.weight(.semibold))
                    if isStale {
                        Text("Stale")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    if account.refreshFailed {
                        Text("Refresh failed")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.red.opacity(0.18), in: Capsule())
                            .foregroundStyle(.red)
                    }
                    Spacer()
                }

                if let observedAt = account.observedAt {
                    Text("Observed \(QuotaFormatter.absoluteTimestamp(observedAt)) (\(QuotaFormatter.relativeAge(from: observedAt, to: now)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Observation time unavailable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
    }
}

private struct QuotaRowView: View {
    let quota: UsageQuota
    let now: Date
    let isPinned: Bool
    let onTogglePin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(quota.label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(QuotaFormatter.detailedValue(quota))
                    .font(.caption)
                    .monospacedDigit()
                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isPinned ? "Unpin \(quota.label)" : "Pin \(quota.label)")
            }

            ProgressView(
                value: min(quota.used, quota.limit),
                total: quota.limit
            )
            .accessibilityLabel("\(quota.label) usage")
            .accessibilityValue(QuotaFormatter.detailedValue(quota))

            if let resetsAt = quota.resetsAt {
                let resetDue = resetsAt <= now
                Text(resetDue
                    ? "Reset due (\(QuotaFormatter.absoluteTimestamp(resetsAt)))"
                    : "Resets \(QuotaFormatter.absoluteTimestamp(resetsAt))")
                    .font(.caption2)
                    .foregroundStyle(resetDue ? .orange : .secondary)
            }
        }
    }
}

private enum QuotaFormatter {
    static func compactValue(_ quota: UsageQuota) -> String {
        switch quota.format {
        case .percent:
            return "\(formatNumber(quota.used))%"
        case .usd:
            return String(format: "$%.2f", quota.used)
        case .count(let suffix):
            let value = "\(formatNumber(quota.used))/\(formatNumber(quota.limit))"
            if let suffix, !suffix.isEmpty {
                return "\(value) \(suffix)"
            }
            return value
        }
    }

    static func detailedValue(_ quota: UsageQuota) -> String {
        switch quota.format {
        case .percent:
            return "\(formatNumber(quota.used))% used"
        case .usd:
            return String(format: "$%.2f / $%.2f", quota.used, quota.limit)
        case .count(let suffix):
            let base = "\(formatNumber(quota.used)) / \(formatNumber(quota.limit))"
            if let suffix, !suffix.isEmpty {
                return "\(base) \(suffix)"
            }
            return base
        }
    }

    static func absoluteTimestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func relativeAge(from earlier: Date, to now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(earlier)))
        if elapsed < 60 {
            return "\(elapsed)s ago"
        }
        let minutes = elapsed / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = minutes / 60
        return "\(hours)h \(minutes % 60)m ago"
    }

    private static func formatNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
#endif
