@testable import DockNet
import XCTest

final class NetworkEdgeCaseTests: XCTestCase {
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

    /// 26. Virtual and overlay interfaces never qualify as physical transports
    func testVirtualAndOverlayInterfacesNeverQualifyAsPhysical() {
        let virtualInterfaces = [
            "utun0", "utun5", "utun9",
            "ipsec0", "ipsec3",
            "ppp0", "ppp1",
            "gif0", "stf0",
            "bridge0", "bridge100",
            "awdl0", "llw0", "lo0",
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

    /// 27. VPN interface can never satisfy an Ethernet-ready test
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

    /// 28. Debounce cancellation: A -> B -> A produces zero notifications
    func testDebounceReturnsToOriginalCancelsWorkItemProducesZeroNotifications() async throws {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0.15)
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

        // Transient flip to en6
        let snapEn6 = NetworkSnapshot(wiredInterfaces: [en6], wifi: wifi, primaryInterface: "en6")
        manager.processSnapshot(snapEn6)

        // Rapid bounce back to en0 before debounce expires (30ms < 150ms)
        try? await Task.sleep(nanoseconds: 30_000_000)
        let snapWifiAgain = NetworkSnapshot(wiredInterfaces: [en6], wifi: wifi, primaryInterface: "en0")
        manager.processSnapshot(snapWifiAgain)

        // Wait past debounce interval (200ms > 150ms)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(scheduler.sentNotifications.count, 0, "A -> B -> A within debounce must produce 0 notifications")
        XCTAssertEqual(manager.previousPrimary?.bsdName, "en0")
    }

    /// 29. Debounce switching through intermediate: A -> B -> C produces single notification
    func testDebounceTransitioningThroughIntermediateProducesSingleNotification() async throws {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.docknet.\(UUID().uuidString)"))
        let manager = NotificationManager(scheduler: scheduler, userDefaults: defaults, debounceInterval: 0.15)
        manager.isPreferenceEnabled = true

        let wifi = makeWifiInfo()
        let en6 = WiredInterfaceState(
            serviceID: "EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            ipv4Address: "192.168.88.160",
            health: .ready
        )
        let en8 = WiredInterfaceState(
            serviceID: "EN8-ID",
            serviceName: "Thunderbolt Ethernet",
            bsdName: "en8",
            ipv4Address: "192.168.88.170",
            health: .ready,
            isPrimary: true
        )

        let initialSnapshot = NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0")
        manager.processSnapshot(initialSnapshot)

        // Rapid flip to en6, then to en8
        let snapEn6 = NetworkSnapshot(wiredInterfaces: [en6], wifi: wifi, primaryInterface: "en6")
        manager.processSnapshot(snapEn6)

        try? await Task.sleep(nanoseconds: 30_000_000)
        let snapEn8 = NetworkSnapshot(wiredInterfaces: [en6, en8], wifi: wifi, primaryInterface: "en8")
        manager.processSnapshot(snapEn8)

        // Wait past debounce interval
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(scheduler.sentNotifications.count, 1, "A -> B -> C within debounce must produce exactly 1 notification")
        XCTAssertEqual(scheduler.sentNotifications.first?.title, "Switched to Ethernet")
        XCTAssertTrue(scheduler.sentNotifications.first?.body.contains("en8") == true)
        XCTAssertEqual(manager.previousPrimary?.bsdName, "en8")
    }

    /// 30. Pure link speed formatter tests
    func testLinkSpeedFormattingPureFunction() {
        // 1 Gbps Full Duplex: subtype 16 (IFM_1000_T), IFM_ETHER (0x20), IFM_FDX (0x00100000)
        let word1G = DarwinIfMediaCompatibility.ethernet | 16 | DarwinIfMediaCompatibility.fullDuplex
        XCTAssertEqual(LinkSpeedDetector.formatLinkSpeed(activeWord: word1G), "1 Gbps Full Duplex")

        // 2.5 Gbps Full Duplex: subtype 22 (IFM_2500_T)
        let word25G = DarwinIfMediaCompatibility.ethernet | 22 | DarwinIfMediaCompatibility.fullDuplex
        XCTAssertEqual(LinkSpeedDetector.formatLinkSpeed(activeWord: word25G), "2.5 Gbps Full Duplex")

        // 10 Gbps Full Duplex: subtype 21 (IFM_10G_T)
        let word10G = DarwinIfMediaCompatibility.ethernet | 21 | DarwinIfMediaCompatibility.fullDuplex
        XCTAssertEqual(LinkSpeedDetector.formatLinkSpeed(activeWord: word10G), "10 Gbps Full Duplex")

        // 100 Mbps Half Duplex: subtype 6 (IFM_100_TX), no FDX
        let word100MHalf = DarwinIfMediaCompatibility.ethernet | 6
        XCTAssertEqual(LinkSpeedDetector.formatLinkSpeed(activeWord: word100MHalf), "100 Mbps Half Duplex")

        // Non-Ethernet media type -> nil
        let nonEther = Int32(0x0000_0040) | 16
        XCTAssertNil(LinkSpeedDetector.formatLinkSpeed(activeWord: nonEther))

        // Unknown subtype -> nil
        let unknownSubtype = DarwinIfMediaCompatibility.ethernet | 99
        XCTAssertNil(LinkSpeedDetector.formatLinkSpeed(activeWord: unknownSubtype))
    }

    func testWifiServiceSelectionHonorsEnabledAndServiceOrder() {
        func wifi(_ id: String, _ enabled: Bool, _ order: Int?) -> ServiceOrderDiscovery.DiscoveredService {
            ServiceOrderDiscovery.DiscoveredService(serviceID: id, serviceName: id, bsdName: "en0",
                                                    interfaceType: "IEEE80211", enabled: enabled, serviceOrder: order)
        }
        XCTAssertTrue(ServiceOrderDiscovery.isPreferredWiFi(wifi("a", true, 2), over: wifi("b", true, 3)))
        XCTAssertTrue(ServiceOrderDiscovery.isPreferredWiFi(wifi("b", true, 3), over: wifi("a", false, 1)))
        XCTAssertFalse(ServiceOrderDiscovery.isPreferredWiFi(wifi("b", false, 1), over: wifi("a", true, 3)))
        XCTAssertTrue(ServiceOrderDiscovery.isPreferredWiFi(wifi("a", true, nil), over: wifi("b", true, nil)))
    }

    func testSystemSelectedEthernetDoesNotRequireIPv4Gateway() {
        let wifi = makeWifiInfo()
        let ethernet = WiredInterfaceState(serviceID: "lan", serviceName: "Ethernet", bsdName: "en8",
                                           enabled: true, linkActive: true, ipv4Address: "192.0.2.5",
                                           health: .configured)
        XCTAssertEqual(NetworkStateMachine.evaluateEthernetState(isLinkActive: true, ipv4Address: "192.0.2.5", router: nil), .configured)
        let transport = PhysicalTransportResolver.resolve(systemPrimaryInterface: "en8",
                                                          wiredInterfaces: [ethernet], wifi: wifi)
        XCTAssertEqual(transport.bsdName, "en8")
        XCTAssertEqual(transport.kind, .ethernet)
        XCTAssertFalse(ethernet.isReady, "A selected route does not imply IPv4 gateway readiness")
    }

    func testDisabledWifiIsNotSelectedAsFallback() {
        let wifi = NetworkInterfaceInfo(bsdName: "en0", serviceName: "Wi-Fi", enabled: false, isLinkActive: true)
        XCTAssertEqual(PhysicalTransportResolver.resolve(systemPrimaryInterface: "utun0", wiredInterfaces: [], wifi: wifi), .none)
    }

    func testRemovedInterfaceDoesNotRetainHealthOnReconnect() {
        let machine = NetworkStateMachine()
        let wired = WiredInterfaceState(serviceID: "en8", serviceName: "Ethernet", bsdName: "en8",
                                        linkActive: true, health: .ready)
        let wifi = makeWifiInfo()
        machine.process(snapshot: NetworkSnapshot(wiredInterfaces: [wired], wifi: wifi))
        XCTAssertEqual(machine.health(for: "en8"), .ready)
        machine.process(snapshot: NetworkSnapshot(wiredInterfaces: [], wifi: wifi))
        XCTAssertEqual(machine.health(for: "en8"), .disconnected)
        let reconnected = NetworkInterfaceInfo(bsdName: "en8", serviceName: "Ethernet", isLinkActive: true)
        let freshHealth = NetworkStateMachine().evaluateWiredInterfaces(from: [reconnected]).first?.health
        XCTAssertEqual(machine.evaluateWiredInterfaces(from: [reconnected]).first?.health, freshHealth)
    }

    func testLinkSpeedExtendedSubtypeEncoding() {
        // IFM_X_SUBTYPE from the macOS SDK's net/if_media.h.
        let cases: [(Int32, String?)] = [
            (3, "10 Mbps"), (6, "100 Mbps"), (16, "1 Gbps"),
            (22, "2.5 Gbps"), (23, "5 Gbps"), (21, "10 Gbps"),
            (32, "2.5 Gbps"), (41, "1 Gbps"), (52, "100 Mbps"),
            (59, "10 Gbps"), (62, "100 Mbps"), (64, "5 Gbps"),
            (17, nil), (37, nil), (99, nil),
        ]
        for (subtype, expected) in cases {
            let encoded = (subtype & 0x1F) | ((subtype & 0x1E0) << 11)
            for fullDuplex in [false, true] {
                let word = DarwinIfMediaCompatibility.ethernet | encoded
                    | (fullDuplex ? DarwinIfMediaCompatibility.fullDuplex : 0)
                let suffix = fullDuplex ? " Full Duplex" : " Half Duplex"
                XCTAssertEqual(LinkSpeedDetector.formatLinkSpeed(activeWord: word), expected.map { $0 + suffix },
                               "subtype \(subtype), full duplex \(fullDuplex)")
            }
        }
    }

    /// 31. ServiceOrderDiscovery exclusion helper tests
    func testDiscoveredServiceExcludesVirtualInterfaces() {
        XCTAssertTrue(ServiceOrderDiscovery.isExcludedInterface(name: "Tailscale", bsdName: "utun5", interfaceType: "Other"))
        XCTAssertTrue(ServiceOrderDiscovery.isExcludedInterface(name: "Thunderbolt Bridge", bsdName: "bridge0", interfaceType: "Ethernet"))
        XCTAssertTrue(ServiceOrderDiscovery.isExcludedInterface(name: "VPN Service", bsdName: "ppp0", interfaceType: "PPP"))
        XCTAssertTrue(ServiceOrderDiscovery.isExcludedInterface(name: "Apple Wireless Direct Link", bsdName: "awdl0", interfaceType: "Other"))
        XCTAssertFalse(ServiceOrderDiscovery.isExcludedInterface(name: "USB 10/100/1G/2.5G LAN", bsdName: "en6", interfaceType: "Ethernet"))
    }
}
