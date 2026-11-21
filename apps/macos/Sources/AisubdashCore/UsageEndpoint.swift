import Foundation

public struct UsageEndpoint: Hashable, Sendable {
    public let origin: URL
    public let isLocal: Bool

    public static let local = UsageEndpoint(
        origin: URL(string: "http://127.0.0.1:6736")!,
        isLocal: true
    )

    private init(origin: URL, isLocal: Bool) {
        self.origin = origin
        self.isLocal = isLocal
    }

    public init?(tailscale input: String) {
        return nil
    }
}
