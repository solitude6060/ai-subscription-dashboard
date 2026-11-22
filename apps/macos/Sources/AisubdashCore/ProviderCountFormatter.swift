public enum ProviderCountFormatter {
    public static func quotas(_ count: Int) -> String {
        "\(count) quotas"
    }

    public static func allHidden(_ count: Int) -> String {
        "All \(count) providers hidden"
    }

    public static func hiddenSettingsLabel(_ count: Int) -> String {
        "\(count) Hidden Providers. Open Settings"
    }
}
