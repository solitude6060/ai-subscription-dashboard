import Foundation

public enum UsageQuotaFormat: Hashable, Sendable {
    case count(suffix: String?)
    case percent
    case usd
}

public struct UsageQuota: Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let used: Double
    public let limit: Double
    public let format: UsageQuotaFormat
    public let resetsAt: Date?

    public init(
        id: String,
        label: String,
        used: Double,
        limit: Double,
        format: UsageQuotaFormat,
        resetsAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.used = used
        self.limit = limit
        self.format = format
        self.resetsAt = resetsAt
    }
}

public struct UsageAccount: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let quotas: [UsageQuota]
    public let observedAt: Date?
    public let refreshFailed: Bool

    public init(
        id: String,
        name: String,
        quotas: [UsageQuota],
        observedAt: Date? = nil,
        refreshFailed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.quotas = quotas
        self.observedAt = observedAt
        self.refreshFailed = refreshFailed
    }
}

public struct UsageDashboard: Hashable, Sendable {
    public let accounts: [UsageAccount]

    public init(accounts: [UsageAccount]) {
        self.accounts = accounts
    }
}

public enum UsageClientError: Error, Sendable, Equatable {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingFailed
    case networkError
}

enum UsageContractDecoder {
    static func decode(providersData: Data, snapshotsData: Data) throws -> UsageDashboard {
        let providersRoot: JSONValue
        let snapshotsRoot: JSONValue
        do {
            providersRoot = try JSONDecoder().decode(JSONValue.self, from: providersData)
            snapshotsRoot = try JSONDecoder().decode(JSONValue.self, from: snapshotsData)
        } catch {
            throw UsageClientError.decodingFailed
        }

        guard case .array(let providerItems) = providersRoot,
              case .array(let snapshotItems) = snapshotsRoot
        else {
            throw UsageClientError.decodingFailed
        }

        var snapshotsByProviderId: [String: [String: JSONValue]] = [:]
        for item in snapshotItems {
            guard case .object(let obj) = item,
                  let providerId = nonEmptyString(obj["providerId"])
            else {
                continue
            }
            snapshotsByProviderId[providerId] = obj
        }

        var accounts: [UsageAccount] = []
        for item in providerItems {
            guard case .object(let obj) = item,
                  let providerId = nonEmptyString(obj["providerId"]),
                  case .bool(true) = obj["enabled"]
            else {
                continue
            }

            let name = nonEmptyString(obj["name"]) ?? providerId
            let refreshFailed = hasLastError(in: obj)

            let snapshot = snapshotsByProviderId[providerId]
            let observedAt = snapshot.flatMap { parseISO8601($0["startedAt"]) }
            let quotas = snapshot.map { decodeQuotas(from: $0, providerId: providerId) } ?? []

            accounts.append(
                UsageAccount(
                    id: providerId,
                    name: name,
                    quotas: quotas,
                    observedAt: observedAt,
                    refreshFailed: refreshFailed
                )
            )
        }

        return UsageDashboard(accounts: accounts)
    }

    static func decodeRefreshFailureCount(data: Data) throws -> Int {
        let root: JSONValue
        do {
            root = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw UsageClientError.decodingFailed
        }

        guard case .object(let envelope) = root,
              case .bool(true) = envelope["ok"],
              case .array(let items) = envelope["results"]
        else {
            throw UsageClientError.decodingFailed
        }

        var failedCount = 0
        for item in items {
            guard case .object(let obj) = item,
                  case .bool(let ok) = obj["ok"]
            else {
                throw UsageClientError.decodingFailed
            }
            if !ok {
                failedCount += 1
            }
        }
        return failedCount
    }

