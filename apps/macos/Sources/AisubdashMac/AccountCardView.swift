#if os(macOS)
import SwiftUI
import AisubdashCore

/// Reordering callbacks for a card; absent when fewer than two cards are visible.
struct AccountCardReorder {
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?
    let drop: (String) -> Bool
}

struct AccountCardView: View {
    let account: UsageAccount
    let now: Date
    let isStale: Bool
    let pinnedQuotaID: String?
    let onTogglePin: (String) -> Void
    var reorder: AccountCardReorder?
    @State private var isDropTargeted = false

    var body: some View {
        if let reorder {
            card
                .dropDestination(for: String.self) { ids, _ in
                    // The list reorders inside this action, which may skip isTargeted(false).
                    isDropTargeted = false
                    guard let id = ids.first else { return false }
                    return reorder.drop(id)
                } isTargeted: { isDropTargeted = $0 }
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        } else {
            card
                .onAppear { isDropTargeted = false }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if account.quotas.isEmpty && account.details.isEmpty {
                Text("No quota reported")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(account.quotas) { quota in
                    QuotaRowView(quota: quota, now: now, isPinned: pinnedQuotaID == quota.id) {
                        onTogglePin(quota.id)
                    }
                }
                ForEach(account.details) { detail in
                    HStack(spacing: 6) {
                        Text(detail.label)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(-1)
                        Text(detail.value)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(8)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if reorder != nil {
                dragHandle
            }
            HStack(spacing: 6) {
                Text(account.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .layoutPriority(-1)
                if isStale {
                    PanelBadge(title: "Stale", icon: "clock.badge.exclamationmark", tint: .orange)
                }
                if account.refreshFailed {
                    PanelBadge(title: "Refresh failed", icon: "exclamationmark.triangle", tint: .red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(QuotaFormatter.readingAge(account.observedAt, now: now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if let moveUp = reorder?.moveUp {
                Button("Move Up", action: moveUp)
            }
            if let moveDown = reorder?.moveDown {
                Button("Move Down", action: moveDown)
            }
        }
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .help("Drag to reorder")
            .draggable(account.id) {
                Text(account.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityHidden(true)
    }
}

struct PanelBadge: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.primary)
        }
        .font(.caption)
        .fixedSize()
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct QuotaRowView: View {
    let quota: UsageQuota
    let now: Date
    let isPinned: Bool
    let onTogglePin: () -> Void

    var body: some View {
        let level = QuotaFormatter.usageLevel(quota)
        let value = QuotaFormatter.cardValue(quota)
        let countdown = QuotaFormatter.resetCountdown(quota.resetsAt, now: now)
        let spokenCountdown = QuotaFormatter.resetCountdown(quota.resetsAt, now: now, spoken: true)
        let spokenDetails: [String?] = [quota.label, value, levelDescription(level), spokenCountdown]
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(quota.label)
                        .font(.callout)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(-1)
                    if let resetsAt = quota.resetsAt, let countdown {
                        resetCountdown(countdown, resetsAt: resetsAt)
                    }
                    HStack(spacing: 4) {
                        if let icon = levelIcon(level) {
                            Image(systemName: icon)
                                .font(.caption)
                                .foregroundStyle(tint(for: level))
                        }
                        Text(value)
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .frame(minWidth: 56, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenDetails.compactMap { $0 }.joined(separator: ", "))

                pinButton
            }

            GeometryReader { geometry in
                Capsule()
                    .fill(.primary.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint(for: level))
                            .frame(width: geometry.size.width * CGFloat(QuotaFormatter.usageFraction(quota)))
                    }
            }
            .frame(height: 5)
            .accessibilityHidden(true)
        }
    }

    private func resetCountdown(_ countdown: String, resetsAt: Date) -> some View {
        HStack(spacing: 4) {
            if resetsAt <= now {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
            Text(countdown)
                .foregroundStyle(resetsAt <= now ? .primary : .secondary)
        }
        .font(.subheadline)
        .fixedSize()
        .help(QuotaFormatter.absoluteTimestamp(resetsAt))
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundStyle(isPinned ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(isPinned ? "Unpin" : "Pin to menu bar")
        .accessibilityLabel(isPinned ? "Unpin \(quota.label)" : "Pin \(quota.label) to Menu Bar")
    }

    private func tint(for level: QuotaUsageLevel) -> Color {
        switch level {
        case .normal: return .accentColor
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func levelIcon(_ level: QuotaUsageLevel) -> String? {
        switch level {
        case .normal: return nil
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private func levelDescription(_ level: QuotaUsageLevel) -> String {
        switch level {
        case .normal: return "Normal Usage"
        case .warning: return "Approaching Limit"
        case .critical: return "Near Limit"
        }
    }
}
#endif
