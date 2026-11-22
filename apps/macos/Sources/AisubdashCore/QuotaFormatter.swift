import Foundation

public enum QuotaUsageLevel: Equatable {
    case normal
    case warning
    case critical
}

public enum QuotaFormatter {
    public static func resetCountdown(_ resetsAt: Date?, now: Date) -> String? { nil }

    public static func readingAge(_ observedAt: Date?, now: Date) -> String { "" }

    public static func usageFraction(_ quota: UsageQuota) -> Double { 0 }

    public static func usageLevel(_ quota: UsageQuota) -> QuotaUsageLevel { .normal }
}
