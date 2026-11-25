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
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("?"),
              !trimmed.contains("#"),
              !trimmed.contains("@")
        else {
            return nil
        }

        guard let components = URLComponents(string: trimmed),
              components.user == nil,
              components.password == nil,
              components.percentEncodedUser == nil,
              components.percentEncodedPassword == nil,
              components.query == nil,
              components.percentEncodedQuery == nil,
              components.fragment == nil,
              components.percentEncodedFragment == nil,
              components.path.isEmpty || components.path == "/"
        else {
            return nil
        }

        guard let scheme = components.scheme?.lowercased(),
              let rawHost = components.host,
              !rawHost.isEmpty
        else {
            return nil
        }

        // Verify authority does not contain a malformed port (e.g. trailing colon or leading zero).
        guard let validatedPort = Self.extractValidatedPort(from: trimmed, componentsPort: components.port) else {
            return nil
        }

        let canonicalHost = rawHost.lowercased()
        switch scheme {
        case "http":
            guard Self.isCanonicalTailnetIPv4(canonicalHost) else {
                return nil
            }
        case "https":
            guard Self.isTailnetServeHost(canonicalHost) else {
                return nil
            }
        default:
            return nil
        }

        var canonical = URLComponents()
        canonical.scheme = scheme
        canonical.host = canonicalHost
        canonical.port = validatedPort
        guard let url = canonical.url else {
            return nil
        }

        self.origin = url
        self.isLocal = false
    }

    private static func extractValidatedPort(from raw: String, componentsPort: Int?) -> Int?? {
        guard let schemeRange = raw.range(of: "://") else {
            return nil
        }
        let afterScheme = raw[schemeRange.upperBound...]
        let authority = afterScheme.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        guard !authority.isEmpty else {
            return nil
        }

        let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 1 {
            guard componentsPort == nil else { return nil }
            return .some(nil)
        }
        guard parts.count == 2 else {
            return nil
        }

        let portString = String(parts[1])
        guard !portString.isEmpty,
              !portString.hasPrefix("0"),
              portString.allSatisfy(\.isASCII),
              portString.allSatisfy(\.isNumber),
              let port = Int(portString),
              (1...65535).contains(port),
              componentsPort == port
        else {
            return nil
        }
        return .some(port)
    }

    private static func isCanonicalTailnetIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else {
            return false
        }

        var values: [Int] = []
        values.reserveCapacity(4)
        for part in octets {
            guard !part.isEmpty,
                  part.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  !(part.count > 1 && part.hasPrefix("0")),
                  let value = Int(part),
                  (0...255).contains(value)
            else {
                return false
            }
            values.append(value)
        }

        return values[0] == 100 && (64...127).contains(values[1])
    }

    private static func isTailnetServeHost(_ host: String) -> Bool {
        guard !host.hasSuffix(".") else {
            return false
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 4,
              labels[labels.count - 2] == "ts",
              labels[labels.count - 1] == "net"
        else {
            return false
        }
        return labels.allSatisfy(isValidDNSLabel)
    }

    private static func isValidDNSLabel(_ label: Substring) -> Bool {
        guard !label.isEmpty,
              label.count <= 63,
              !label.hasPrefix("-"),
              !label.hasSuffix("-")
        else {
            return false
        }
        return label.allSatisfy { ch in
            (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch == "-"
        }
    }
}
