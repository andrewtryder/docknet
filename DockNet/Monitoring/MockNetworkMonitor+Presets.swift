import Foundation

public extension MockNetworkMonitor {
    static func makeSnapshot(for scenario: String) -> NetworkSnapshot {
        let wifi = NetworkInterfaceInfo(
            bsdName: "en0",
            serviceName: "Wi-Fi",
            serviceID: "WIFI-SERVICE-ID",
            serviceOrder: 3,
            enabled: true,
            isLinkActive: true,
            ipv4Addresses: ["192.168.88.148"],
            subnetMasks: ["255.255.255.0"],
            router: "192.168.88.1"
        )

        switch scenario {
        case "wifi": return wifiSnapshot(wifi: wifi)
        case "oneEthernetReady": return oneEthernetReadySnapshot(wifi: wifi)
        case "ethernetPrimaryEn6": return ethernetPrimaryEn6Snapshot(wifi: wifi)
        case "ethernetDHCP": return ethernetDHCPSnapshot(wifi: wifi)
        case "ethernetDegraded": return ethernetDegradedSnapshot(wifi: wifi)
        case "twoEthernetOneReady": return twoEthernetOneReadySnapshot(wifi: wifi)
        case "twoEthernetBothReady": return twoEthernetBothReadySnapshot(wifi: wifi)
        case "ethernetLost": return ethernetLostSnapshot(wifi: wifi)
        case "vpnOverEthernet": return vpnOverEthernetSnapshot(wifi: wifi)
        case "vpnOverWifi": return vpnOverWifiSnapshot(wifi: wifi)
        case "vpnIdentityChange": return vpnIdentityChangeSnapshot(wifi: wifi)
        default: return wifiSnapshot(wifi: wifi)
        }
    }

    private static func wifiSnapshot(wifi: NetworkInterfaceInfo) -> NetworkSnapshot {
        let wiredEn8 = WiredInterfaceState(
            serviceID: "LAN-EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: false,
            ipv4Address: nil,
            subnetMask: nil,
            gateway: nil,
            health: .adapterNotPresent,
            isPreferred: false,
            isPrimary: false,
            linkSpeed: nil,
            isHardwarePresent: false
        )
        return NetworkSnapshot(
            wiredInterfaces: [wiredEn8],
            wifi: wifi,
            primaryInterface: "en0",
            primaryServiceID: "WIFI-SERVICE-ID",
            primaryServiceName: "Wi-Fi",
            globalIPv4Router: "192.168.88.1"
        )
    }

    private static func oneEthernetReadySnapshot(wifi: NetworkInterfaceInfo) -> NetworkSnapshot {
        let wiredEn8 = WiredInterfaceState(
            serviceID: "LAN-EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.42",
            subnetMask: "255.255.255.0",
            gateway: "192.168.88.1",
            health: .ready,
            isPreferred: true,
            isPrimary: true,
            linkSpeed: "1 Gbps Full Duplex",
            isHardwarePresent: true
        )
        return NetworkSnapshot(
            wiredInterfaces: [wiredEn8],
            wifi: wifi,
            primaryInterface: "en8",
            primaryServiceID: "LAN-EN8-ID",
            primaryServiceName: "USB 10/100/1000 LAN",
            globalIPv4Router: "192.168.88.1"
        )
    }

    private static func ethernetPrimaryEn6Snapshot(wifi: NetworkInterfaceInfo) -> NetworkSnapshot {
        let wiredEn6 = WiredInterfaceState(
            serviceID: "LAN-EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 2,
            linkActive: true,
            ipv4Address: "192.168.88.160",
            subnetMask: "255.255.255.0",
            gateway: "192.168.88.1",
            health: .ready,
            isPreferred: true,
            isPrimary: true,
            linkSpeed: "100 Mbps Full Duplex",
            isHardwarePresent: true
        )
        let wiredEn8 = WiredInterfaceState(
            serviceID: "LAN-EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: false,
            ipv4Address: nil,
            subnetMask: nil,
            gateway: nil,
            health: .adapterNotPresent,
            isPreferred: false,
            isPrimary: false,
            linkSpeed: nil,
            isHardwarePresent: false
        )
        return NetworkSnapshot(
            wiredInterfaces: [wiredEn6, wiredEn8],
            wifi: wifi,
            primaryInterface: "en6",
            primaryServiceID: "LAN-EN6-ID",
            primaryServiceName: "USB 10/100/1G/2.5G LAN",
            globalIPv4Router: "192.168.88.1"
        )
    }

