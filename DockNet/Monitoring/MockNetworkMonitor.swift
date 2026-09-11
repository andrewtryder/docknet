import Foundation
import os

/// Deterministic network monitor for UI tests and mock simulations.
public final class MockNetworkMonitor: NetworkMonitoringProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.local.DockNet", category: "MockNetworkMonitor")

    private let lock = NSLock()
    private var _currentSnapshot: NetworkSnapshot
    private var isMonitoring: Bool = false
    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var timerSource: DispatchSourceTimer?
    private let stateFilePath: String?

    public var onSnapshotUpdated: (@Sendable (NetworkSnapshot) -> Void)?

    public init(scenario: String = "wifi", stateFilePath: String? = nil) {
        self.stateFilePath = stateFilePath
        self._currentSnapshot = Self.makeSnapshot(for: scenario)
    }

    public var currentSnapshot: NetworkSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return _currentSnapshot
    }

    public func setSnapshot(_ snapshot: NetworkSnapshot) {
        lock.lock()
        _currentSnapshot = snapshot
        lock.unlock()

        Self.logger.info("MockNetworkMonitor snapshot updated manually")
        onSnapshotUpdated?(snapshot)
    }

    public func setScenario(_ scenario: String) {
        let snapshot = Self.makeSnapshot(for: scenario)
        setSnapshot(snapshot)
    }

    public func startMonitoring() {
        lock.lock()
        guard !isMonitoring else {
            lock.unlock()
            return
        }
        isMonitoring = true
        lock.unlock()

        Self.logger.info("MockNetworkMonitor started")

        // If a state file path is provided, watch it for live dynamic transitions
        if let path = stateFilePath {
            setupFileWatcher(at: path)
        }

        // Fire initial snapshot
        let initial = currentSnapshot
        onSnapshotUpdated?(initial)
    }

    public func stopMonitoring() {
        lock.lock()
        guard isMonitoring else {
            lock.unlock()
            return
        }
        isMonitoring = false
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
        timerSource?.cancel()
        timerSource = nil
        lock.unlock()

        Self.logger.info("MockNetworkMonitor stopped")
    }

    public func refresh() {
        if let path = stateFilePath, let content = try? String(contentsOfFile: path, encoding: .utf8) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            setScenario(trimmed)
        } else {
            let current = currentSnapshot
            onSnapshotUpdated?(current)
        }
    }

    private func setupFileWatcher(at path: String) {
        // Poll every 100ms for state file changes in UI testing mode
        let queue = DispatchQueue(label: "com.local.docknet.mockwatcher", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        var lastContent = ""

        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != lastContent && !trimmed.isEmpty {
                lastContent = trimmed
                Self.logger.info("MockNetworkMonitor read updated state file scenario: \(trimmed)")
                self.setScenario(trimmed)
            }
        }
        timer.resume()
        self.timerSource = timer
    }

    // MARK: - Presets Factory

    public static func makeSnapshot(for scenario: String) -> NetworkSnapshot {
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
        case "wifi":
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

        case "oneEthernetReady":
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

        case "ethernetPrimaryEn6":
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

        case "ethernetDHCP":
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

        case "ethernetDegraded":
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

        case "twoEthernetOneReady":
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

        case "twoEthernetBothReady":
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

        case "ethernetLost":
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

        case "vpnOverEthernet":
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

        case "vpnOverWifi":
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

        case "vpnIdentityChange":
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

        default:
            return makeSnapshot(for: "wifi")
        }
    }
}
