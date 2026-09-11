import XCTest

final class DockNetLiveUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Non-destructive observational smoke test against the live hardware and real SystemConfiguration monitor.
    func testLiveNetworkEnvironmentSmokeTest() throws {
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

        let dir = URL(fileURLWithPath: "/Users/atr/code/docknet/build/screenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("live_hardware_state.png")
        try? screenshot.pngRepresentation.write(to: fileURL)

        print("--- Live Smoke Test Observation ---")
        print("Observed Primary Connection: \(primaryText)")
        print("Observed Primary Details: \(ifaceText)")
        print("Screenshot written to: \(fileURL.path)")
        print("-----------------------------------")
    }
}
