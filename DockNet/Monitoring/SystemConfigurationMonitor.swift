import Foundation
import SystemConfiguration
import os

/// Event-driven monitor that listens to macOS `SCDynamicStore` network state notifications
/// and dynamically discovers physical wired Ethernet interfaces and macOS service order.
public final class SystemConfigurationMonitor: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.local.DockNet", category: "SystemConfigurationMonitor")

    private let queue: DispatchQueue
    private var dynamicStore: SCDynamicStore?
    private var isRunning: Bool = false
    public let stateMachine: NetworkStateMachine
    public let linkSpeedDetector: any LinkSpeedDetecting

    public var onSnapshotUpdated: (@Sendable (NetworkSnapshot) -> Void)?

    public init(
        stateMachine: NetworkStateMachine = NetworkStateMachine(),
        linkSpeedDetector: any LinkSpeedDetecting = LinkSpeedDetector(),
        queue: DispatchQueue = DispatchQueue(label: "com.local.docknet.scdynamicstore", qos: .utility)
    ) {
        self.stateMachine = stateMachine
        self.linkSpeedDetector = linkSpeedDetector
        self.queue = queue
    }

    deinit {
        stop()
    }

    public func start() {
        queue.async { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.setupDynamicStore()
            self.isRunning = true
            self.triggerSnapshot()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            if let store = self.dynamicStore {
                SCDynamicStoreSetDispatchQueue(store, nil)
                self.dynamicStore = nil
            }
            self.isRunning = false
        }
    }

    public func requestRefresh() {
        queue.async { [weak self] in
            self?.triggerSnapshot()
        }
    }

    private func setupDynamicStore() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: SCDynamicStoreCallBack = { (store, changedKeys, info) in
            guard let info = info else { return }
            let monitor = Unmanaged<SystemConfigurationMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.handleStoreNotification(changedKeys: changedKeys as? [String] ?? [])
        }

        guard let store = SCDynamicStoreCreate(
            kCFAllocatorDefault,
            "com.local.DockNet" as CFString,
            callback,
            &context
        ) else {
            Self.logger.error("Failed to create SCDynamicStore instance")
            return
        }

        self.dynamicStore = store

        let patterns = [
            "State:/Network/Interface/.*/Link" as CFString,
            "State:/Network/Interface/.*/IPv4" as CFString,
            "State:/Network/Global/IPv4" as CFString,
            "Setup:/Network/Service/.*" as CFString
        ] as CFArray

        if !SCDynamicStoreSetNotificationKeys(store, nil, patterns) {
            Self.logger.error("Failed to set notification keys for SCDynamicStore")
        }

        if !SCDynamicStoreSetDispatchQueue(store, queue) {
            Self.logger.error("Failed to assign dispatch queue to SCDynamicStore")
        }
    }

    private func handleStoreNotification(changedKeys: [String]) {
        Self.logger.debug("SCDynamicStore notified with keys: \(changedKeys)")
        triggerSnapshot()
    }

    public func captureSnapshot() -> NetworkSnapshot {
        // 1. Discover all configured wired Ethernet services and Wi-Fi service dynamically
        let discovery = ServiceOrderDiscovery.discoverServices()

        guard let store = dynamicStore else {
            let emptyWifi = NetworkInterfaceInfo(
                bsdName: discovery.wifiService?.bsdName ?? "en0",
                serviceName: discovery.wifiService?.serviceName ?? "Wi-Fi",
                isLinkActive: false
            )
            return NetworkSnapshot(wiredInterfaces: [], wifi: emptyWifi)
        }

        // 2. Global IPv4 state
        var primaryInterface: String? = nil
        var primaryServiceID: String? = nil
        var globalRouter: String? = nil

        let globalKey = "State:/Network/Global/IPv4" as CFString
        if let globalDict = SCDynamicStoreCopyValue(store, globalKey) as? [String: Any] {
            primaryInterface = globalDict["PrimaryInterface"] as? String
            primaryServiceID = globalDict["PrimaryService"] as? String
            globalRouter = globalDict["Router"] as? String
        }

        // 3. Inspect each discovered wired Ethernet service
        var rawWiredInfos: [NetworkInterfaceInfo] = []
        for service in discovery.wiredEthernetServices {
            let ifaceInfo = readInterfaceInfo(
                store: store,
                bsdName: service.bsdName,
                serviceName: service.serviceName,
                serviceID: service.serviceID,
                serviceOrder: service.serviceOrder,
                enabled: service.enabled,
                globalPrimary: primaryInterface,
                globalRouter: globalRouter
            )
            rawWiredInfos.append(ifaceInfo)
        }

        // 4. Evaluate health & determine preferred wired interface via stateMachine
        let evaluatedWiredStates = stateMachine.evaluateWiredInterfaces(
            from: rawWiredInfos,
            primaryInterface: primaryInterface,
            linkSpeedDetector: linkSpeedDetector
        )

        // 5. Inspect Wi-Fi service
        let wifiBSD = discovery.wifiService?.bsdName ?? "en0"
        let wifiName = discovery.wifiService?.serviceName ?? "Wi-Fi"
        let wifiInfo = readInterfaceInfo(
            store: store,
            bsdName: wifiBSD,
            serviceName: wifiName,
            serviceID: discovery.wifiService?.serviceID,
            serviceOrder: discovery.wifiService?.serviceOrder,
            enabled: discovery.wifiService?.enabled ?? true,
            globalPrimary: primaryInterface,
            globalRouter: globalRouter
        )

        // Find primary service name
        var primaryName: String? = nil
        if let pid = primaryServiceID {
            if let match = discovery.wiredEthernetServices.first(where: { $0.serviceID == pid }) {
                primaryName = match.serviceName
            } else if discovery.wifiService?.serviceID == pid {
                primaryName = discovery.wifiService?.serviceName
            }
        }
        if primaryName == nil, let pIface = primaryInterface {
            if let match = evaluatedWiredStates.first(where: { $0.bsdName == pIface }) {
                primaryName = match.serviceName
            } else if pIface == wifiInfo.bsdName {
                primaryName = wifiInfo.serviceName
            }
        }

        return NetworkSnapshot(
            wiredInterfaces: evaluatedWiredStates,
            wifi: wifiInfo,
            primaryInterface: primaryInterface,
            primaryServiceID: primaryServiceID,
            primaryServiceName: primaryName,
            globalIPv4Router: globalRouter,
            timestamp: Date()
        )
    }

    private func triggerSnapshot() {
        let snapshot = captureSnapshot()
        stateMachine.process(snapshot: snapshot)
        onSnapshotUpdated?(snapshot)
    }

    private func readInterfaceInfo(
        store: SCDynamicStore,
        bsdName: String,
        serviceName: String,
        serviceID: String?,
        serviceOrder: Int?,
        enabled: Bool,
        globalPrimary: String?,
        globalRouter: String?
    ) -> NetworkInterfaceInfo {
        // Link status
        var isLinkActive = false
        if !bsdName.isEmpty {
            let linkKey = "State:/Network/Interface/\(bsdName)/Link" as CFString
            if let linkDict = SCDynamicStoreCopyValue(store, linkKey) as? [String: Any] {
                if let active = linkDict["Active"] as? Bool {
                    isLinkActive = active
                } else if let activeNum = linkDict["Active"] as? NSNumber {
                    isLinkActive = activeNum.boolValue
                }
            }
        }

        // IPv4 status
        var ipv4Addresses: [String] = []
        var subnetMasks: [String] = []
        var router: String? = nil

        if !bsdName.isEmpty {
            let ipv4Key = "State:/Network/Interface/\(bsdName)/IPv4" as CFString
            if let ipv4Dict = SCDynamicStoreCopyValue(store, ipv4Key) as? [String: Any] {
                if let addrs = ipv4Dict["Addresses"] as? [String] {
                    ipv4Addresses = addrs
                }
                if let subnets = ipv4Dict["SubnetMasks"] as? [String] {
                    subnetMasks = subnets
                }
                if let r = ipv4Dict["Router"] as? String {
                    router = r
                }
            }
        }

        // Fall back to global router if interface is primary and interface router wasn't listed
        if router == nil && globalPrimary == bsdName {
            router = globalRouter
        }

        let isPresent = !bsdName.isEmpty && if_nametoindex(bsdName) > 0

        return NetworkInterfaceInfo(
            bsdName: bsdName,
            serviceName: serviceName,
            serviceID: serviceID,
            serviceOrder: serviceOrder,
            enabled: enabled,
            isLinkActive: isLinkActive,
            isHardwarePresent: isPresent,
            ipv4Addresses: ipv4Addresses,
            subnetMasks: subnetMasks,
            router: router
        )
    }
}
