import XCTest

final class DockNetLiveUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Non-destructive observational smoke test against the live hardware and real SystemConfiguration monitor.
    func testLiveNetworkEnvironmentSmokeTest() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--live-mode"]
        app.launch()

        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0), "DockNet Test Host window should appear")

        // Verify primary connection label is present
        let primaryType = window.staticTexts["docknet.primary.type"]
        XCTAssertTrue(primaryType.waitForExistence(timeout: 3.0), "Primary connection type label should exist")
        let primaryText = primaryType.label
        XCTAssertFalse(primaryText.isEmpty, "Primary connection type should not be empty")

        // Verify primary interface text exists
        let primaryInterface = window.staticTexts["docknet.primary.interface"]
        XCTAssertTrue(primaryInterface.exists)
        let ifaceText = primaryInterface.label
        XCTAssertFalse(ifaceText.isEmpty)

        // Capture screenshot of live state
        let screenshot = window.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "live_hardware_network_state"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("--- Live Smoke Test Observation ---")
        print("Observed Primary Connection: \(primaryText)")
        print("Observed Primary Details: \(ifaceText)")
        print("-----------------------------------")
    }
}
