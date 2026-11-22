import Foundation

public enum QuotaUsageLevel: Equatable {
    case normal
    case warning
    case critical
}

public enum QuotaFormatter {
    public static func compactValue(_ quota: UsageQuota) -> String {
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

    public static func detailedValue(_ quota: UsageQuota) -> String {
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

    public static func absoluteTimestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    public static func relativeAge(from earlier: Date, to now: Date) -> String {
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

    public static func resetCountdown(_ resetsAt: Date?, now: Date) -> String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return "Reset due" }
        return "in \(shortDuration(seconds))"
    }

    public static func readingAge(_ observedAt: Date?, now: Date) -> String {
        guard let observedAt else { return "No reading time" }
        return "\(shortDuration(now.timeIntervalSince(observedAt))) ago"
    }

    public static func usageFraction(_ quota: UsageQuota) -> Double {
        guard quota.limit > 0 else { return 0 }
        return min(1, max(0, quota.used / quota.limit))
    }

    public static func usageLevel(_ quota: UsageQuota) -> QuotaUsageLevel {
        let fraction = usageFraction(quota)
        if fraction >= 0.90 { return .critical }
        if fraction >= 0.70 { return .warning }
        return .normal
    }

    private static func shortDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "<1m" }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 {
            let remainingHours = hours % 24
            return remainingHours == 0 ? "\(days)d" : "\(days)d \(remainingHours)h"
        }
        if hours > 0 {
            let remainingMinutes = minutes % 60
            return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes)m"
    }

    private static func formatNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
