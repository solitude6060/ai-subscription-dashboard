public enum ProviderCountFormatter {
    public static func quotas(_ count: Int) -> String {
        count == 1 ? "1 quota" : "\(count) quotas"
    }

    public static func allHidden(_ count: Int) -> String {
        count == 1 ? "1 provider hidden" : "All \(count) providers hidden"
    }

    public static func hiddenSettingsLabel(_ count: Int) -> String {
        let providers = count == 1 ? "1 Hidden Provider" : "\(count) Hidden Providers"
        return "\(providers). Open Settings"
    }
}
