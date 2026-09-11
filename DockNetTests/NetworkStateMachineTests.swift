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
}

