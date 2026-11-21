import XCTest
@testable import AisubdashMac

final class ProbeRunnerTests: XCTestCase {
    func testCocoaLaunchArgumentsPassThroughToTheApplication() {
        XCTAssertNil(ProbeRunner(arguments: ["-NSDocumentRevisionsDebugMode", "NO"]))
    }

    func testInvalidProbeArgumentsRetainTheProbeExitStatus() async {
        let probe = ProbeRunner(arguments: ["--probe-tailscale", "https://example.com"])
        let exitCode = await probe?.run()
        XCTAssertEqual(exitCode, 2)
    }
}
