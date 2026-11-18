@testable import DockNet
import XCTest

@MainActor
final class PresentationPreferencesTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            suiteName = "com.andrewtryder.docknet.tests.presentation.\(UUID().uuidString)"
            testDefaults = UserDefaults(suiteName: suiteName)!
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            testDefaults.removePersistentDomain(forName: suiteName)
            testDefaults = nil
            suiteName = nil
        }
        super.tearDown()
    }

    /// 1. PresentationStyle enum coverage
    func testPresentationStyleCases() {
        XCTAssertEqual(PresentationStyle.allCases.count, 2)
        XCTAssertEqual(PresentationStyle.compact.rawValue, "compact")
        XCTAssertEqual(PresentationStyle.detailed.rawValue, "detailed")
    }

    /// 2. Missing key in UserDefaults defaults to .compact
    func testDefaultPresentationStyleIsCompact() {
        let prefs = PresentationPreferences(defaults: testDefaults)
        XCTAssertEqual(prefs.style, .compact)
    }

    /// 3. Invalid or unknown string in UserDefaults falls back to .compact
    func testInvalidStoredValueFallsBackToCompact() {
        testDefaults.set("unknown_mode_xyz", forKey: PresentationPreferences.userDefaultsKey)
        let prefs = PresentationPreferences(defaults: testDefaults)
        XCTAssertEqual(prefs.style, .compact)
    }

    /// 4. Storing .detailed persists properly
    func testPersistingDetailedStyle() {
        let prefs = PresentationPreferences(defaults: testDefaults)
        prefs.style = .detailed
        XCTAssertEqual(testDefaults.string(forKey: PresentationPreferences.userDefaultsKey), "detailed")
        XCTAssertEqual(prefs.style, .detailed)
    }

    /// 5. Storing .compact persists properly
    func testPersistingCompactStyle() {
        let prefs = PresentationPreferences(defaults: testDefaults)
        prefs.style = .detailed
        XCTAssertEqual(prefs.style, .detailed)

        prefs.style = .compact
        XCTAssertEqual(testDefaults.string(forKey: PresentationPreferences.userDefaultsKey), "compact")
        XCTAssertEqual(prefs.style, .compact)
    }

    /// 6. StatusItemController routes Compact vs Detailed correctly & creates popover lazily
    func testStatusItemControllerRoutingAndLazyCreation() {
        let mockMonitor = MockNetworkMonitor(scenario: "wifi")
        let notificationMgr = NotificationManager(
            scheduler: MockNotificationScheduler(status: .notDetermined),
            userDefaults: testDefaults,
            debounceInterval: 0
        )
        let loginMgr = LoginItemManager()
        let prefs = PresentationPreferences(defaults: testDefaults)
        prefs.style = .compact

        let controller = StatusItemController(
            networkMonitor: mockMonitor,
            notificationManager: notificationMgr,
            loginItemManager: loginMgr,
            presentationPreferences: prefs
        )

        // Compact mode: statusItem has menu, no button action
        XCTAssertNotNil(controller.statusItem.menu)
        XCTAssertNil(controller.statusItem.button?.action)
        // Lazy creation: Detailed popover is NOT created yet
        XCTAssertNil(controller.detailedPopoverController)

        // Switch to Detailed mode
        controller.setPresentationStyle(.detailed)
        XCTAssertNil(controller.statusItem.menu)
        XCTAssertNotNil(controller.statusItem.button?.action)
        // Detailed popover is still nil until status item is clicked!
        XCTAssertNil(controller.detailedPopoverController)

        // Simulate status item click in Detailed mode
        controller.statusItem.button?.performClick(nil)
        XCTAssertNotNil(controller.detailedPopoverController, "Popover controller should be lazily instantiated on click")

        // Switching back to Compact restores NSMenu and clears button action
        controller.setPresentationStyle(.compact)
        XCTAssertNotNil(controller.statusItem.menu)
        XCTAssertNil(controller.statusItem.button?.action)
    }

    func testDetailedStyleControlRoutesThroughCoordinator() {
        let prefs = PresentationPreferences(defaults: testDefaults)
        prefs.style = .compact
        let controller = StatusItemController(
            networkMonitor: MockNetworkMonitor(scenario: "wifi"),
            notificationManager: NotificationManager(
                scheduler: MockNotificationScheduler(status: .notDetermined),
                userDefaults: testDefaults,
                debounceInterval: 0
            ),
            loginItemManager: LoginItemManager(),
            presentationPreferences: prefs
        )
        for _ in 0 ..< 2 {
            controller.selectDetailedStyleAction()
            XCTAssertNil(controller.statusItem.menu)
            XCTAssertNotNil(controller.statusItem.button?.action)
            controller.statusItem.button?.performClick(nil)
            guard let popover = controller.detailedPopoverController,
                  let control = popover.statusViewController.view
                      .descendants(matching: "docknet.presentation.segmented").first as? NSSegmentedControl,
                  let action = control.action
            else {
                XCTFail("Detailed style control was not created")
                return
            }
            control.selectedSegment = 0
            control.sendAction(action, to: control.target)
            XCTAssertEqual(prefs.style, .compact)
            XCTAssertEqual(PresentationPreferences(defaults: testDefaults).style, .compact)
            XCTAssertNotNil(controller.statusItem.menu)
            XCTAssertNil(controller.statusItem.button?.action)
            XCTAssertFalse(popover.isShown)
        }
    }

    /// 7. DetailedStatusViewController correctly populates primary connection and other connections
    func testDetailedStatusViewControllerPopulatesConnectionsWithoutDuplication() {
        let mockMonitor = MockNetworkMonitor(scenario: "oneEthernetReady")
        let notificationMgr = NotificationManager(
            scheduler: MockNotificationScheduler(status: .notDetermined),
            userDefaults: testDefaults,
            debounceInterval: 0
        )
        let loginMgr = LoginItemManager()
        let prefs = PresentationPreferences(defaults: testDefaults)
        prefs.style = .detailed

        let vc = DetailedStatusViewController(
            networkMonitor: mockMonitor,
            notificationManager: notificationMgr,
            loginItemManager: loginMgr,
            presentationPreferences: prefs,
            onStyleChanged: { _ in }
        )

        // Load view hierarchy
        _ = vc.view

        let snapshot = mockMonitor.currentSnapshot
        vc.update(with: snapshot)

        // Verify root view accessibility
        XCTAssertEqual(vc.view.accessibilityIdentifier(), "docknet.detailed")

        // Verify primary card has primary elements
        let primaryViews = vc.view.descendants(matching: "docknet.detailed.primary")
        XCTAssertFalse(primaryViews.isEmpty)

        // Active connection (en8) must be marked as primary
        let en8Primary = vc.view.descendants(matching: "docknet.wired.en8.primary")
        XCTAssertFalse(en8Primary.isEmpty)

        // Other connections container must exist
        let otherContainer = vc.view.descendants(matching: "docknet.detailed.otherConnections")
        XCTAssertFalse(otherContainer.isEmpty)

        // Primary connection (en8) must NOT appear in other connections
        let otherEn8 = otherContainer.first?.descendants(matching: "docknet.wired.en8.name") ?? []
        XCTAssertTrue(otherEn8.isEmpty, "Active primary connection en8 must not appear under OTHER CONNECTIONS")

        // Wi-Fi standby must appear in other connections
        let wifiStandby = otherContainer.first?.descendants(matching: "docknet.wifi.health") ?? []
        XCTAssertFalse(wifiStandby.isEmpty, "Wi-Fi standby should appear under OTHER CONNECTIONS when Ethernet is primary")

        // VPN / tunnel interfaces must never appear anywhere in the detailed view
        XCTAssertTrue(vc.view.descendants(matching: "utun5").isEmpty)
        XCTAssertTrue(vc.view.descendants(matching: "Tailscale").isEmpty)
    }

    /// 8. Switching style via callback persists and notifies
    func testDetailedViewControllerStyleSwitch() throws {
        let mockMonitor = MockNetworkMonitor(scenario: "wifi")
        let notificationMgr = NotificationManager(
            scheduler: MockNotificationScheduler(status: .notDetermined),
            userDefaults: testDefaults,
            debounceInterval: 0
        )
        let loginMgr = LoginItemManager()
        let prefs = PresentationPreferences(defaults: testDefaults)
        prefs.style = .detailed

        var switchedStyle: PresentationStyle?
        let vc = DetailedStatusViewController(
            networkMonitor: mockMonitor,
            notificationManager: notificationMgr,
            loginItemManager: loginMgr,
            presentationPreferences: prefs,
            onStyleChanged: { newStyle in
                switchedStyle = newStyle
            }
        )
        _ = vc.view

        // Find segmented control
        let segControls = vc.view.descendants(matching: "docknet.presentation.segmented")
        guard let seg = segControls.first as? NSSegmentedControl else {
            XCTFail("Segmented control not found")
            return
        }

        XCTAssertEqual(seg.selectedSegment, 1) // Detailed

        // Select compact
        seg.selectedSegment = 0
        try seg.sendAction(XCTUnwrap(seg.action), to: seg.target)

        XCTAssertEqual(prefs.style, .detailed)
        XCTAssertEqual(switchedStyle, .compact)
    }

    /// 9. Compact menu builder adds Display Style submenu with proper checkmarks
    func testCompactMenuBuilderDisplayStyleSubmenu() throws {
        let mockMonitor = MockNetworkMonitor(scenario: "wifi")
        let notificationMgr = NotificationManager(
            scheduler: MockNotificationScheduler(status: .notDetermined),
            userDefaults: testDefaults,
            debounceInterval: 0
        )
        let loginMgr = LoginItemManager()
        let prefs = PresentationPreferences(defaults: testDefaults)
        prefs.style = .compact

        let menu = NSMenu()
        let dummyTarget = NSObject()

        CompactMenuBuilder.build(
            menu: menu,
            snapshot: mockMonitor.currentSnapshot,
            notificationManager: notificationMgr,
            loginItemManager: loginMgr,
            presentationPreferences: prefs,
            target: dummyTarget
        )

        let displayStyleItem = menu.items.first(where: { $0.title == "Display Style" })
        XCTAssertNotNil(displayStyleItem)
        XCTAssertNotNil(displayStyleItem?.submenu)

        let submenu = try XCTUnwrap(displayStyleItem?.submenu)
        let compactItem = submenu.items.first(where: { $0.title == "Compact" })
        let detailedItem = submenu.items.first(where: { $0.title == "Detailed" })

        XCTAssertNotNil(compactItem)
        XCTAssertNotNil(detailedItem)
        XCTAssertEqual(compactItem?.state, .on)
        XCTAssertEqual(detailedItem?.state, .off)

        // Change to detailed and rebuild
        prefs.style = .detailed
        CompactMenuBuilder.build(
            menu: menu,
            snapshot: mockMonitor.currentSnapshot,
            notificationManager: notificationMgr,
            loginItemManager: loginMgr,
            presentationPreferences: prefs,
            target: dummyTarget
        )

        let updatedDisplayStyleItem = menu.items.first(where: { $0.title == "Display Style" })
        let updatedSubmenu = try XCTUnwrap(updatedDisplayStyleItem?.submenu)
        let updatedCompact = updatedSubmenu.items.first(where: { $0.title == "Compact" })
        let updatedDetailed = updatedSubmenu.items.first(where: { $0.title == "Detailed" })

        XCTAssertEqual(updatedCompact?.state, .off)
        XCTAssertEqual(updatedDetailed?.state, .on)
    }

    /// 10. Single shared network state source across Compact and Detailed modes
    func testSharedNetworkMonitorState() {
        let mockMonitor = MockNetworkMonitor(scenario: "wifi")
        let notificationMgr = NotificationManager(
            scheduler: MockNotificationScheduler(status: .notDetermined),
            userDefaults: testDefaults,
            debounceInterval: 0
        )
        let loginMgr = LoginItemManager()
        let prefs = PresentationPreferences(defaults: testDefaults)

        let controller = StatusItemController(
            networkMonitor: mockMonitor,
            notificationManager: notificationMgr,
            loginItemManager: loginMgr,
            presentationPreferences: prefs
        )

        // Verify StatusItemController holds the exact same NetworkMonitor instance
        XCTAssertTrue(controller.networkMonitor === mockMonitor)

        // When monitor snapshot updates to Ethernet, icon updates to ethernetPrimary
        mockMonitor.setScenario("oneEthernetReady")
        controller.updateSnapshot(mockMonitor.currentSnapshot)
        XCTAssertEqual(controller.statusItem.button?.accessibilityLabel(), "DockNet — Ethernet primary")
    }

    /// 11. VPN / tunnel interfaces never appear in Compact NSMenu or Detailed UI
    func testVPNFilteringAcrossBothPresentations() {
        let mockMonitor = MockNetworkMonitor(scenario: "vpnOverEthernet")
        let notificationMgr = NotificationManager(
            scheduler: MockNotificationScheduler(status: .notDetermined),
            userDefaults: testDefaults,
            debounceInterval: 0
        )
        let loginMgr = LoginItemManager()
        let prefs = PresentationPreferences(defaults: testDefaults)

        let snapshot = mockMonitor.currentSnapshot

        // Test Compact Menu
        let menu = NSMenu()
        CompactMenuBuilder.build(
            menu: menu,
            snapshot: snapshot,
            notificationManager: notificationMgr,
            loginItemManager: loginMgr,
            presentationPreferences: prefs,
            target: NSObject()
        )

        for item in menu.items {
            XCTAssertFalse(item.title.contains("utun"), "Compact menu must not contain utun: \(item.title)")
            XCTAssertFalse(item.title.contains("Tailscale"), "Compact menu must not contain Tailscale: \(item.title)")
            XCTAssertFalse(item.title.contains("VPN"), "Compact menu must not contain VPN: \(item.title)")
        }

        // Test Detailed View
        let vc = DetailedStatusViewController(
            networkMonitor: mockMonitor,
            notificationManager: notificationMgr,
            loginItemManager: loginMgr,
            presentationPreferences: prefs,
            onStyleChanged: { _ in }
        )
        _ = vc.view
        vc.update(with: snapshot)

        XCTAssertTrue(vc.view.descendants(matching: "utun5").isEmpty)
        XCTAssertTrue(vc.view.descendants(matching: "Tailscale").isEmpty)
        XCTAssertTrue(vc.view.descendants(matching: "VPN").isEmpty)
    }
}

