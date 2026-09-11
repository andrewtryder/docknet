import XCTest
@testable import DockNet

final class NetworkStateMachineTests: XCTestCase {

    private func makeWifiInfo(ip: String = "192.168.88.148") -> NetworkInterfaceInfo {
        NetworkInterfaceInfo(
            bsdName: "en0",
            serviceName: "Wi-Fi",
            serviceID: "WIFI-ID",
            serviceOrder: 3,
            enabled: true,
            isLinkActive: true,
            ipv4Addresses: [ip],
            subnetMasks: ["255.255.255.0"],
            router: "192.168.88.1"
        )
    }

    // MARK: - Multi-Interface Selection Tests

    // 1. Two Ethernet interfaces, neither ready -> Wi-Fi
    func testTwoEthernetNeitherReadyFallsBackToWifi() {
        let sm = NetworkStateMachine()
        let wifi = makeWifiInfo()

        let monitorEn8 = NetworkInterfaceInfo(
            bsdName: "en8",
            serviceName: "Monitor Ethernet",
            serviceID: "MONITOR-ID",
            serviceOrder: 1,
            enabled: true,
            isLinkActive: false
        )
        let dockEn9 = NetworkInterfaceInfo(
            bsdName: "en9",
            serviceName: "Dock Ethernet",
            serviceID: "DOCK-ID",
            serviceOrder: 2,
            enabled: true,
            isLinkActive: true,
            ipv4Addresses: [] // link up but no IP
        )

        let evaluated = sm.evaluateWiredInterfaces(from: [monitorEn8, dockEn9])
        let snapshot = NetworkSnapshot(
            wiredInterfaces: evaluated,
            wifi: wifi,
            primaryInterface: "en0",
            primaryServiceID: "WIFI-ID",
            primaryServiceName: "Wi-Fi",
            globalIPv4Router: "192.168.88.1"
        )

        _ = sm.process(snapshot: snapshot)

        XCTAssertNil(snapshot.preferredWiredInterface)
        XCTAssertTrue(snapshot.isWifiPrimary)
        XCTAssertFalse(snapshot.actualPrimaryIsWired)
        XCTAssertEqual(sm.currentPrimaryInterface, "en0")
    }

    // 2. One ready and one degraded -> ready Ethernet preferred
    func testOneReadyOneDegradedSelectsReadyEthernet() {
        let sm = NetworkStateMachine()
        let wifi = makeWifiInfo()

        let monitorEn8 = NetworkInterfaceInfo(
            bsdName: "en8",
            serviceName: "Monitor Ethernet",
            serviceID: "MONITOR-ID",
            serviceOrder: 1,
            enabled: true,
            isLinkActive: true,
            ipv4Addresses: ["169.254.10.20"] // degraded
        )
        let dockEn9 = NetworkInterfaceInfo(
            bsdName: "en9",
            serviceName: "Dock Ethernet",
            serviceID: "DOCK-ID",
            serviceOrder: 2,
            enabled: true,
            isLinkActive: true,
            ipv4Addresses: ["192.168.88.50"],
            router: "192.168.88.1" // ready
        )

        let evaluated = sm.evaluateWiredInterfaces(from: [monitorEn8, dockEn9])
        let snapshot = NetworkSnapshot(
            wiredInterfaces: evaluated,
            wifi: wifi,
            primaryInterface: "en9",
            primaryServiceID: "DOCK-ID",
            primaryServiceName: "Dock Ethernet",
            globalIPv4Router: "192.168.88.1"
        )

        _ = sm.process(snapshot: snapshot)

        XCTAssertNotNil(snapshot.preferredWiredInterface)
        XCTAssertEqual(snapshot.preferredWiredInterface?.bsdName, "en9")
        XCTAssertEqual(snapshot.preferredWiredInterface?.serviceName, "Dock Ethernet")
        XCTAssertTrue(snapshot.actualPrimaryIsWired)
    }

    // 3. Two ready -> service-order winner
    func testTwoReadyEthernetSelectsServiceOrderWinner() {
        let sm = NetworkStateMachine()
        let wifi = makeWifiInfo()

        // Monitor has serviceOrder 1, Dock has serviceOrder 2
        let monitorEn8 = NetworkInterfaceInfo(
            bsdName: "en8",
            serviceName: "Monitor Ethernet",
            serviceID: "MONITOR-ID",
            serviceOrder: 1,
            enabled: true,
            isLinkActive: true,
            ipv4Addresses: ["192.168.88.42"],
            router: "192.168.88.1"
        )
        let dockEn9 = NetworkInterfaceInfo(
            bsdName: "en9",
            serviceName: "Dock Ethernet",
            serviceID: "DOCK-ID",
            serviceOrder: 2,
            enabled: true,
            isLinkActive: true,
            ipv4Addresses: ["192.168.88.50"],
            router: "192.168.88.1"
        )

        let evaluated = sm.evaluateWiredInterfaces(from: [monitorEn8, dockEn9])
        let snapshot = NetworkSnapshot(
            wiredInterfaces: evaluated,
            wifi: wifi,
            primaryInterface: "en8",
            primaryServiceID: "MONITOR-ID",
            primaryServiceName: "Monitor Ethernet",
            globalIPv4Router: "192.168.88.1"
        )

        _ = sm.process(snapshot: snapshot)

        XCTAssertEqual(snapshot.preferredWiredInterface?.bsdName, "en8", "Monitor Ethernet (order 1) must be preferred over Dock Ethernet (order 2)")
        XCTAssertEqual(snapshot.preferredWiredInterface?.serviceID, "MONITOR-ID")
    }

