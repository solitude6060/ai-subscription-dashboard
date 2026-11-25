#if os(macOS)
import SwiftUI
import AisubdashCore

struct ProviderVisibilitySettings: View {
    let store: DashboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Reset to automatic") { store.resetVisibilityOverrides() }
                    .controlSize(.small)
                    .disabled(!store.hasVisibilityOverrides)
                Button("Reset Order") { store.resetAccountOrder() }
                    .controlSize(.small)
                    .disabled(!store.hasCustomOrder)
            }
            if let dashboard = store.dashboard {
                let accounts = dashboard.accounts
                if accounts.isEmpty {
                    Text("No enabled providers")
                        .foregroundStyle(.secondary)
                } else {
                    providerList(accounts)
                }
            } else {
                Text("Connect a source to manage providers")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerList(_ accounts: [UsageAccount]) -> some View {
        let ordered = accounts.filter { !$0.quotas.isEmpty } + accounts.filter { $0.quotas.isEmpty }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ordered) { account in
                    providerRow(account)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 340)
    }

    private func providerRow(_ account: UsageAccount) -> some View {
        let subtitle = providerStatus(account)
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { store.isAccountVisible(account) },
                set: { store.setAccountVisibility($0, providerID: account.id) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .accessibilityLabel("\(account.name), \(subtitle)")

            if store.pinnedProviderID == account.id, let quotaID = store.pinnedQuotaID {
                HStack(spacing: 6) {
                    PanelBadge(title: "Pinned", icon: "pin.fill", tint: .accentColor)
                    Button("Unpin") { store.togglePin(quotaID: quotaID) }
                        .controlSize(.small)
                        .accessibilityLabel("Unpin Quota for \(account.name)")
                }
            }
        }
    }

    private func providerStatus(_ account: UsageAccount) -> String {
        let quotaCount = account.quotas.count
        if quotaCount == 0 {
            return account.refreshFailed ? "Refresh failed" : "No data"
        }
        let quotas = ProviderCountFormatter.quotas(quotaCount)
        return account.refreshFailed ? "\(quotas) · Refresh failed" : quotas
    }
}
#endif
