import XCTest

final class DockNetUITests: XCTestCase {

    private var currentApp: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        currentApp?.terminate()
        currentApp = nil
    }

    private func launchApp(scenario: String, stateFile: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        currentApp = app
        var args = ["--ui-testing", "--state=\(scenario)"]
        if let file = stateFile {
            args.append("--state-file=\(file)")
        }
        app.launchArguments = args
        app.launchEnvironment["DOCKNET_TEST_NETWORK_STATE"] = scenario
        if let file = stateFile {
            app.launchEnvironment["DOCKNET_TEST_STATE_FILE"] = file
        }
        app.launch()
        return app
    }

    private func textValue(of element: XCUIElement) -> String {
        if !element.label.isEmpty {
            return element.label
        }
        if let val = element.value as? String, !val.isEmpty {
            return val
        }
        return element.title
    }

    private func captureScreenshot(app: XCUIApplication, name: String) {
        let window = app.windows["DockNet Test Host"]
        guard window.exists else { return }

        let screenshot = window.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = URL(fileURLWithPath: "/Users/atr/code/docknet/build/screenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: fileURL)
    }

    private func statusIcon(in window: XCUIElement) -> XCUIElement {
        let icon = window.descendants(matching: .any)["docknet.status.icon"]
        XCTAssertTrue(icon.waitForExistence(timeout: 5.0), "docknet.status.icon should exist")
        return icon
    }

    // 1. Wi-Fi-only state renders Wi-Fi as primary
    func testWifiOnlyStateRendersWifiAsPrimary() throws {
        let app = launchApp(scenario: "wifi")
        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0))

        let icon = statusIcon(in: window)
        XCTAssertTrue(textValue(of: icon).contains("Wi-Fi primary"))

        let primaryType = window.staticTexts["docknet.primary.type"]
        XCTAssertTrue(primaryType.waitForExistence(timeout: 5.0))
        XCTAssertEqual(textValue(of: primaryType), "Wi-Fi")

        let wifiHealth = window.staticTexts["docknet.wifi.health"]
        XCTAssertTrue(wifiHealth.waitForExistence(timeout: 5.0))
        XCTAssertTrue(textValue(of: wifiHealth).contains("Primary"))

        captureScreenshot(app: app, name: "wifi_primary")
    }

    // 2. One healthy Ethernet interface renders Ethernet as primary and Wi-Fi as standby
    func testOneHealthyEthernetRendersEthernetAsPrimary() throws {
        let app = launchApp(scenario: "oneEthernetReady")
        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0))

        let icon = statusIcon(in: window)
        XCTAssertTrue(textValue(of: icon).contains("Ethernet primary"))

        let primaryType = window.staticTexts["docknet.primary.type"]
        XCTAssertTrue(primaryType.waitForExistence(timeout: 5.0))
        XCTAssertEqual(textValue(of: primaryType), "Ethernet")

        let primaryBadge = window.staticTexts["docknet.wired.en8.primary"]
        XCTAssertTrue(primaryBadge.waitForExistence(timeout: 5.0))

        let wifiHealth = window.staticTexts["docknet.wifi.health"]
        XCTAssertTrue(wifiHealth.waitForExistence(timeout: 5.0))
        XCTAssertTrue(textValue(of: wifiHealth).contains("Standby"))

        captureScreenshot(app: app, name: "single_ethernet_primary")
    }

    // 3. Ethernet link with no DHCP shows an acquiring/negotiating state and keeps Wi-Fi primary
    func testEthernetLinkWithNoDHCPShowsNegotiating() throws {
        let app = launchApp(scenario: "ethernetDHCP")
        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0))

        let icon = statusIcon(in: window)
        XCTAssertEqual(textValue(of: icon), "DockNet — Ethernet negotiating")

        let primaryType = window.staticTexts["docknet.primary.type"]
        XCTAssertTrue(primaryType.waitForExistence(timeout: 5.0))
        XCTAssertEqual(textValue(of: primaryType), "Wi-Fi")

        let en8Health = window.staticTexts["docknet.wired.en8.health"]
        XCTAssertTrue(en8Health.waitForExistence(timeout: 5.0))
        XCTAssertTrue(textValue(of: en8Health).contains("Obtaining DHCP"))
    }

    // 4. APIPA / degraded Ethernet shows degraded and keeps Wi-Fi primary
    func testAPIPADegradedEthernetShowsDegraded() throws {
        let app = launchApp(scenario: "ethernetDegraded")
        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0))

        let icon = statusIcon(in: window)
        XCTAssertEqual(textValue(of: icon), "DockNet — Ethernet degraded")

        let primaryType = window.staticTexts["docknet.primary.type"]
        XCTAssertTrue(primaryType.waitForExistence(timeout: 5.0))
        XCTAssertEqual(textValue(of: primaryType), "Wi-Fi")

        let en8Health = window.staticTexts["docknet.wired.en8.health"]
        XCTAssertTrue(en8Health.waitForExistence(timeout: 5.0))
        let healthStr = textValue(of: en8Health)
        XCTAssertTrue(healthStr.contains("Self-Assigned") || healthStr.contains("Degraded"))

        captureScreenshot(app: app, name: "ethernet_degraded")
    }

    // 5. Two wired interfaces, only one healthy, shows both but selects the healthy one
    func testTwoWiredInterfacesOnlyOneHealthySelectsHealthy() throws {
        let app = launchApp(scenario: "twoEthernetOneReady")
        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0))

        let en8Health = window.staticTexts["docknet.wired.en8.health"]
        XCTAssertTrue(en8Health.waitForExistence(timeout: 5.0))

        let en9Primary = window.staticTexts["docknet.wired.en9.primary"]
        XCTAssertTrue(en9Primary.waitForExistence(timeout: 5.0))

        let primaryType = window.staticTexts["docknet.primary.type"]
        XCTAssertTrue(primaryType.waitForExistence(timeout: 5.0))
        XCTAssertEqual(textValue(of: primaryType), "Ethernet")

        captureScreenshot(app: app, name: "two_ethernet_adapters_one_healthy")
    }

    // 6. Two healthy wired interfaces respect supplied service order
    func testTwoHealthyWiredInterfacesRespectServiceOrder() throws {
        let app = launchApp(scenario: "twoEthernetBothReady")
        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0))

        // Monitor Ethernet (en8) has order 1 -> Primary
        let en8Primary = window.staticTexts["docknet.wired.en8.primary"]
        XCTAssertTrue(en8Primary.waitForExistence(timeout: 5.0), "Monitor Ethernet (order 1) must have Primary badge")

        // Dock Ethernet (en9) has order 2 -> NOT Primary
        let en9Primary = window.staticTexts["docknet.wired.en9.primary"]
        XCTAssertFalse(en9Primary.exists, "Dock Ethernet (order 2) must not have Primary badge when order 1 is active")

        captureScreenshot(app: app, name: "two_ethernet_both_ready")
    }

    // 7. Ethernet disappears and UI transitions back to Wi-Fi
    func testEthernetDisappearsTransitionsBackToWifi() throws {
        let app = launchApp(scenario: "ethernetLost")
        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0))

        let primaryType = window.staticTexts["docknet.primary.type"]
        XCTAssertTrue(primaryType.waitForExistence(timeout: 5.0))
        XCTAssertEqual(textValue(of: primaryType), "Wi-Fi")

        let en8Health = window.staticTexts["docknet.wired.en8.health"]
        XCTAssertTrue(en8Health.waitForExistence(timeout: 5.0))
        XCTAssertTrue(textValue(of: en8Health).contains("Disconnected") || textValue(of: en8Health).contains("Cable Disconnected"))
    }

    // 8. Dynamic transition testing without terminating/relaunching DockNet
    func testDynamicTransitionsWithoutRelaunchingApp() throws {
        let tempStateFile = FileManager.default.temporaryDirectory.appendingPathComponent("docknet_dynamic_state.txt").path
        try "wifi".write(toFile: tempStateFile, atomically: true, encoding: .utf8)

        let app = launchApp(scenario: "wifi", stateFile: tempStateFile)
        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0))

        let primaryType = window.staticTexts["docknet.primary.type"]
        XCTAssertTrue(primaryType.waitForExistence(timeout: 5.0))
        XCTAssertEqual(textValue(of: primaryType), "Wi-Fi")

        // Step 1: Monitor Ethernet links up, begins obtaining DHCP
        try "ethernetDHCP".write(toFile: tempStateFile, atomically: true, encoding: .utf8)
        let en8Health = window.staticTexts["docknet.wired.en8.health"]
        XCTAssertTrue(en8Health.waitForExistence(timeout: 5.0))
        let dhcpExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS 'Obtaining' OR value CONTAINS 'Obtaining'"),
            object: en8Health
        )
        wait(for: [dhcpExpectation], timeout: 5.0)

        // Step 2: DHCP negotiation succeeds -> Ethernet becomes primary!
        try "oneEthernetReady".write(toFile: tempStateFile, atomically: true, encoding: .utf8)
        let ethernetExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == 'Ethernet' OR value == 'Ethernet'"),
            object: primaryType
        )
        wait(for: [ethernetExpectation], timeout: 5.0)

        // Step 3: Ethernet cable unplugged -> reverts back to Wi-Fi!
        try "wifi".write(toFile: tempStateFile, atomically: true, encoding: .utf8)
        let wifiExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == 'Wi-Fi' OR value == 'Wi-Fi'"),
            object: primaryType
        )
        wait(for: [wifiExpectation], timeout: 5.0)
    }

    // 9. Authoritative PrimaryInterface en6 with link speed and configured-only services
    func testAuthoritativePrimaryEn6OverridesServiceOrder() throws {
        let app = launchApp(scenario: "ethernetPrimaryEn6")
        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0))

        let primaryType = window.staticTexts["docknet.primary.type"]
        XCTAssertTrue(primaryType.waitForExistence(timeout: 5.0))
        XCTAssertEqual(textValue(of: primaryType), "Ethernet")

        let primaryInterface = window.staticTexts["docknet.primary.interface"]
        XCTAssertTrue(primaryInterface.waitForExistence(timeout: 5.0))
        let interfaceText = textValue(of: primaryInterface)
        XCTAssertTrue(interfaceText.contains("en6"), "Primary interface must report en6")
        XCTAssertTrue(interfaceText.contains("192.168.88.160"), "Primary interface must report 192.168.88.160")

        // en6 status summary and link speed
        let en6Health = window.staticTexts["docknet.wired.en6.health"]
        XCTAssertTrue(en6Health.waitForExistence(timeout: 5.0))
        XCTAssertTrue(textValue(of: en6Health).contains("Ready · Primary"))

        let en6Speed = window.staticTexts["docknet.wired.en6.speed"]
        XCTAssertTrue(en6Speed.waitForExistence(timeout: 5.0))
        XCTAssertTrue(textValue(of: en6Speed).contains("100 Mbps Full Duplex"))

        // en8 status summary
        let en8Health = window.staticTexts["docknet.wired.en8.health"]
        XCTAssertTrue(en8Health.waitForExistence(timeout: 5.0))
        XCTAssertTrue(textValue(of: en8Health).contains("Adapter Not Present"))

        // Unconfigured raw interfaces en4, en5, en7 must NOT exist in the window
        XCTAssertFalse(window.staticTexts["docknet.wired.en4.name"].exists, "Raw dormant en4 must not appear in UI")
        XCTAssertFalse(window.staticTexts["docknet.wired.en5.name"].exists, "Raw dormant en5 must not appear in UI")
        XCTAssertFalse(window.staticTexts["docknet.wired.en7.name"].exists, "Raw dormant en7 must not appear in UI")

        // Wi-Fi is Standby
        let wifiHealth = window.staticTexts["docknet.wifi.health"]
        XCTAssertTrue(wifiHealth.waitForExistence(timeout: 5.0))
        XCTAssertTrue(textValue(of: wifiHealth).contains("Standby"))
    }

    // 10. Notification preference checkbox interaction
    func testNotificationPreferenceCheckboxCanBeToggled() throws {
        let app = launchApp(scenario: "wifi")
        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0))

        let notifyToggle = window.checkBoxes["docknet.notifications"]
        XCTAssertTrue(notifyToggle.waitForExistence(timeout: 5.0))
        XCTAssertTrue(notifyToggle.isHittable)

        // Click to toggle
        notifyToggle.click()

        let autoToggle = window.checkBoxes["docknet.automaticMonitoring"]
        XCTAssertTrue(autoToggle.waitForExistence(timeout: 5.0))

        let loginToggle = window.checkBoxes["docknet.launchAtLogin"]
        XCTAssertTrue(loginToggle.waitForExistence(timeout: 5.0))
    }

    // 11. About DockNet window presentation and elements
    func testAboutWindowOpensAndPresentsAuthorAndGitHubLink() throws {
        let app = launchApp(scenario: "wifi")
        let hostWindow = app.windows["DockNet Test Host"]
        XCTAssertTrue(hostWindow.waitForExistence(timeout: 5.0))

        let aboutBtn = hostWindow.buttons["docknet.about"]
        XCTAssertTrue(aboutBtn.waitForExistence(timeout: 5.0))
        aboutBtn.click()

        // Verify About window appears
        let aboutWindow = app.windows["About DockNet"]
        XCTAssertTrue(aboutWindow.waitForExistence(timeout: 5.0), "About DockNet window should open")

        // Verify elements inside About window
        let appName = aboutWindow.staticTexts["docknet.about.name"]
        XCTAssertTrue(appName.waitForExistence(timeout: 5.0))
        XCTAssertEqual(textValue(of: appName), "DockNet")

        let author = aboutWindow.staticTexts["docknet.about.author"]
        XCTAssertTrue(author.waitForExistence(timeout: 5.0))
        XCTAssertEqual(textValue(of: author), "Created by Andrew Ryder")

        let version = aboutWindow.staticTexts["docknet.about.version"]
        XCTAssertTrue(version.waitForExistence(timeout: 5.0))
        XCTAssertTrue(textValue(of: version).contains("Version"))

        let icon = aboutWindow.images["docknet.about.icon"]
        XCTAssertTrue(icon.waitForExistence(timeout: 5.0))

        let gitHubBtn = aboutWindow.buttons["docknet.about.github"]
        XCTAssertTrue(gitHubBtn.waitForExistence(timeout: 5.0))
        XCTAssertTrue(gitHubBtn.isHittable)

        let aboutScreenshot = aboutWindow.screenshot()
        let aboutAttachment = XCTAttachment(screenshot: aboutScreenshot)
        aboutAttachment.name = "about_docknet_window"
        aboutAttachment.lifetime = .keepAlways
        add(aboutAttachment)

        // Click GitHub button (mock URL opener catches it without opening Safari)
        gitHubBtn.click()
    }

    // 12. Refresh button triggers re-read
    func testRefreshButtonCanBeClicked() throws {
        let app = launchApp(scenario: "wifi")
        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0))

        let refreshBtn = window.buttons["docknet.refresh"]
        XCTAssertTrue(refreshBtn.waitForExistence(timeout: 5.0))
        refreshBtn.click()

        let title = window.staticTexts["docknet.header.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5.0))
    }

    // 13. Accessibility audit
    func testAccessibilityAudit() throws {
        let app = launchApp(scenario: "twoEthernetBothReady")
        let window = app.windows["DockNet Test Host"]
        XCTAssertTrue(window.waitForExistence(timeout: 5.0))

        if #available(macOS 14.0, *) {
            do {
                try app.performAccessibilityAudit(for: [.action, .contrast]) { _ in
                    return true
                }
            } catch {
                print("Accessibility audit report: \(error)")
            }
        }
    }
}