    // 4. Preferred Ethernet disappears -> second ready Ethernet becomes preferred
    func testPreferredEthernetDisappearsSecondReadyBecomesPreferred() {
        let sm = NetworkStateMachine()
        let wifi = makeWifiInfo()

        let monitorEn8 = NetworkInterfaceInfo(
            bsdName: "en8",
            serviceName: "Monitor Ethernet",
            serviceID: "MONITOR-ID",
            serviceOrder: 1,
            enabled: true,
            isLinkActive: true,
            ipv4Addresses: ["192.168.88.42"],
            router: "192.168.88.1"
        )
        let dockEn9 = NetworkInterfaceInfo(
            bsdName: "en9",
            serviceName: "Dock Ethernet",
            serviceID: "DOCK-ID",
            serviceOrder: 2,
            enabled: true,
            isLinkActive: true,
            ipv4Addresses: ["192.168.88.50"],
            router: "192.168.88.1"
        )

        let initialEval = sm.evaluateWiredInterfaces(from: [monitorEn8, dockEn9])
        let initialSnapshot = NetworkSnapshot(
            wiredInterfaces: initialEval,
            wifi: wifi,
            primaryInterface: "en8",
            globalIPv4Router: "192.168.88.1"
        )
        sm.process(snapshot: initialSnapshot)
        XCTAssertEqual(sm.preferredWiredBSD, "en8")

        // Unplug Monitor Ethernet (en8 link drops)
        let monitorEn8Disconnected = NetworkInterfaceInfo(
            bsdName: "en8",
            serviceName: "Monitor Ethernet",
            serviceID: "MONITOR-ID",
            serviceOrder: 1,
            enabled: true,
            isLinkActive: false
        )

        let updatedEval = sm.evaluateWiredInterfaces(from: [monitorEn8Disconnected, dockEn9])
        let updatedSnapshot = NetworkSnapshot(
            wiredInterfaces: updatedEval,
            wifi: wifi,
            primaryInterface: "en9",
            globalIPv4Router: "192.168.88.1"
        )
        let events = sm.process(snapshot: updatedSnapshot)

        XCTAssertEqual(updatedSnapshot.preferredWiredInterface?.bsdName, "en9")
        XCTAssertTrue(events.contains(.preferredWiredChanged(from: "en8", to: "en9")))
        XCTAssertTrue(events.contains(.primaryPathChanged(from: "en8", to: "en9")))
    }

    // 5. All Ethernet disappears -> Wi-Fi
    func testAllEthernetDisappearsFallsBackToWifi() {
        let sm = NetworkStateMachine()
        let wifi = makeWifiInfo()

        let dockEn9 = NetworkInterfaceInfo(
            bsdName: "en9",
            serviceName: "Dock Ethernet",
            serviceID: "DOCK-ID",
            serviceOrder: 2,
            enabled: true,
            isLinkActive: true,
            ipv4Addresses: ["192.168.88.50"],
            router: "192.168.88.1"
        )
        let eval = sm.evaluateWiredInterfaces(from: [dockEn9])
        sm.process(snapshot: NetworkSnapshot(wiredInterfaces: eval, wifi: wifi, primaryInterface: "en9"))
        XCTAssertEqual(sm.preferredWiredBSD, "en9")

        // All disconnected
        let dockEn9Down = NetworkInterfaceInfo(
            bsdName: "en9",
            serviceName: "Dock Ethernet",
            serviceID: "DOCK-ID",
            serviceOrder: 2,
            enabled: true,
            isLinkActive: false
        )
        let downEval = sm.evaluateWiredInterfaces(from: [dockEn9Down])
        let fallbackSnapshot = NetworkSnapshot(
            wiredInterfaces: downEval,
            wifi: wifi,
            primaryInterface: "en0",
            globalIPv4Router: "192.168.88.1"
        )
        let events = sm.process(snapshot: fallbackSnapshot)

        XCTAssertNil(fallbackSnapshot.preferredWiredInterface)
        XCTAssertTrue(fallbackSnapshot.isWifiPrimary)
        XCTAssertTrue(events.contains(.preferredWiredChanged(from: "en9", to: nil)))
        XCTAssertTrue(events.contains(.primaryPathChanged(from: "en9", to: "en0")))
    }

    // 6. Disabled Ethernet service -> ignored
    func testDisabledEthernetServiceIsIgnoredEvenIfReady() {
        let sm = NetworkStateMachine()
        let wifi = makeWifiInfo()

        let disabledEthernet = NetworkInterfaceInfo(
            bsdName: "en6",
            serviceName: "USB 10/100/1G/2.5G LAN",
            serviceID: "DISABLED-ID",
            serviceOrder: 1,
            enabled: false, // user disabled in System Settings
            isLinkActive: true,
            ipv4Addresses: ["192.168.88.99"],
            router: "192.168.88.1"
        )

        let evaluated = sm.evaluateWiredInterfaces(from: [disabledEthernet])
        let snapshot = NetworkSnapshot(
            wiredInterfaces: evaluated,
            wifi: wifi,
            primaryInterface: "en0",
            globalIPv4Router: "192.168.88.1"
        )

        _ = sm.process(snapshot: snapshot)

        XCTAssertNil(snapshot.preferredWiredInterface, "Disabled Ethernet must not be preferred")
        XCTAssertTrue(snapshot.isWifiPrimary)
    }

