import XCTest
@testable import AisubdashCore

final class ProviderCountFormatterTests: XCTestCase {
    func testQuotasUsesSingularForOneQuota() {
        XCTAssertEqual(ProviderCountFormatter.quotas(1), "1 quota")
        XCTAssertEqual(ProviderCountFormatter.quotas(2), "2 quotas")
    }

    func testStatusCountsTextValuesForAnAccountWithoutQuotas() {
        XCTAssertEqual(ProviderCountFormatter.status(quotas: 0, details: 1, refreshFailed: false), "1 value")
        XCTAssertEqual(ProviderCountFormatter.status(quotas: 0, details: 3, refreshFailed: true), "3 values · Refresh failed")
        XCTAssertEqual(ProviderCountFormatter.status(quotas: 2, details: 0, refreshFailed: true), "2 quotas · Refresh failed")
        XCTAssertEqual(ProviderCountFormatter.status(quotas: 0, details: 0, refreshFailed: false), "No data")
        XCTAssertEqual(ProviderCountFormatter.status(quotas: 0, details: 0, refreshFailed: true), "Refresh failed")
    }

    func testAllHiddenUsesSingularForOneProvider() {
        XCTAssertEqual(ProviderCountFormatter.allHidden(1), "1 provider hidden")
        XCTAssertEqual(ProviderCountFormatter.allHidden(2), "All 2 providers hidden")
    }

    func testHiddenSettingsLabelUsesSingularForOneProvider() {
        XCTAssertEqual(ProviderCountFormatter.hiddenSettingsLabel(1), "1 Hidden Provider. Open Settings")
        XCTAssertEqual(ProviderCountFormatter.hiddenSettingsLabel(2), "2 Hidden Providers. Open Settings")
    }
}
