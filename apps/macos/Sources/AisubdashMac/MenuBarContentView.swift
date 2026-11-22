#if os(macOS)
import AppKit
import SwiftUI
import AisubdashCore

struct MenuBarContentView: View {
    let store: DashboardStore
    @State private var showingSettings = false
    @State private var tailscaleDraft = ""
    @State private var invalidOrigin = false

    private static let originInstructions = "Enter a Tailscale HTTPS URL or direct Tailscale IPv4 address and port."

    init(store: DashboardStore) {
        self.store = store
    }

    /// Visible height of the screen showing the panel; the panel and account list grow
    /// to it so the list scrolls only when the cards do not fit.
    private var screenHeight: CGFloat { NSScreen.main?.visibleFrame.height ?? 800 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
                .fixedSize(horizontal: false, vertical: true)
            if showingSettings {
                settings
            } else {
                statusSection
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                accountsSection
                    .layoutPriority(-1)
                Divider()
                footer
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 400)
        .frame(maxHeight: screenHeight - 40)
        .background {
            PanelDismissalObserver { showingSettings = false }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onDisappear { showingSettings = false }
        .onChange(of: tailscaleDraft) { invalidOrigin = false }
        .onChange(of: store.selectedSource) { invalidOrigin = false }
        .task { await store.reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if showingSettings {
                    Button {
                        showingSettings = false
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Back to Usage")
                    Text("Settings")
                        .font(.headline)
                } else {
                    Label("aisubdash", systemImage: "gauge.with.dots.needle.33percent")
                        .font(.headline)
                }

                Spacer(minLength: 0)
                sourcePicker
                busyIndicator

                if !showingSettings {
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(",", modifiers: .command)
                    .accessibilityLabel("Open Settings")
                }
            }

            if showingSettings {
                if invalidOrigin && store.selectedSource == .tailscale {
                    Text(Self.originInstructions)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if case .failed = store.status, let requestStatusText {
                    Text(requestStatusText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var sourcePicker: some View {
        Picker("Usage Source", selection: Binding(
            get: { store.selectedSource },
            set: { source in
                store.selectSource(source)
                Task { await store.reload() }
            }
        )) {
            Text("This Mac").tag(UsageSourceKind.local)
            Text("Tailscale").tag(UsageSourceKind.tailscale)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 152)
        .accessibilityLabel("Usage Source")
    }

    private var busyIndicator: some View {
        Group {
            if store.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(store.isRefreshingLocal ? "Refreshing Local Providers" : "Loading Usage")
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 16, height: 16)
    }

    private var statusSection: some View {
        let hiddenCount = store.hiddenAccountCount
        let nearLimitCount = store.nearLimitCount
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(sourceSummary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(-1)
                if hiddenCount > 0 {
                    Button(action: openSettings) {
                        HStack(spacing: 4) {
                            Text("\(hiddenCount) hidden")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(ProviderCountFormatter.hiddenSettingsLabel(hiddenCount))
                }
            }

            if nearLimitCount > 0 || requestStatusText != nil {
                HStack(spacing: 6) {
                    if nearLimitCount > 0 {
                        Text("\(nearLimitCount) near limit")
                            .fontWeight(.medium)
                            .fixedSize()
                        Spacer(minLength: 0)
                    }
                    if let requestStatusText {
                        if store.status == .idle {
                            Label {
                                Text(requestStatusText)
                            } icon: {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .foregroundStyle(.orange)
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(.primary)
                        } else {
                            Text(requestStatusText)
                                .foregroundStyle(statusColor)
                        }
                    }
                }
                .multilineTextAlignment(nearLimitCount > 0 ? .trailing : .leading)
                .accessibilityElement(children: .combine)
            }

            if let warning = store.lastRefreshWarning {
                Label {
                    Text(warning)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .foregroundStyle(.primary)
            }

            if case .missing = store.pinnedQuotaState(now: store.clock),
               let quotaID = store.pinnedQuotaID {
                HStack(spacing: 6) {
                    Label {
                        Text("Pinned quota unavailable.")
                    } icon: {
                        Image(systemName: "pin.slash")
                            .foregroundStyle(.orange)
                    }
                    .foregroundStyle(.primary)
                    Spacer()
                    Button("Unpin") { store.togglePin(quotaID: quotaID) }
                        .controlSize(.small)
                        .accessibilityLabel("Unpin Menu Bar Quota")
                }
            }
        }
        .font(.caption)
    }

    private var accountsSection: some View {
        let accounts = store.visibleAccounts
        let hiddenCount = store.hiddenAccountCount
        let now = store.clock

        return Group {
            if store.currentEndpoint == nil {
                ContentUnavailableView {
                    Label("Set the Tailscale address in Settings", systemImage: "gearshape")
                } actions: {
                    Button("Open Settings", action: openSettings)
                }
            } else if !accounts.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(accounts) { account in
                            AccountCardView(
                                account: account,
                                now: now,
                                isStale: store.isAccountStale(account, now: now),
                                pinnedQuotaID: store.pinnedQuotaID,
                                onTogglePin: { store.togglePin(quotaID: $0) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: screenHeight - 200)
            } else if hiddenCount > 0 {
                ContentUnavailableView {
                    Label(ProviderCountFormatter.allHidden(hiddenCount), systemImage: "eye.slash")
                } actions: {
                    HStack {
                        Button("Open Settings", action: openSettings)
                        if store.selectedSource == .local {
                            fetchUsageButton
                        }
                    }
                }
            } else if store.isBusy && store.dashboard == nil {
                ProgressView("Loading usage…")
            } else {
                ContentUnavailableView(
                    "No Usage Data",
                    systemImage: "tray",
                    description: Text("Reload to fetch the latest provider snapshots.")
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(store.isBusy || store.currentEndpoint == nil)
            .keyboardShortcut("r", modifiers: .command)
            .help("Reload Usage Snapshots")
            .accessibilityLabel("Reload Usage Snapshots")

            if store.selectedSource == .local {
                fetchUsageButton
            }

            Spacer()

            Button {
                if let url = store.currentEndpoint?.origin {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Dashboard", systemImage: "safari")
            }
            .disabled(store.currentEndpoint == nil)
            .accessibilityLabel("Open Dashboard in Browser")

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

    private var fetchUsageButton: some View {
        Button {
            Task { await store.fetchProviderUsage() }
        } label: {
            Label("Fetch Usage", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!store.canFetchProviderUsage)
        .accessibilityLabel("Fetch Local Provider Usage")
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.selectedSource == .tailscale {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("https://host.tailnet.ts.net or http://100.x.x.x:6736", text: $tailscaleDraft)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Tailscale Endpoint URL")
                            .onSubmit(applyTailscaleOrigin)
                        Button("Apply", action: applyTailscaleOrigin)
                            .disabled(tailscaleDraft == store.tailscaleOriginInput)
                            .accessibilityLabel("Apply Tailscale Endpoint")
                    }
                    if store.currentEndpoint == nil && !invalidOrigin {
                        Text(Self.originInstructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ProviderVisibilitySettings(store: store)
        }
    }

    private func openSettings() {
        tailscaleDraft = store.tailscaleOriginInput
        invalidOrigin = false
        showingSettings = true
    }

    private func applyTailscaleOrigin() {
        invalidOrigin = !store.updateTailscaleOrigin(tailscaleDraft)
        guard !invalidOrigin else { return }
        tailscaleDraft = store.tailscaleOriginInput
        Task { await store.reload() }
    }

    private var sourceSummary: String {
        switch store.selectedSource {
        case .local:
            return "This Mac (127.0.0.1:6736)"
        case .tailscale:
            return store.currentEndpoint?.origin.absoluteString ?? "Tailscale (not configured)"
        }
    }

    private var requestStatusText: String? {
        switch store.status {
        case .idle:
            return store.isUsingCachedFallback ? "Stale (cached)" : nil
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
        case .idle, .loading, .refreshingLocal:
            return .secondary
        case .failed:
            return .red
        }
    }
}

private struct PanelDismissalObserver: NSViewRepresentable {
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> WindowObserver { WindowObserver() }

    func updateNSView(_ nsView: WindowObserver, context: Context) {
        nsView.onDismiss = onDismiss
    }

    final class WindowObserver: NSView {
        var onDismiss: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            let name = NSWindow.didChangeOcclusionStateNotification
            center.removeObserver(self, name: name, object: nil)
            if let window {
                center.addObserver(self, selector: #selector(visibilityChanged(_:)), name: name, object: window)
            }
        }

        @objc private func visibilityChanged(_ notification: Notification) {
            // A hidden panel can keep its SwiftUI content mounted.
            if window?.isVisible == false {
                onDismiss?()
            }
        }
    }
}
#endif