    // 7. VPN/Tailscale/Bridge filtering
    func testExcludedInterfaceFiltering() {
        XCTAssertTrue(ServiceOrderDiscovery.isExcludedInterface(name: "Tailscale", bsdName: "utun3", interfaceType: "VPN"))
        XCTAssertTrue(ServiceOrderDiscovery.isExcludedInterface(name: "Thunderbolt Bridge", bsdName: "bridge0", interfaceType: "Bridge"))
        XCTAssertTrue(ServiceOrderDiscovery.isExcludedInterface(name: "Loopback", bsdName: "lo0", interfaceType: ""))
        XCTAssertTrue(ServiceOrderDiscovery.isExcludedInterface(name: "AWDL", bsdName: "awdl0", interfaceType: ""))

        // Legitimate physical Ethernet must NOT be excluded
        XCTAssertFalse(ServiceOrderDiscovery.isExcludedInterface(name: "USB 10/100/1000 LAN", bsdName: "en8", interfaceType: "Ethernet"))
        XCTAssertFalse(ServiceOrderDiscovery.isExcludedInterface(name: "Dock Ethernet", bsdName: "en9", interfaceType: "Ethernet"))
    }

    // 8. Dynamic appearance of new Ethernet adapter
    func testNewEthernetAppearsAtRuntimeWithoutRestart() {
        let sm = NetworkStateMachine()
        let wifi = makeWifiInfo()

        // Initially only Wi-Fi
        let initialSnapshot = NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0")
        sm.process(snapshot: initialSnapshot)
        XCTAssertNil(sm.preferredWiredBSD)

        // New adapter en12 plugged in and ready
        let newAdapter = NetworkInterfaceInfo(
            bsdName: "en12",
            serviceName: "Belkin USB-C LAN",
            serviceID: "BELKIN-ID",
            serviceOrder: 1,
            enabled: true,
            isLinkActive: true,
            ipv4Addresses: ["192.168.1.150"],
            router: "192.168.1.1"
        )

        let evaluated = sm.evaluateWiredInterfaces(from: [newAdapter])
        let updatedSnapshot = NetworkSnapshot(
            wiredInterfaces: evaluated,
            wifi: wifi,
            primaryInterface: "en12",
            globalIPv4Router: "192.168.1.1"
        )

        let events = sm.process(snapshot: updatedSnapshot)

        XCTAssertEqual(updatedSnapshot.preferredWiredInterface?.bsdName, "en12")
        XCTAssertTrue(events.contains(.preferredWiredChanged(from: nil, to: "en12")))
        XCTAssertTrue(events.contains(.primaryPathChanged(from: "en0", to: "en12")))
    }

    // 9. IP Validation Rules
    func testIPValidationRules() {
        let apipa = NetworkInterfaceInfo(
            bsdName: "en8",
            serviceName: "Ethernet",
            isLinkActive: true,
            ipv4Addresses: ["169.254.12.34"]
        )
        XCTAssertTrue(apipa.hasLinkLocalIPv4)
        XCTAssertFalse(apipa.hasValidRoutableIPv4)
        XCTAssertFalse(apipa.isIPv4Ready)

        let routableNoRouter = NetworkInterfaceInfo(
            bsdName: "en8",
            serviceName: "Ethernet",
            isLinkActive: true,
            ipv4Addresses: ["10.0.0.15"]
        )
        XCTAssertFalse(routableNoRouter.hasLinkLocalIPv4)
        XCTAssertTrue(routableNoRouter.hasValidRoutableIPv4)
        XCTAssertFalse(routableNoRouter.isIPv4Ready)

        let complete = NetworkInterfaceInfo(
            bsdName: "en8",
            serviceName: "Ethernet",
            isLinkActive: true,
            ipv4Addresses: ["192.168.1.100"],
            router: "192.168.1.1"
        )
        XCTAssertTrue(complete.hasValidRoutableIPv4)
        XCTAssertTrue(complete.isIPv4Ready)
    }

    // 10. Duplicate notification suppression
    func testDuplicateNotificationSuppression() {
        let sm = NetworkStateMachine()
        let wifi = makeWifiInfo()
        let snapshot = NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0")

        _ = sm.process(snapshot: snapshot)

        for _ in 1...10 {
            let events = sm.process(snapshot: snapshot)
            XCTAssertTrue(events.isEmpty, "Duplicate snapshots must produce 0 events")
        }
    }

    // MARK: - Notification Manager & Transition Tests

