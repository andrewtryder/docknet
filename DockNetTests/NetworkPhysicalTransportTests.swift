@testable import DockNet
import XCTest

final class NetworkPhysicalTransportTests: XCTestCase {
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

    // MARK: - Physical Transport & VPN / Overlay Isolation Tests

    /// 14. en6 primary, then utun5 appears -> physical primary remains en6
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

    /// 15. en0 primary, then Tailscale appears -> physical primary remains en0
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

    /// 16. VPN active while en6 disconnects -> physical primary becomes en0
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

    /// 17. VPN active while en6 becomes Ready -> physical primary becomes en6
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

    /// 18. utun5 -> utun6 transition -> no physical transition
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
            if case .physicalPrimaryChanged = $0 {
                return true
            }
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
            if case .physicalPrimaryChanged = $0 {
                return true
            }
            return false
        })
        XCTAssertFalse(physicalChanged, "VPN interface change from utun5 to utun6 must not emit physicalPrimaryChanged")
    }

    // 19. VPN connects -> no notification
}
