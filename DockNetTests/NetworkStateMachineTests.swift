@testable import DockNet
import XCTest

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

    /// 1. Two Ethernet interfaces, neither ready -> Wi-Fi
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

    /// 2. One ready and one degraded -> ready Ethernet preferred
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

    /// 3. Two ready -> service-order winner
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

    /// 4. Preferred Ethernet disappears -> second ready Ethernet becomes preferred
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

    /// 5. All Ethernet disappears -> Wi-Fi
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

    /// 6. Disabled Ethernet service -> ignored
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

    /// 7. VPN/Tailscale/Bridge filtering
    func testExcludedInterfaceFiltering() {
        XCTAssertTrue(ServiceOrderDiscovery.isExcludedInterface(name: "Tailscale", bsdName: "utun3", interfaceType: "VPN"))
        XCTAssertTrue(ServiceOrderDiscovery.isExcludedInterface(name: "Thunderbolt Bridge", bsdName: "bridge0", interfaceType: "Bridge"))
        XCTAssertTrue(ServiceOrderDiscovery.isExcludedInterface(name: "Loopback", bsdName: "lo0", interfaceType: ""))
        XCTAssertTrue(ServiceOrderDiscovery.isExcludedInterface(name: "AWDL", bsdName: "awdl0", interfaceType: ""))

        // Legitimate physical Ethernet must NOT be excluded
        XCTAssertFalse(ServiceOrderDiscovery.isExcludedInterface(name: "USB 10/100/1000 LAN", bsdName: "en8", interfaceType: "Ethernet"))
        XCTAssertFalse(ServiceOrderDiscovery.isExcludedInterface(name: "Dock Ethernet", bsdName: "en9", interfaceType: "Ethernet"))
    }

    /// 8. Dynamic appearance of new Ethernet adapter
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

    /// 9. IP Validation Rules
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

    /// 10. Duplicate notification suppression
    func testDuplicateNotificationSuppression() {
        let sm = NetworkStateMachine()
        let wifi = makeWifiInfo()
        let snapshot = NetworkSnapshot(wiredInterfaces: [], wifi: wifi, primaryInterface: "en0")

        _ = sm.process(snapshot: snapshot)

        for _ in 1 ... 10 {
            let events = sm.process(snapshot: snapshot)
            XCTAssertTrue(events.isEmpty, "Duplicate snapshots must produce 0 events")
        }
    }
}
