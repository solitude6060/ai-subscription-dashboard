import XCTest
@testable import AisubdashCore

final class ProviderCountFormatterTests: XCTestCase {
    func testQuotasUsesSingularForOneQuota() {
        XCTAssertEqual(ProviderCountFormatter.quotas(1), "1 quota")
        XCTAssertEqual(ProviderCountFormatter.quotas(2), "2 quotas")
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