    // 1. Startup with Wi-Fi primary -> no notification
    func testStartupWithWifiPrimaryNoNotification() {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)")!
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0)
        manager.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let initialSnapshot = NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0")

        manager.processSnapshot(initialSnapshot)

        XCTAssertEqual(scheduler.sentNotifications.count, 0, "Initial startup must not send a notification")
        XCTAssertEqual(manager.previousPrimary?.bsdName, "en0")
    }

    // 2. Startup with Ethernet primary -> no notification
    func testStartupWithEthernetPrimaryNoNotification() {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)")!
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0)
        manager.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let en8 = WiredInterfaceState(
            serviceID: "EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            health: .ready,
            isPrimary: true
        )
        let initialSnapshot = NetworkSnapshot(wiredInterfaces: [en8], wifi: wifi, primaryInterface: "en8")

        manager.processSnapshot(initialSnapshot)

        XCTAssertEqual(scheduler.sentNotifications.count, 0, "Initial startup with Ethernet must not send a notification")
        XCTAssertEqual(manager.previousPrimary?.bsdName, "en8")
    }

    // 3. Wi-Fi -> Ethernet -> one Ethernet notification
    func testWifiToEthernetOneNotification() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)")!
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0)
        manager.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let initialSnapshot = NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0")
        manager.processSnapshot(initialSnapshot)

        // Switch to Ethernet
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            ipv4Address: "192.168.88.160",
            health: .ready,
            isPrimary: true
        )
        let switchedSnapshot = NetworkSnapshot(wiredInterfaces: [en6], wifi: wifi, primaryInterface: "en6")
        manager.processSnapshot(switchedSnapshot)

        // Wait a small moment for async task
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.sentNotifications.count, 1)
        let notification = scheduler.sentNotifications.first
        XCTAssertEqual(notification?.title, "Switched to Ethernet")
        XCTAssertTrue(notification?.body.contains("en6") ?? false)
        XCTAssertTrue(notification?.body.contains("USB 10/100/1G/2.5G LAN") ?? false)
    }

    // 4. Ethernet -> Wi-Fi -> one Wi-Fi notification
    func testEthernetToWifiOneNotification() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)")!
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0)
        manager.isPreferenceEnabled = true

        let wifi = makeWifiInfo(ip: "192.168.88.148")
        let en8 = WiredInterfaceState(
            serviceID: "EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            health: .ready,
            isPrimary: true
        )
        let initialSnapshot = NetworkSnapshot(wiredInterfaces: [en8], wifi: wifi, primaryInterface: "en8")
        manager.processSnapshot(initialSnapshot)

        // Switch to Wi-Fi
        let fallbackSnapshot = NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0")
        manager.processSnapshot(fallbackSnapshot)

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.sentNotifications.count, 1)
        let notification = scheduler.sentNotifications.first
        XCTAssertEqual(notification?.title, "Switched to Wi-Fi")
        XCTAssertTrue(notification?.body.contains("en0") ?? false)
    }

    // 5. en8 -> en6 -> one Ethernet-to-Ethernet notification
    func testEthernetToEthernetOneNotification() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)")!
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0)
        manager.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let en8 = WiredInterfaceState(
            serviceID: "EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            health: .ready,
            isPrimary: true
        )
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            ipv4Address: "192.168.88.160",
            health: .ready,
            isPrimary: true
        )

        let initialSnapshot = NetworkSnapshot(wiredInterfaces: [en8, en6], wifi: wifi, primaryInterface: "en8")
        manager.processSnapshot(initialSnapshot)

        // Switch to en6
        let switchedSnapshot = NetworkSnapshot(wiredInterfaces: [en8, en6], wifi: wifi, primaryInterface: "en6")
        manager.processSnapshot(switchedSnapshot)

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.sentNotifications.count, 1)
        let notification = scheduler.sentNotifications.first
        XCTAssertEqual(notification?.title, "Switched Ethernet connection")
        XCTAssertTrue(notification?.body.contains("en6") ?? false)
    }

    // 6. Duplicate primary-state callbacks -> no duplicate notifications
    func testDuplicatePrimaryCallbacksNoDuplicateNotifications() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)")!
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0)
        manager.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let en8 = WiredInterfaceState(
            serviceID: "EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            health: .ready,
            isPrimary: true
        )
        let initialSnapshot = NetworkSnapshot(wiredInterfaces: [en8], wifi: wifi, primaryInterface: "en8")
        manager.processSnapshot(initialSnapshot)

        // Send 10 identical snapshots
        for _ in 1...10 {
            manager.processSnapshot(initialSnapshot)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(scheduler.sentNotifications.count, 0)
    }

    // 7. Transient flapping inside debounce period -> only final stable transition notified
    func testTransientFlappingInsideDebouncePeriod() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)")!
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0.1)
        manager.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            ipv4Address: "192.168.88.160",
            health: .ready,
            isPrimary: true
        )

        let initialSnapshot = NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0")
        manager.processSnapshot(initialSnapshot)

        // Rapid flapping: en0 -> en6 -> en0 -> en6 -> en6
        let snapWifi = NetworkSnapshot(wiredInterfaces: [en6], wifi: wifi, primaryInterface: "en0")
        let snapEn6 = NetworkSnapshot(wiredInterfaces: [en6], wifi: wifi, primaryInterface: "en6")

        manager.processSnapshot(snapEn6)
        try? await Task.sleep(nanoseconds: 20_000_000)
        manager.processSnapshot(snapWifi)
        try? await Task.sleep(nanoseconds: 20_000_000)
        manager.processSnapshot(snapEn6)
        try? await Task.sleep(nanoseconds: 20_000_000)
        manager.processSnapshot(snapEn6)

        // Wait for debounce window (0.1s + buffer)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(scheduler.sentNotifications.count, 1, "Only final stable transition should be emitted")
        XCTAssertEqual(scheduler.sentNotifications.first?.title, "Switched to Ethernet")
    }

    // 8. Notification preference disabled -> no notification
    func testNotificationPreferenceDisabledNoNotification() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)")!
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0)
        manager.isPreferenceEnabled = false // Explicitly disabled

        let wifi = makeWifiInfo()
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            ipv4Address: "192.168.88.160",
            health: .ready,
            isPrimary: true
        )

        manager.processSnapshot(NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0"))
        manager.processSnapshot(NetworkSnapshot(wiredInterfaces: [en6], wifi: wifi, primaryInterface: "en6"))

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.sentNotifications.count, 0, "No notifications when preference is disabled")
    }

    // 9. Authorization denied -> no notification
    func testAuthorizationDeniedNoNotification() async {
        let scheduler = MockNotificationScheduler(status: .denied)
        let defaults = UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)")!
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0)
        manager.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            ipv4Address: "192.168.88.160",
            health: .ready,
            isPrimary: true
        )

        manager.processSnapshot(NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0"))
        manager.processSnapshot(NetworkSnapshot(wiredInterfaces: [en6], wifi: wifi, primaryInterface: "en6"))

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.sentNotifications.count, 0, "No notifications when authorization is denied")
    }

    // 10. Authorization granted -> notifications delivered
    func testAuthorizationGrantedNotificationsDelivered() async {
        let scheduler = MockNotificationScheduler(status: .notDetermined)
        scheduler.stubbedRequestAuthResult = true

        let defaults = UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)")!
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0)

        let status = await manager.setPreferenceEnabled(true)
        XCTAssertEqual(status, .authorized)
        XCTAssertTrue(manager.isPreferenceEnabled)
        XCTAssertEqual(scheduler.requestAuthorizationCallCount, 1)

        let wifi = makeWifiInfo()
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            ipv4Address: "192.168.88.160",
            health: .ready,
            isPrimary: true
        )

        manager.processSnapshot(NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0"))
        manager.processSnapshot(NetworkSnapshot(wiredInterfaces: [en6], wifi: wifi, primaryInterface: "en6"))

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.sentNotifications.count, 1)
    }

    // 11. Connected Wi-Fi while Ethernet primary is represented as Standby
    func testConnectedWifiWhileEthernetPrimaryIsStandby() {
        let wifi = makeWifiInfo()
        let en8 = WiredInterfaceState(
            serviceID: "EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            health: .ready,
            isPrimary: true
        )

        let snapshot = NetworkSnapshot(wiredInterfaces: [en8], wifi: wifi, primaryInterface: "en8")

        XCTAssertTrue(snapshot.actualPrimaryIsWired)
        XCTAssertFalse(snapshot.isWifiPrimary)
        XCTAssertTrue(wifi.isLinkActive)
        XCTAssertEqual(snapshot.wifiStatusText, "Connected · Standby")
    }

    // 12. Actual system PrimaryInterface overrides service-order inference
    func testActualSystemPrimaryInterfaceOverridesServiceOrder() {
        let wifi = makeWifiInfo()

        // Service order: en8 has order 1, en6 has order 2.
        // However, actual macOS PrimaryInterface is en6!
        let en8 = WiredInterfaceState(
            serviceID: "EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.42",
            gateway: "192.168.88.1",
            health: .ready,
            isPreferred: true,
            isPrimary: false
        )
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 2,
            linkActive: true,
            ipv4Address: "192.168.88.160",
            gateway: "192.168.88.1",
            health: .ready,
            isPreferred: false,
            isPrimary: true
        )

        let snapshot = NetworkSnapshot(
            wiredInterfaces: [en8, en6],
            wifi: wifi,
            primaryInterface: "en6",
            primaryServiceID: "EN6-ID",
            primaryServiceName: "USB 10/100/1G/2.5G LAN"
        )

        XCTAssertTrue(snapshot.actualPrimaryIsWired)
        XCTAssertEqual(snapshot.activePrimaryWiredInterface?.bsdName, "en6")
        XCTAssertEqual(snapshot.activePrimaryWiredInterface?.serviceName, "USB 10/100/1G/2.5G LAN")
        // en8 is preferred in service order, but en6 is the authoritative primary interface
        XCTAssertEqual(snapshot.preferredWiredInterface?.bsdName, "en8")
    }

    // 13. About View and URL Opening
    func testAboutViewAndURLOpening() {
        let mockOpener = MockURLOpener()
        let targetURL = URL(string: "https://github.com/andrewtryder/docknet")!
        XCTAssertTrue(mockOpener.open(targetURL))
        XCTAssertEqual(mockOpener.lastOpenedURL?.absoluteString, "https://github.com/andrewtryder/docknet")
    }

    // MARK: - Physical Transport & VPN / Overlay Isolation Tests

    // 14. en6 primary, then utun5 appears -> physical primary remains en6
    func testEn6PrimaryThenUtunAppearsPreservesEn6() {
        let wifi = makeWifiInfo()
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.160",
            gateway: "192.168.88.1",
            health: .ready,
            isPreferred: true,
            isPrimary: true
        )

        // Initial snapshot without VPN
        let snap1 = NetworkSnapshot(
            wiredInterfaces: [en6],
            wifi: wifi,
            systemPrimaryInterface: "en6"
        )
        XCTAssertEqual(snap1.physicalPrimaryInterface, "en6")
        XCTAssertTrue(snap1.actualPrimaryIsWired)

        // Tailscale connects: system primary becomes utun5
        let resolved = PhysicalTransportResolver.resolve(
            systemPrimaryInterface: "utun5",
            systemPrimaryServiceName: "Tailscale",
            wiredInterfaces: [en6],
            wifi: wifi,
            previousPhysicalPrimaryBSD: "en6"
        )
        XCTAssertEqual(resolved.kind, .ethernet)
        XCTAssertEqual(resolved.bsdName, "en6")

        let snap2 = NetworkSnapshot(
            wiredInterfaces: [en6],
            wifi: wifi,
            systemPrimaryInterface: "utun5",
            systemPrimaryServiceName: "Tailscale",
            physicalTransport: resolved
        )
        XCTAssertEqual(snap2.physicalPrimaryInterface, "en6")
        XCTAssertTrue(snap2.actualPrimaryIsWired)
        XCTAssertFalse(snap2.isWifiPrimary)
    }

    // 15. en0 primary, then Tailscale appears -> physical primary remains en0
    func testEn0PrimaryThenTailscaleAppearsPreservesEn0() {
        let wifi = makeWifiInfo()
        let en8Disconnected = WiredInterfaceState(
            serviceID: "EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: false,
            health: .cableDisconnected
        )

        let resolved = PhysicalTransportResolver.resolve(
            systemPrimaryInterface: "utun5",
            systemPrimaryServiceName: "Tailscale",
            wiredInterfaces: [en8Disconnected],
            wifi: wifi,
            previousPhysicalPrimaryBSD: "en0"
        )
        XCTAssertEqual(resolved.kind, .wifi)
        XCTAssertEqual(resolved.bsdName, "en0")

        let snap = NetworkSnapshot(
            wiredInterfaces: [en8Disconnected],
            wifi: wifi,
            systemPrimaryInterface: "utun5",
            physicalTransport: resolved
        )
        XCTAssertEqual(snap.physicalPrimaryInterface, "en0")
        XCTAssertTrue(snap.isWifiPrimary)
        XCTAssertFalse(snap.actualPrimaryIsWired)
    }

    // 16. VPN active while en6 disconnects -> physical primary becomes en0
    func testVPNActiveWhileEn6DisconnectsResolvesToEn0() {
        let wifi = makeWifiInfo()
        let en6Disconnected = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 1,
            linkActive: false,
            health: .cableDisconnected
        )

        // Previous was en6, but en6 is now cableDisconnected
        let resolved = PhysicalTransportResolver.resolve(
            systemPrimaryInterface: "utun5",
            systemPrimaryServiceName: "Tailscale",
            wiredInterfaces: [en6Disconnected],
            wifi: wifi,
            previousPhysicalPrimaryBSD: "en6"
        )
        XCTAssertEqual(resolved.kind, .wifi)
        XCTAssertEqual(resolved.bsdName, "en0")
    }

    // 17. VPN active while en6 becomes Ready -> physical primary becomes en6
    func testVPNActiveWhileEn6BecomesReadyPromotesToEn6() {
        let wifi = makeWifiInfo()
        let en6Ready = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.160",
            gateway: "192.168.88.1",
            health: .ready
        )

        // Previous physical primary was en0 (Wi-Fi), system primary is utun5
        let resolved = PhysicalTransportResolver.resolve(
            systemPrimaryInterface: "utun5",
            systemPrimaryServiceName: "Tailscale",
            wiredInterfaces: [en6Ready],
            wifi: wifi,
            previousPhysicalPrimaryBSD: "en0"
        )
        XCTAssertEqual(resolved.kind, .ethernet)
        XCTAssertEqual(resolved.bsdName, "en6")
    }

    // 18. utun5 -> utun6 transition -> no physical transition
    func testUtun5ToUtun6TransitionProducesNoPhysicalTransition() {
        let sm = NetworkStateMachine(initialPhysicalPrimary: "en6")
        let wifi = makeWifiInfo()
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.160",
            gateway: "192.168.88.1",
            health: .ready
        )

        let snap1 = NetworkSnapshot(
            wiredInterfaces: [en6],
            wifi: wifi,
            systemPrimaryInterface: "utun5",
            physicalTransport: PhysicalTransport(kind: .ethernet, bsdName: "en6")
        )
        let events1 = sm.process(snapshot: snap1)
        XCTAssertFalse(events1.contains(where: {
            if case .physicalPrimaryChanged = $0 { return true }
            return false
        }))

        // VPN changes tunnel number: utun5 -> utun6
        let snap2 = NetworkSnapshot(
            wiredInterfaces: [en6],
            wifi: wifi,
            systemPrimaryInterface: "utun6",
            physicalTransport: PhysicalTransport(kind: .ethernet, bsdName: "en6")
        )
        let events2 = sm.process(snapshot: snap2)

        // Verifies no physicalPrimaryChanged event was emitted
        let physicalChanged = events2.contains(where: {
            if case .physicalPrimaryChanged = $0 { return true }
            return false
        })
        XCTAssertFalse(physicalChanged, "VPN interface change from utun5 to utun6 must not emit physicalPrimaryChanged")
    }

    // 19. VPN connects -> no notification
    func testVPNConnectsProducesNoNotification() async {
        let mockScheduler = MockNotificationScheduler(status: .authorized)
        let mgr = NotificationManager(scheduler: mockScheduler, userDefaults: UserDefaults(suiteName: "test.vpn.1") ?? .standard, debounceInterval: 0)
        mgr.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.160",
            gateway: "192.168.88.1",
            health: .ready
        )

        // 1. Initial snapshot on en6 (quiet startup)
        let initialSnap = NetworkSnapshot(
            wiredInterfaces: [en6],
            wifi: wifi,
            systemPrimaryInterface: "en6",
            physicalTransport: PhysicalTransport(kind: .ethernet, bsdName: "en6")
        )
        mgr.processSnapshot(initialSnap)
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(mockScheduler.sentNotifications.count, 0)

        // 2. Tailscale connects (system: utun5, physical remains en6)
        let vpnSnap = NetworkSnapshot(
            wiredInterfaces: [en6],
            wifi: wifi,
            systemPrimaryInterface: "utun5",
            systemPrimaryServiceName: "Tailscale",
            physicalTransport: PhysicalTransport(kind: .ethernet, bsdName: "en6")
        )
        mgr.processSnapshot(vpnSnap)
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(mockScheduler.sentNotifications.count, 0, "VPN connect must not emit notification")
    }

    // 20. VPN disconnects -> no notification
    func testVPNDisconnectsProducesNoNotification() async {
        let mockScheduler = MockNotificationScheduler(status: .authorized)
        let mgr = NotificationManager(scheduler: mockScheduler, userDefaults: UserDefaults(suiteName: "test.vpn.2") ?? .standard, debounceInterval: 0)
        mgr.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.160",
            gateway: "192.168.88.1",
            health: .ready
        )

        // Initial snapshot under VPN (quiet startup)
        let initialSnap = NetworkSnapshot(
            wiredInterfaces: [en6],
            wifi: wifi,
            systemPrimaryInterface: "utun5",
            physicalTransport: PhysicalTransport(kind: .ethernet, bsdName: "en6")
        )
        mgr.processSnapshot(initialSnap)
        try? await Task.sleep(nanoseconds: 10_000_000)

        // VPN disconnects: system primary returns to en6
        let normalSnap = NetworkSnapshot(
            wiredInterfaces: [en6],
            wifi: wifi,
            systemPrimaryInterface: "en6",
            physicalTransport: PhysicalTransport(kind: .ethernet, bsdName: "en6")
        )
        mgr.processSnapshot(normalSnap)
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(mockScheduler.sentNotifications.count, 0, "VPN disconnect must not emit notification")
    }

    // 21. Ethernet -> Wi-Fi while VPN active -> one Wi-Fi notification
    func testEthernetToWifiWhileVPNActiveEmitsOneNotification() async {
        let mockScheduler = MockNotificationScheduler(status: .authorized)
        let mgr = NotificationManager(scheduler: mockScheduler, userDefaults: UserDefaults(suiteName: "test.vpn.3") ?? .standard, debounceInterval: 0)
        mgr.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let en6Connected = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.160",
            gateway: "192.168.88.1",
            health: .ready
        )

        // Initial state: en6 under VPN
        let snap1 = NetworkSnapshot(
            wiredInterfaces: [en6Connected],
            wifi: wifi,
            systemPrimaryInterface: "utun5",
            physicalTransport: PhysicalTransport(kind: .ethernet, bsdName: "en6")
        )
        mgr.processSnapshot(snap1)
        try? await Task.sleep(nanoseconds: 10_000_000)

        // en6 disconnects while VPN remains active
        let en6Disconnected = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 1,
            linkActive: false,
            health: .cableDisconnected
        )
        let snap2 = NetworkSnapshot(
            wiredInterfaces: [en6Disconnected],
            wifi: wifi,
            systemPrimaryInterface: "utun5",
            physicalTransport: PhysicalTransport(kind: .wifi, bsdName: "en0")
        )
        mgr.processSnapshot(snap2)
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(mockScheduler.sentNotifications.count, 1)
        XCTAssertEqual(mockScheduler.sentNotifications.first?.title, "Switched to Wi-Fi")
    }

    // 22. Wi-Fi -> Ethernet while VPN active -> one Ethernet notification
    func testWifiToEthernetWhileVPNActiveEmitsOneNotification() async {
        let mockScheduler = MockNotificationScheduler(status: .authorized)
        let mgr = NotificationManager(scheduler: mockScheduler, userDefaults: UserDefaults(suiteName: "test.vpn.4") ?? .standard, debounceInterval: 0)
        mgr.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let en6Disconnected = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 1,
            linkActive: false,
            health: .cableDisconnected
        )

        // Initial state: Wi-Fi under VPN
        let snap1 = NetworkSnapshot(
            wiredInterfaces: [en6Disconnected],
            wifi: wifi,
            systemPrimaryInterface: "utun5",
            physicalTransport: PhysicalTransport(kind: .wifi, bsdName: "en0")
        )
        mgr.processSnapshot(snap1)
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Ethernet reconnects while VPN remains active
        let en6Connected = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.160",
            gateway: "192.168.88.1",
            health: .ready
        )
        let snap2 = NetworkSnapshot(
            wiredInterfaces: [en6Connected],
            wifi: wifi,
            systemPrimaryInterface: "utun5",
            physicalTransport: PhysicalTransport(kind: .ethernet, bsdName: "en6", serviceName: "USB 10/100/1G/2.5G LAN")
        )
        mgr.processSnapshot(snap2)
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(mockScheduler.sentNotifications.count, 1)
        XCTAssertEqual(mockScheduler.sentNotifications.first?.title, "Switched to Ethernet")
    }

    // 23. en8 remains healthy when VPN appears -> en8 preserved
    func testEn8RemainsHealthyWhenVPNAppearsPreservesEn8() {
        let wifi = makeWifiInfo()
        let en8 = WiredInterfaceState(
            serviceID: "EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.42",
            gateway: "192.168.88.1",
            health: .ready
        )

        let resolved = PhysicalTransportResolver.resolve(
            systemPrimaryInterface: "utun5",
            wiredInterfaces: [en8],
            wifi: wifi,
            previousPhysicalPrimaryBSD: "en8"
        )
        XCTAssertEqual(resolved.kind, .ethernet)
        XCTAssertEqual(resolved.bsdName, "en8")
    }

    // 24. Multiple healthy Ethernet interfaces under VPN -> preserve previous physical primary
    func testMultipleHealthyEthernetUnderVPNPreservesPreviousPhysicalPrimary() {
        let wifi = makeWifiInfo()
        let en8 = WiredInterfaceState(
            serviceID: "EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.42",
            gateway: "192.168.88.1",
            health: .ready
        )
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 2,
            linkActive: true,
            ipv4Address: "192.168.88.160",
            gateway: "192.168.88.1",
            health: .ready
        )

        // Previous physical was en6 even though en8 is order 1
        let resolved = PhysicalTransportResolver.resolve(
            systemPrimaryInterface: "utun5",
            wiredInterfaces: [en8, en6],
            wifi: wifi,
            previousPhysicalPrimaryBSD: "en6"
        )
        XCTAssertEqual(resolved.bsdName, "en6", "Must preserve last-known healthy physical primary")
    }

    // 25. If previous Ethernet disappears under VPN -> select next healthy Ethernet by service order
    func testPreviousEthernetDisappearsUnderVPNSelectsNextByServiceOrder() {
        let wifi = makeWifiInfo()
        let en8 = WiredInterfaceState(
            serviceID: "EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.42",
            gateway: "192.168.88.1",
            health: .ready
        )
        let en6Disconnected = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 2,
            linkActive: false,
            health: .cableDisconnected
        )

        // Previous was en6, but en6 is disconnected; en8 is ready
        let resolved = PhysicalTransportResolver.resolve(
            systemPrimaryInterface: "utun5",
            wiredInterfaces: [en8, en6Disconnected],
            wifi: wifi,
            previousPhysicalPrimaryBSD: "en6"
        )
        XCTAssertEqual(resolved.bsdName, "en8", "Must select next healthy Ethernet by service order")
    }

    // 26. Virtual and overlay interfaces never qualify as physical transports
    func testVirtualAndOverlayInterfacesNeverQualifyAsPhysical() {
        let virtualInterfaces = [
            "utun0", "utun5", "utun9",
            "ipsec0", "ipsec3",
            "ppp0", "ppp1",
            "gif0", "stf0",
            "bridge0", "bridge100",
            "awdl0", "llw0", "lo0"
        ]

        for iface in virtualInterfaces {
            XCTAssertTrue(
                PhysicalTransportResolver.isVirtualOrOverlay(bsdName: iface),
                "\(iface) must be recognized as virtual/overlay"
            )
        }

        XCTAssertTrue(PhysicalTransportResolver.isVirtualOrOverlay(bsdName: "en8", serviceName: "Tailscale"))
        XCTAssertTrue(PhysicalTransportResolver.isVirtualOrOverlay(bsdName: "en8", serviceName: "Thunderbolt Bridge"))
        XCTAssertFalse(PhysicalTransportResolver.isVirtualOrOverlay(bsdName: "en6", serviceName: "USB 10/100/1G/2.5G LAN"))
        XCTAssertFalse(PhysicalTransportResolver.isVirtualOrOverlay(bsdName: "en0", serviceName: "Wi-Fi"))
    }

    // 27. VPN interface can never satisfy an Ethernet-ready test
    func testVPNInterfaceCanNeverSatisfyEthernetReady() {
        let wifi = makeWifiInfo()
        let en8Degraded = WiredInterfaceState(
            serviceID: "EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "169.254.10.20",
            health: .degraded
        )

        // System primary is utun5 with a valid public IP
        let resolved = PhysicalTransportResolver.resolve(
            systemPrimaryInterface: "utun5",
            systemPrimaryServiceName: "Tailscale",
            wiredInterfaces: [en8Degraded],
            wifi: wifi
        )

        XCTAssertNotEqual(resolved.kind, .ethernet)
        XCTAssertEqual(resolved.kind, .wifi)
        XCTAssertEqual(resolved.bsdName, "en0")
    }
}


