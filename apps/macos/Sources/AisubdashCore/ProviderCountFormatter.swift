public enum ProviderCountFormatter {
    public static func quotas(_ count: Int) -> String {
        count == 1 ? "1 quota" : "\(count) quotas"
    }

    /// Settings subtitle for a provider row.
    public static func status(quotas quotaCount: Int, details detailCount: Int, refreshFailed: Bool) -> String {
        if quotaCount == 0 {
            return refreshFailed ? "Refresh failed" : "No data"
        }
        let reading = quotas(quotaCount)
        return refreshFailed ? "\(reading) · Refresh failed" : reading
    }

    public static func allHidden(_ count: Int) -> String {
        count == 1 ? "1 provider hidden" : "All \(count) providers hidden"
    }

    public static func hiddenSettingsLabel(_ count: Int) -> String {
        let providers = count == 1 ? "1 Hidden Provider" : "\(count) Hidden Providers"
        return "\(providers). Open Settings"
    }
}
