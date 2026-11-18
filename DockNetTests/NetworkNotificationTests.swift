@testable import DockNet
import UserNotifications
import XCTest

final class NetworkNotificationTests: XCTestCase {
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

    func testNewerTransitionInvalidatesAuthorizationWaitForOlderTransition() async throws {
        let entered = expectation(description: "both authorization lookups started")
        entered.expectedFulfillmentCount = 2
        let scheduler = SuspendedAuthorizationScheduler(entered: entered)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0)
        manager.isPreferenceEnabled = true
        let wifi = makeWifiInfo()
        let wifiSnapshot = NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0")
        manager.processSnapshot(wifiSnapshot)
        let ethernet = WiredInterfaceState(serviceID: "en6", serviceName: "Ethernet", bsdName: "en6", health: .ready)
        manager.processSnapshot(NetworkSnapshot(wiredInterfaces: [ethernet], wifi: wifi, primaryInterface: "en6"))
        manager.processSnapshot(wifiSnapshot)
        await fulfillment(of: [entered], timeout: 5)
        await scheduler.resumeAuthorization()
        try await Task.sleep(nanoseconds: 100_000_000)
        let titles = await scheduler.sentTitles
        XCTAssertEqual(titles, ["Switched to Wi-Fi"])
    }

    func testDisablingPreferenceWinsOverPendingEnableRequest() async throws {
        let entered = expectation(description: "authorization lookup started")
        let scheduler = SuspendedAuthorizationScheduler(entered: entered)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults)
        let enabling = Task { await manager.setPreferenceEnabled(true) }
        await fulfillment(of: [entered], timeout: 5)
        manager.isPreferenceEnabled = false
        await scheduler.resumeAuthorization()
        _ = await enabling.value
        XCTAssertFalse(manager.isPreferenceEnabled)
    }

    func testDisablingNotificationsInvalidatesAwaitingAuthorization() async throws {
        let entered = expectation(description: "authorization requested")
        let scheduler = SuspendedAuthorizationScheduler(entered: entered)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0)
        manager.isPreferenceEnabled = true
        let wifi = makeWifiInfo()
        manager.processSnapshot(NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0"))
        let ethernet = WiredInterfaceState(serviceID: "en6", serviceName: "Ethernet", bsdName: "en6", health: .ready)
        manager.processSnapshot(NetworkSnapshot(wiredInterfaces: [ethernet], wifi: wifi, primaryInterface: "en6"))
        await fulfillment(of: [entered], timeout: 5)
        manager.isPreferenceEnabled = false
        manager.isPreferenceEnabled = true
        await scheduler.resumeAuthorization()
        try await Task.sleep(nanoseconds: 100_000_000)
        let sentCount = await scheduler.sentCount
        XCTAssertEqual(sentCount, 0)
    }

    // MARK: - Notification Manager & Transition Tests

    /// 1. Startup with Wi-Fi primary -> no notification
    func testStartupWithWifiPrimaryNoNotification() throws {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0)
        manager.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let initialSnapshot = NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0")

        manager.processSnapshot(initialSnapshot)

        XCTAssertEqual(scheduler.sentNotifications.count, 0, "Initial startup must not send a notification")
        XCTAssertEqual(manager.previousPrimary?.bsdName, "en0")
    }

    /// 2. Startup with Ethernet primary -> no notification
    func testStartupWithEthernetPrimaryNoNotification() throws {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
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

    /// 3. Wi-Fi -> Ethernet -> one Ethernet notification
    func testWifiToEthernetOneNotification() async throws {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
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

    /// 4. Ethernet -> Wi-Fi -> one Wi-Fi notification
    func testEthernetToWifiOneNotification() async throws {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
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

    /// 5. en8 -> en6 -> one Ethernet-to-Ethernet notification
    func testEthernetToEthernetOneNotification() async throws {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
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

    /// 6. Duplicate primary-state callbacks -> no duplicate notifications
    func testDuplicatePrimaryCallbacksNoDuplicateNotifications() async throws {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
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
        for _ in 1 ... 10 {
            manager.processSnapshot(initialSnapshot)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(scheduler.sentNotifications.count, 0)
    }

    /// 7. Transient flapping inside debounce period -> only final stable transition notified
    func testTransientFlappingInsideDebouncePeriod() async throws {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
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

    /// 8. Notification preference disabled -> no notification
    func testNotificationPreferenceDisabledNoNotification() async throws {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
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

    /// 9. Authorization denied -> no notification
    func testAuthorizationDeniedNoNotification() async throws {
        let scheduler = MockNotificationScheduler(status: .denied)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
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

    /// 10. Authorization granted -> notifications delivered
    func testAuthorizationGrantedNotificationsDelivered() async throws {
        let scheduler = MockNotificationScheduler(status: .notDetermined)
        scheduler.stubbedRequestAuthResult = true

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
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

    /// 11. Connected Wi-Fi while Ethernet primary is represented as Standby
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

    /// 12. Actual system PrimaryInterface overrides service-order inference
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

    /// 13. About View and URL Opening
    @MainActor func testAboutViewAndURLOpening() throws {
        let mockOpener = MockURLOpener()
        let targetURL = try XCTUnwrap(URL(string: "https://github.com/andrewtryder/docknet"))
        XCTAssertTrue(mockOpener.open(targetURL))
        XCTAssertEqual(mockOpener.lastOpenedURL?.absoluteString, "https://github.com/andrewtryder/docknet")
    }
}

private actor SuspendedAuthorizationScheduler: NotificationScheduling {
    let entered: XCTestExpectation
    var continuations: [CheckedContinuation<UNAuthorizationStatus, Never>] = []
    var sentTitles: [String] = []
    var sentCount: Int {
        sentTitles.count
    }

    init(entered: XCTestExpectation) {
        self.entered = entered
    }

    func requestAuthorization() async -> Bool {
        true
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            entered.fulfill()
        }
    }

    func resumeAuthorization() {
        continuations.forEach { $0.resume(returning: .authorized) }
        continuations.removeAll()
    }

    func send(_ notification: DockNetNotification) async {
        sentTitles.append(notification.title)
    }
}