@MainActor
final class DetailedPresentationLifecycleTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            suiteName = "com.andrewtryder.docknet.tests.lifecycle.\(UUID().uuidString)"
            testDefaults = UserDefaults(suiteName: suiteName)!
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            testDefaults.removePersistentDomain(forName: suiteName)
            testDefaults = nil
            suiteName = nil
        }
        super.tearDown()
    }

    /// 12. CompactMenuBuilder uses valid compile-time selectors handled by StatusItemController
    func testCompactMenuBuilderUsesValidCompileTimeSelectors() throws {
        let mockMonitor = MockNetworkMonitor(scenario: "oneEthernetReady")
        let notificationMgr = NotificationManager(
            scheduler: MockNotificationScheduler(status: .notDetermined),
            userDefaults: testDefaults,
            debounceInterval: 0
        )
        let loginMgr = LoginItemManager()
        let prefs = PresentationPreferences(defaults: testDefaults)
        prefs.style = .compact

        let controller = StatusItemController(
            networkMonitor: mockMonitor,
            notificationManager: notificationMgr,
            loginItemManager: loginMgr,
            presentationPreferences: prefs
        )

        let menu = NSMenu()
        CompactMenuBuilder.build(
            menu: menu,
            snapshot: mockMonitor.currentSnapshot,
            notificationManager: notificationMgr,
            loginItemManager: loginMgr,
            presentationPreferences: prefs,
            target: controller
        )

        let expectedTitles = [
            "Notify on connection changes",
            "Launch at Login",
            "Refresh",
            "Open Network Settings…",
            "About DockNet…",
            "Quit DockNet",
        ]
        for title in expectedTitles {
            let item = try XCTUnwrap(menu.items.first(where: { $0.title == title }), "Missing item \(title)")
            let action = try XCTUnwrap(item.action, "Item \(title) missing action")
            XCTAssertTrue(controller.responds(to: action), "Controller does not respond to \(action) for \(title)")
        }

        let displaySubmenu = try XCTUnwrap(menu.items.first(where: { $0.title == "Display Style" })?.submenu)
        for styleTitle in ["Compact", "Detailed"] {
            let item = try XCTUnwrap(displaySubmenu.items.first(where: { $0.title == styleTitle }))
            let action = try XCTUnwrap(item.action, "Style item \(styleTitle) missing action")
            XCTAssertTrue(controller.responds(to: action), "Controller does not respond to \(action) for \(styleTitle)")
        }
    }

    /// 13. DetailedStatusViewController skips connection rebuild when snapshot is semantically identical
    func testDetailedViewControllerSkipsRebuildForSemanticallyIdenticalSnapshot() {
        let mockMonitor = MockNetworkMonitor(scenario: "oneEthernetReady")
        let notificationMgr = NotificationManager(
            scheduler: MockNotificationScheduler(status: .notDetermined),
            userDefaults: testDefaults,
            debounceInterval: 0
        )
        let prefs = PresentationPreferences(defaults: testDefaults)
        prefs.style = .detailed

        let vc = DetailedStatusViewController(
            networkMonitor: mockMonitor,
            notificationManager: notificationMgr,
            loginItemManager: LoginItemManager(),
            presentationPreferences: prefs,
            onStyleChanged: { _ in }
        )
        _ = vc.view

        let snap1 = mockMonitor.currentSnapshot
        vc.update(with: snap1)
        let primaryBefore = vc.primaryContainer.arrangedSubviews
        let otherBefore = vc.otherContainer.arrangedSubviews
        XCTAssertFalse(primaryBefore.isEmpty)
        XCTAssertFalse(otherBefore.isEmpty)

        // Create a semantically identical snapshot with a later capture timestamp
        let snap2 = NetworkSnapshot(
            wiredInterfaces: snap1.wiredInterfaces,
            wifi: snap1.wifi,
            systemPrimaryInterface: snap1.systemPrimaryInterface,
            systemPrimaryServiceID: snap1.systemPrimaryServiceID,
            systemPrimaryServiceName: snap1.systemPrimaryServiceName,
            physicalTransport: snap1.physicalTransport,
            globalIPv4Router: snap1.globalIPv4Router,
            timestamp: snap1.timestamp.addingTimeInterval(60)
        )
        vc.update(with: snap2)

        let primaryAfterSame = vc.primaryContainer.arrangedSubviews
        let otherAfterSame = vc.otherContainer.arrangedSubviews
        XCTAssertEqual(primaryBefore.count, primaryAfterSame.count)
        XCTAssertEqual(otherBefore.count, otherAfterSame.count)
        for (lhs, rhs) in zip(primaryBefore, primaryAfterSame) {
            XCTAssertTrue(lhs === rhs, "Primary subviews must not rebuild for semantically identical snapshot")
        }
        for (lhs, rhs) in zip(otherBefore, otherAfterSame) {
            XCTAssertTrue(lhs === rhs, "Other subviews must not rebuild for semantically identical snapshot")
        }

        // Update with a genuinely different snapshot
        let differentSnapshot = MockNetworkMonitor.makeSnapshot(for: "wifi")
        vc.update(with: differentSnapshot)
        let primaryAfterChange = vc.primaryContainer.arrangedSubviews
        XCTAssertFalse(primaryAfterChange.isEmpty)
        XCTAssertFalse(primaryBefore.first === primaryAfterChange.first)
    }

    /// 14. DetailedStatusViewController handles many adapters and very long service names in scroll view
    func testDetailedViewControllerHandlesMultipleAdaptersAndLongServiceNames() throws {
        let longName = String(repeating: "Thunderbolt Dock 10GbE Adapter ", count: 3)
        XCTAssertGreaterThan(longName.count, 70)

        let wifi = NetworkInterfaceInfo(
            bsdName: "en0",
            serviceName: "Wi-Fi",
            serviceID: "WIFI-ID",
            serviceOrder: 10,
            enabled: true,
            isLinkActive: true,
            ipv4Addresses: ["192.168.88.148"],
            subnetMasks: ["255.255.255.0"],
            router: "192.168.88.1"
        )

        var wired: [WiredInterfaceState] = []
        for idx in 1 ... 6 {
            let bsd = "en\(idx + 3)"
            let isFirst = (idx == 1)
            wired.append(WiredInterfaceState(
                serviceID: "SVC-\(idx)",
                serviceName: isFirst ? longName : "Dock Ethernet Port \(idx) — Extra Descriptive Name",
                bsdName: bsd,
                enabled: true,
                serviceOrder: idx,
                linkActive: isFirst,
                ipv4Address: isFirst ? "192.168.88.200" : nil,
                gateway: isFirst ? "192.168.88.1" : nil,
                health: isFirst ? .ready : .cableDisconnected,
                isPreferred: isFirst,
                isPrimary: isFirst,
                linkSpeed: isFirst ? "10 Gbps Full Duplex" : nil,
                isHardwarePresent: true
            ))
        }

        let snapshot = NetworkSnapshot(
            wiredInterfaces: wired,
            wifi: wifi,
            systemPrimaryInterface: "en4",
            systemPrimaryServiceID: "SVC-1",
            systemPrimaryServiceName: longName
        )

        let monitor = MockNetworkMonitor(scenario: "wifi")
        monitor.setSnapshot(snapshot)
        let notificationMgr = NotificationManager(
            scheduler: MockNotificationScheduler(status: .notDetermined),
            userDefaults: testDefaults,
            debounceInterval: 0
        )
        let prefs = PresentationPreferences(defaults: testDefaults)
        prefs.style = .detailed

        let vc = DetailedStatusViewController(
            networkMonitor: monitor,
            notificationManager: notificationMgr,
            loginItemManager: LoginItemManager(),
            presentationPreferences: prefs,
            onStyleChanged: { _ in }
        )
        _ = vc.view
        vc.update(with: snapshot)
        vc.view.layoutSubtreeIfNeeded()

        XCTAssertFalse(vc.view.descendants(matching: "docknet.wired.en4.primary").isEmpty)
        for idx in 2 ... 6 {
            let bsd = "en\(idx + 3)"
            XCTAssertFalse(
                vc.otherContainer.descendants(matching: "docknet.wired.\(bsd).name").isEmpty,
                "Missing adapter \(bsd) in otherContainer"
            )
        }

        let scrollView = try XCTUnwrap(vc.view.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView)
        let docView = try XCTUnwrap(scrollView.documentView)
        XCTAssertGreaterThan(docView.fittingSize.height, vc.view.bounds.height, "6 adapters should exceed 480pt and scroll")
    }

    /// 15. Presentation controllers release without retain cycles
    func testPresentationControllersDeallocateCleanly() {
        final class WeakBox<T: AnyObject> {
            weak var value: T?
        }

        let popoverBox = WeakBox<DetailedPopoverController>()
        let vcBox = WeakBox<DetailedStatusViewController>()

        func instantiateAndLoad() {
            let mockMonitor = MockNetworkMonitor(scenario: "wifi")
            let notificationMgr = NotificationManager(
                scheduler: MockNotificationScheduler(status: .notDetermined),
                userDefaults: testDefaults,
                debounceInterval: 0
            )
            let prefs = PresentationPreferences(defaults: testDefaults)
            let popover = DetailedPopoverController(
                networkMonitor: mockMonitor,
                notificationManager: notificationMgr,
                loginItemManager: LoginItemManager(),
                presentationPreferences: prefs,
                onStyleChanged: { _ in }
            )
            _ = popover.statusViewController.view
            popoverBox.value = popover
            vcBox.value = popover.statusViewController
        }

        autoreleasepool {
            instantiateAndLoad()
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(popoverBox.value, "DetailedPopoverController leaked")
        XCTAssertNil(vcBox.value, "DetailedStatusViewController leaked")
    }
}

private extension NSView {
    func descendants(matching identifier: String) -> [NSView] {
        var results: [NSView] = []
        if accessibilityIdentifier() == identifier {
            results.append(self)
        }
        for sub in subviews {
            results.append(contentsOf: sub.descendants(matching: identifier))
        }
        return results
    }
}