    private static func ethernetDHCPSnapshot(wifi: NetworkInterfaceInfo) -> NetworkSnapshot {
        let wiredEn8 = WiredInterfaceState(
            serviceID: "LAN-EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: nil,
            subnetMask: nil,
            gateway: nil,
            health: .obtainingDHCP,
            isPreferred: false,
            isPrimary: false,
            linkSpeed: "1 Gbps Full Duplex",
            isHardwarePresent: true
        )
        return NetworkSnapshot(
            wiredInterfaces: [wiredEn8],
            wifi: wifi,
            primaryInterface: "en0",
            primaryServiceID: "WIFI-SERVICE-ID",
            primaryServiceName: "Wi-Fi",
            globalIPv4Router: "192.168.88.1"
        )
    }

    private static func ethernetDegradedSnapshot(wifi: NetworkInterfaceInfo) -> NetworkSnapshot {
        let wiredEn8 = WiredInterfaceState(
            serviceID: "LAN-EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "169.254.42.10",
            subnetMask: "255.255.0.0",
            gateway: nil,
            health: .degraded,
            isPreferred: false,
            isPrimary: false,
            linkSpeed: "100 Mbps Full Duplex",
            isHardwarePresent: true
        )
        return NetworkSnapshot(
            wiredInterfaces: [wiredEn8],
            wifi: wifi,
            primaryInterface: "en0",
            primaryServiceID: "WIFI-SERVICE-ID",
            primaryServiceName: "Wi-Fi",
            globalIPv4Router: "192.168.88.1"
        )
    }

    private static func twoEthernetOneReadySnapshot(wifi: NetworkInterfaceInfo) -> NetworkSnapshot {
        let monitorEn8 = WiredInterfaceState(
            serviceID: "MONITOR-EN8-ID",
            serviceName: "Monitor Ethernet",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "169.254.10.20",
            subnetMask: "255.255.0.0",
            gateway: nil,
            health: .degraded,
            isPreferred: false,
            isPrimary: false,
            linkSpeed: "1 Gbps Full Duplex",
            isHardwarePresent: true
        )
        let dockEn9 = WiredInterfaceState(
            serviceID: "DOCK-EN9-ID",
            serviceName: "Thunderbolt Dock",
            bsdName: "en9",
            enabled: true,
            serviceOrder: 2,
            linkActive: true,
            ipv4Address: "192.168.88.50",
            subnetMask: "255.255.255.0",
            gateway: "192.168.88.1",
            health: .ready,
            isPreferred: true,
            isPrimary: true,
            linkSpeed: "2.5 Gbps Full Duplex",
            isHardwarePresent: true
        )
        return NetworkSnapshot(
            wiredInterfaces: [monitorEn8, dockEn9],
            wifi: wifi,
            primaryInterface: "en9",
            primaryServiceID: "DOCK-EN9-ID",
            primaryServiceName: "Thunderbolt Dock",
            globalIPv4Router: "192.168.88.1"
        )
    }

    private static func twoEthernetBothReadySnapshot(wifi: NetworkInterfaceInfo) -> NetworkSnapshot {
        let monitorEn8 = WiredInterfaceState(
            serviceID: "MONITOR-EN8-ID",
            serviceName: "Monitor Ethernet",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.42",
            subnetMask: "255.255.255.0",
            gateway: "192.168.88.1",
            health: .ready,
            isPreferred: true,
            isPrimary: true,
            linkSpeed: "1 Gbps Full Duplex",
            isHardwarePresent: true
        )
        let dockEn9 = WiredInterfaceState(
            serviceID: "DOCK-EN9-ID",
            serviceName: "Thunderbolt Dock",
            bsdName: "en9",
            enabled: true,
            serviceOrder: 2,
            linkActive: true,
            ipv4Address: "192.168.88.50",
            subnetMask: "255.255.255.0",
            gateway: "192.168.88.1",
            health: .ready,
            isPreferred: false,
            isPrimary: false,
            linkSpeed: "2.5 Gbps Full Duplex",
            isHardwarePresent: true
        )
        return NetworkSnapshot(
            wiredInterfaces: [monitorEn8, dockEn9],
            wifi: wifi,
            primaryInterface: "en8",
            primaryServiceID: "MONITOR-EN8-ID",
            primaryServiceName: "Monitor Ethernet",
            globalIPv4Router: "192.168.88.1"
        )
    }

