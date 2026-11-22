import Foundation
import XCTest
@testable import AisubdashCore

final class QuotaFormatterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testResetCountdown() {
        let cases: [(TimeInterval, String)] = [
            (1, "in <1m"),
            (59, "in <1m"),
            (60, "in 1m"),
            (45 * 60, "in 45m"),
            (3 * 3600 + 12 * 60, "in 3h 12m"),
            (3 * 3600, "in 3h"),
            (52 * 3600, "in 2d 4h"),
            (48 * 3600 + 59 * 60, "in 2d"),
            (0, "Reset due"),
            (-1, "Reset due"),
        ]
        for (offset, expected) in cases {
            XCTAssertEqual(QuotaFormatter.resetCountdown(now.addingTimeInterval(offset), now: now), expected)
        }
        XCTAssertNil(QuotaFormatter.resetCountdown(nil, now: now))
    }

    func testSpokenResetCountdownDescribesFutureReset() {
        let future = now.addingTimeInterval(3 * 3600 + 12 * 60)
        XCTAssertEqual(QuotaFormatter.resetCountdown(future, now: now, spoken: true), "Resets in 3h 12m")
        XCTAssertEqual(QuotaFormatter.resetCountdown(now.addingTimeInterval(1), now: now, spoken: true), "Resets in <1m")
        XCTAssertEqual(QuotaFormatter.resetCountdown(now, now: now, spoken: true), "Reset due")
        XCTAssertEqual(QuotaFormatter.resetCountdown(now.addingTimeInterval(-1), now: now, spoken: true), "Reset due")
        XCTAssertNil(QuotaFormatter.resetCountdown(nil, now: now, spoken: true))
    }

    func testReadingAge() {
        let cases: [(TimeInterval, String)] = [
            (-1, "<1m ago"),
            (0, "<1m ago"),
            (59, "<1m ago"),
            (5 * 60, "5m ago"),
            (3 * 3600 + 12 * 60, "3h 12m ago"),
            (3 * 3600, "3h ago"),
            (52 * 3600, "2d 4h ago"),
            (48 * 3600, "2d ago"),
        ]
        for (age, expected) in cases {
            XCTAssertEqual(QuotaFormatter.readingAge(now.addingTimeInterval(-age), now: now), expected)
        }
        XCTAssertEqual(QuotaFormatter.readingAge(nil, now: now), "No reading time")
    }

    func testUsageFractionClampsAndHandlesNonPositiveLimits() {
        XCTAssertEqual(QuotaFormatter.usageFraction(quota(used: -4, limit: 100)), 0)
        XCTAssertEqual(QuotaFormatter.usageFraction(quota(used: 125, limit: 100)), 1)
        XCTAssertEqual(QuotaFormatter.usageFraction(quota(used: 82, limit: 100)), 0.82)
        XCTAssertEqual(QuotaFormatter.usageFraction(quota(used: 10, limit: 0)), 0)
        XCTAssertEqual(QuotaFormatter.usageFraction(quota(used: 10, limit: -100)), 0)
    }

    func testUsageLevelUsesTheSameThresholdsForEveryFormat() {
        let formats: [UsageQuotaFormat] = [.percent, .count(suffix: "requests"), .usd]
        for format in formats {
            XCTAssertEqual(QuotaFormatter.usageLevel(quota(used: 699, limit: 1000, format: format)), .normal)
            XCTAssertEqual(QuotaFormatter.usageLevel(quota(used: 700, limit: 1000, format: format)), .warning)
            XCTAssertEqual(QuotaFormatter.usageLevel(quota(used: 899, limit: 1000, format: format)), .warning)
            XCTAssertEqual(QuotaFormatter.usageLevel(quota(used: 900, limit: 1000, format: format)), .critical)
            XCTAssertEqual(QuotaFormatter.usageLevel(quota(used: 25, limit: 0, format: format)), .normal)
        }
    }

    private func quota(used: Double, limit: Double, format: UsageQuotaFormat = .percent) -> UsageQuota {
        UsageQuota(id: "5:codex2:5h:1", label: "5h", used: used, limit: limit, format: format)
    }
}