    private static func hasLastError(in object: [String: JSONValue]) -> Bool {
        guard let value = object["lastError"] else {
            return false
        }
        switch value {
        case .null:
            return false
        case .string(let message):
            return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    private static func decodeQuotas(from snapshot: [String: JSONValue], providerId: String) -> [UsageQuota] {
        guard case .object(let raw) = snapshot["raw"] else { return [] }

        var occurrences: [String: Int] = [:]
        if case .array(let lines) = raw["lines"] {
            return lines.compactMap(decodeProgressLine).map {
                makeQuota($0, providerId: providerId, occurrences: &occurrences)
            }
        }
        if case .object(let quota) = raw["quota"], let parsed = decodeMiniMaxQuota(quota) {
            return [makeQuota(parsed, providerId: providerId, occurrences: &occurrences)]
        }
        return []
    }

    private struct ParsedQuota {
        let label: String
        let used: Double
        let limit: Double
        let format: UsageQuotaFormat
        let resetsAt: Date?
    }

    private static func makeQuota(
        _ parsed: ParsedQuota,
        providerId: String,
        occurrences: inout [String: Int]
    ) -> UsageQuota {
        occurrences[parsed.label, default: 0] += 1
        let occurrence = occurrences[parsed.label, default: 0]
        let stableID = "\(providerId.utf8.count):\(providerId)\(parsed.label.utf8.count):\(parsed.label):\(occurrence)"
        return UsageQuota(
            id: stableID,
            label: parsed.label,
            used: parsed.used,
            limit: parsed.limit,
            format: parsed.format,
            resetsAt: parsed.resetsAt
        )
    }

    private static func decodeProgressLine(_ value: JSONValue) -> ParsedQuota? {
        guard case .object(let obj) = value,
              nonEmptyString(obj["type"]) == "progress",
              let label = nonEmptyString(obj["label"]),
              let used = finiteNumber(obj["used"]), used >= 0,
              let limit = finiteNumber(obj["limit"]), limit > 0
        else {
            return nil
        }

        let format: UsageQuotaFormat
        if let value = obj["format"] {
            if case .null = value {
                format = .percent
            } else {
                guard let decoded = decodeFormat(value) else { return nil }
                format = decoded
            }
        } else {
            format = .percent
        }
        return ParsedQuota(
            label: label,
            used: used,
            limit: limit,
            format: format,
            resetsAt: parseISO8601(obj["resetsAt"])
        )
    }

    private static func decodeMiniMaxQuota(_ obj: [String: JSONValue]) -> ParsedQuota? {
        guard let used = finiteNumber(obj["used"]), used >= 0,
              let limit = finiteNumber(obj["limit"]), limit > 0
        else { return nil }

        let label = nonEmptyString(obj["label"]) ?? "Usage"
        let format: UsageQuotaFormat = nonEmptyString(obj["format"]) == "count"
            ? .count(suffix: nonEmptyString(obj["suffix"]) ?? "prompts")
            : .percent
        return ParsedQuota(
            label: label, used: used, limit: limit, format: format,
            resetsAt: parseISO8601(obj["resetsAt"])
        )
    }

    private static func decodeFormat(_ value: JSONValue?) -> UsageQuotaFormat? {
        guard let value else { return nil }
        switch value {
        case .string(let kind):
            return mapFormat(kind: kind, suffix: nil)
        case .object(let obj):
            guard let kind = nonEmptyString(obj["kind"] ?? obj["type"]) else {
                return nil
            }
            let suffix = nonEmptyString(obj["suffix"] ?? obj["unit"])
            return mapFormat(kind: kind, suffix: suffix)
        default:
            return nil
        }
    }

    private static func mapFormat(kind: String, suffix: String?) -> UsageQuotaFormat? {
        switch kind.lowercased() {
        case "percent", "percentage":
            return .percent
        case "usd", "dollars", "currency":
            return .usd
        case "count":
            return .count(suffix: suffix)
        default:
            return nil
        }
    }

    private static func nonEmptyString(_ value: JSONValue?) -> String? {
        guard case .string(let str) = value else {
            return nil
        }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func finiteNumber(_ value: JSONValue?) -> Double? {
        let number: Double?
        switch value {
        case .number(let raw): number = raw
        case .string(let raw): number = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        default: number = nil
        }
        guard let number, number.isFinite else { return nil }
        return number
    }

    private static func parseISO8601(_ value: JSONValue?) -> Date? {
        guard let raw = nonEmptyString(value) else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: raw) {
            return date
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: raw)
    }
}

private enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
}