    private static func ethernetLostSnapshot(wifi: NetworkInterfaceInfo) -> NetworkSnapshot {
        let wiredEn8 = WiredInterfaceState(
            serviceID: "LAN-EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: false,
            ipv4Address: nil,
            subnetMask: nil,
            gateway: nil,
            health: .cableDisconnected,
            isPreferred: false,
            isPrimary: false,
            linkSpeed: nil,
            isHardwarePresent: true
        )
        return NetworkSnapshot(
            wiredInterfaces: [wiredEn8],
            wifi: wifi,
            primaryInterface: "en0",
            primaryServiceID: "WIFI-SERVICE-ID",
            primaryServiceName: "Wi-Fi",
            globalIPv4Router: "192.168.88.1"
        )
    }

    private static func vpnOverEthernetSnapshot(wifi: NetworkInterfaceInfo) -> NetworkSnapshot {
        let wiredEn6 = WiredInterfaceState(
            serviceID: "LAN-EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.160",
            subnetMask: "255.255.255.0",
            gateway: "192.168.88.1",
            health: .ready,
            isPreferred: true,
            isPrimary: true,
            linkSpeed: "2.5 Gbps Full Duplex",
            isHardwarePresent: true
        )
        return NetworkSnapshot(
            wiredInterfaces: [wiredEn6],
            wifi: wifi,
            systemPrimaryInterface: "utun5",
            systemPrimaryServiceID: "TAILSCALE-TUNNEL-ID",
            systemPrimaryServiceName: "Tailscale",
            physicalTransport: PhysicalTransport(
                kind: .ethernet,
                bsdName: "en6",
                serviceName: "USB 10/100/1G/2.5G LAN",
                ipv4Address: "192.168.88.160"
            ),
            globalIPv4Router: "192.168.88.1"
        )
    }

    private static func vpnOverWifiSnapshot(wifi: NetworkInterfaceInfo) -> NetworkSnapshot {
        let wiredEn8 = WiredInterfaceState(
            serviceID: "LAN-EN8-ID",
            serviceName: "USB 10/100/1000 LAN",
            bsdName: "en8",
            enabled: true,
            serviceOrder: 1,
            linkActive: false,
            ipv4Address: nil,
            subnetMask: nil,
            gateway: nil,
            health: .adapterNotPresent,
            isPreferred: false,
            isPrimary: false,
            linkSpeed: nil,
            isHardwarePresent: false
        )
        return NetworkSnapshot(
            wiredInterfaces: [wiredEn8],
            wifi: wifi,
            systemPrimaryInterface: "utun5",
            systemPrimaryServiceID: "TAILSCALE-TUNNEL-ID",
            systemPrimaryServiceName: "Tailscale",
            physicalTransport: PhysicalTransport(
                kind: .wifi,
                bsdName: "en0",
                serviceName: "Wi-Fi",
                ipv4Address: "192.168.88.148"
            ),
            globalIPv4Router: "192.168.88.1"
        )
    }

    private static func vpnIdentityChangeSnapshot(wifi: NetworkInterfaceInfo) -> NetworkSnapshot {
        let wiredEn6 = WiredInterfaceState(
            serviceID: "LAN-EN6-ID",
            serviceName: "USB 10/100/1G/2.5G LAN",
            bsdName: "en6",
            enabled: true,
            serviceOrder: 1,
            linkActive: true,
            ipv4Address: "192.168.88.160",
            subnetMask: "255.255.255.0",
            gateway: "192.168.88.1",
            health: .ready,
            isPreferred: true,
            isPrimary: true,
            linkSpeed: "2.5 Gbps Full Duplex",
            isHardwarePresent: true
        )
        return NetworkSnapshot(
            wiredInterfaces: [wiredEn6],
            wifi: wifi,
            systemPrimaryInterface: "utun7",
            systemPrimaryServiceID: "TAILSCALE-TUNNEL-ID",
            systemPrimaryServiceName: "Tailscale",
            physicalTransport: PhysicalTransport(
                kind: .ethernet,
                bsdName: "en6",
                serviceName: "USB 10/100/1G/2.5G LAN",
                ipv4Address: "192.168.88.160"
            ),
            globalIPv4Router: "192.168.88.1"
        )
    }
}
