@testable import DockNet
import XCTest

final class NetworkVPNNotificationTests: XCTestCase {
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

    /// 20. VPN disconnects -> no notification
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

    /// 21. Ethernet -> Wi-Fi while VPN active -> one Wi-Fi notification
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

    /// 22. Wi-Fi -> Ethernet while VPN active -> one Ethernet notification
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

    /// 23. en8 remains healthy when VPN appears -> en8 preserved
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

    /// 24. Multiple healthy Ethernet interfaces under VPN -> preserve previous physical primary
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
}
