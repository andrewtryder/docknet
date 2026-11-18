import Foundation
import os
import SystemConfiguration

/// Event-driven monitor that listens to macOS `SCDynamicStore` network state notifications
/// and dynamically discovers physical wired Ethernet interfaces, Wi-Fi, and macOS service order,
/// estimating the underlying physical transport without interference from VPNs.
/// Mutable monitor state is confined to queue; callback registration and delivery tokens use a lock.
/// Callbacks run in order on a separate queue and are never invoked while a lock is held.
public final class SystemConfigurationMonitor: @unchecked Sendable {
    private final class CallbackContext {
        weak var monitor: SystemConfigurationMonitor?
        init(_ monitor: SystemConfigurationMonitor) {
            self.monitor = monitor
        }
    }

    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "SystemConfigurationMonitor")

    private let queue = DispatchQueue(label: "com.andrewtryder.docknet.scdynamicstore", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    private let deliveryQueue = DispatchQueue(label: "com.andrewtryder.docknet.snapshot-delivery", qos: .utility)
    private let callbackLock = NSLock()
    private var deliveryGeneration: UInt64 = 0
    private var callback: (@Sendable (NetworkSnapshot) -> Void)?
    private var dynamicStore: SCDynamicStore?
    private var isRunning: Bool = false
    private var cachedDiscovery: ServiceOrderDiscovery.DiscoveryResult?
    private var coalesceWorkItem: DispatchWorkItem?
    private var lastDeliveredSnapshot: NetworkSnapshot?

    public let stateMachine: NetworkStateMachine
    public let linkSpeedDetector: any LinkSpeedDetecting

    public var onSnapshotUpdated: (@Sendable (NetworkSnapshot) -> Void)? {
        get { callbackLock.lock(); defer { callbackLock.unlock() }; return callback }
        set { callbackLock.lock(); defer { callbackLock.unlock() }; callback = newValue }
    }

    public init(
        stateMachine: NetworkStateMachine = NetworkStateMachine(),
        linkSpeedDetector: any LinkSpeedDetecting = LinkSpeedDetector()
    ) {
        self.stateMachine = stateMachine
        self.linkSpeedDetector = linkSpeedDetector
        queue.setSpecific(key: queueKey, value: true)
    }

    deinit {
        stop()
    }

    private func onQueue<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return operation()
        }
        return queue.sync(execute: operation)
    }

    public func start() {
        onQueue {
            guard !isRunning, setupDynamicStore() else { return }
            isRunning = true
            callbackLock.lock()
            deliveryGeneration &+= 1
            callbackLock.unlock()
            triggerSnapshot()
        }
    }

    public func stop() {
        onQueue {
            isRunning = false
            callbackLock.lock()
            deliveryGeneration &+= 1
            callbackLock.unlock()
            coalesceWorkItem?.cancel()
            coalesceWorkItem = nil
            if let store = dynamicStore {
                SCDynamicStoreSetDispatchQueue(store, nil)
                dynamicStore = nil
            }
            cachedDiscovery = nil
            lastDeliveredSnapshot = nil
        }
    }

    public func requestRefresh() {
        queue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.cachedDiscovery = nil
            self.coalesceWorkItem?.cancel()
            self.coalesceWorkItem = nil
            self.triggerSnapshot()
        }
    }

    private func setupDynamicStore() -> Bool {
        let box = CallbackContext(self)
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { info in
                UnsafeRawPointer(Unmanaged<CallbackContext>.fromOpaque(info).retain().toOpaque())
            },
            release: { info in
                Unmanaged<CallbackContext>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let callback: SCDynamicStoreCallBack = { _, changedKeys, info in
            guard let info = info,
                  let monitor = Unmanaged<CallbackContext>.fromOpaque(info).takeUnretainedValue().monitor else { return }
            monitor.handleStoreNotification(changedKeys: changedKeys as? [String] ?? [])
        }
        guard let store = SCDynamicStoreCreate(kCFAllocatorDefault, "com.andrewtryder.DockNet" as CFString,
                                               callback, &context)
        else {
            Self.logger.error("Failed to create SCDynamicStore instance")
            return false
        }

        let patterns = [
            "State:/Network/Interface/.*/Link" as CFString,
            "State:/Network/Interface/.*/IPv4" as CFString,
            "State:/Network/Interface/.*/IPv6" as CFString,
            "State:/Network/Service/.*/IPv4" as CFString,
            "State:/Network/Global/IPv4" as CFString,
            "State:/Network/Global/IPv6" as CFString,
            "Setup:/Network/Service/.*" as CFString,
        ] as CFArray

        guard SCDynamicStoreSetNotificationKeys(store, nil, patterns) else {
            Self.logger.error("Failed to set notification keys for SCDynamicStore")
            return false
        }
        guard SCDynamicStoreSetDispatchQueue(store, queue) else {
            Self.logger.error("Failed to assign dispatch queue to SCDynamicStore")
            return false
        }
        dynamicStore = store
        return true
    }

    static func selectPrimary(ipv4: [String: Any]?, ipv6: [String: Any]?) -> (interface: String?, service: String?) {
        let selected = (ipv4?["PrimaryInterface"] as? String) != nil ? ipv4 : ipv6
        return (selected?["PrimaryInterface"] as? String, selected?["PrimaryService"] as? String)
    }

    private func handleStoreNotification(changedKeys: [String]) {
        guard isRunning else { return }
        Self.logger.debug("SCDynamicStore notified with keys: \(changedKeys)")

        // Invalidate cached service discovery if service setup changed
        if changedKeys.contains(where: { $0.hasPrefix("Setup:/") }) {
            Self.logger.debug("Service setup key changed; invalidating discovery cache")
            cachedDiscovery = nil
        }

        // Coalesce burst notifications over 35ms
        coalesceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.triggerSnapshot()
        }
        coalesceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + .milliseconds(35), execute: workItem)
    }

    public func captureSnapshot() -> NetworkSnapshot {
        onQueue { captureSnapshotOnQueue() }
    }

    private func captureSnapshotOnQueue() -> NetworkSnapshot {
        // 1. Discover configured services (cached until Setup keys change)
        let discovery: ServiceOrderDiscovery.DiscoveryResult
        if let cached = cachedDiscovery {
            discovery = cached
        } else {
            let fresh = ServiceOrderDiscovery.discoverServices()
            cachedDiscovery = fresh
            discovery = fresh
        }

        guard let store = dynamicStore else {
            let emptyWifi = NetworkInterfaceInfo(
                bsdName: discovery.wifiService?.bsdName ?? "en0",
                serviceName: discovery.wifiService?.serviceName ?? "Wi-Fi",
                isLinkActive: false
            )
            return NetworkSnapshot(wiredInterfaces: [], wifi: emptyWifi)
        }

        // Prefer the IPv4 primary when present, otherwise use the IPv6 primary.
        let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let ipv6 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv6" as CFString) as? [String: Any]
        let primary = Self.selectPrimary(ipv4: ipv4, ipv6: ipv6)
        let systemPrimaryInterface = primary.interface
        let systemPrimaryServiceID = primary.service
        let globalRouter = ipv4?["Router"] as? String

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
                globalPrimary: systemPrimaryInterface,
                globalRouter: globalRouter
            )
            rawWiredInfos.append(ifaceInfo)
        }

        // 4. Inspect Wi-Fi service
        let wifiBSD = discovery.wifiService?.bsdName ?? "en0"
        let wifiName = discovery.wifiService?.serviceName ?? "Wi-Fi"
        let wifiInfo = readInterfaceInfo(
            store: store,
            bsdName: wifiBSD,
            serviceName: wifiName,
            serviceID: discovery.wifiService?.serviceID,
            serviceOrder: discovery.wifiService?.serviceOrder,
            enabled: discovery.wifiService?.enabled ?? false,
            globalPrimary: systemPrimaryInterface,
            globalRouter: globalRouter
        )

        // Find primary service name
        var primaryName: String? = nil
        if let pid = systemPrimaryServiceID {
            if let match = discovery.wiredEthernetServices.first(where: { $0.serviceID == pid }) {
                primaryName = match.serviceName
            } else if discovery.wifiService?.serviceID == pid {
                primaryName = discovery.wifiService?.serviceName
            }
        }
        if primaryName == nil, let pIface = systemPrimaryInterface {
            if let match = rawWiredInfos.first(where: { $0.bsdName == pIface }) {
                primaryName = match.serviceName
            } else if pIface == wifiInfo.bsdName {
                primaryName = wifiInfo.serviceName
            }
        }

        // 5. Single-pass health & link-speed evaluation
        let evaluatedWiredStates = stateMachine.evaluateWiredInterfaces(
            from: rawWiredInfos,
            physicalPrimaryInterface: nil,
            linkSpeedDetector: linkSpeedDetector
        )

        // 6. Resolve the physical transport; overlay fallbacks are estimates.
        let resolvedPhysicalTransport = PhysicalTransportResolver.resolve(
            systemPrimaryInterface: systemPrimaryInterface,
            systemPrimaryServiceName: primaryName,
            wiredInterfaces: evaluatedWiredStates,
            wifi: wifiInfo,
            previousPhysicalPrimaryBSD: stateMachine.currentPhysicalPrimaryBSD
        )

        // 7. Stamp isPrimary on the active physical Ethernet adapter without re-running evaluation or ioctl
        let finalWiredStates = evaluatedWiredStates.map { state in
            let isPrimary = (resolvedPhysicalTransport.kind == .ethernet && state.bsdName == resolvedPhysicalTransport.bsdName)
            return state.withPrimary(isPrimary)
        }

        return NetworkSnapshot(
            wiredInterfaces: finalWiredStates,
            wifi: wifiInfo,
            systemPrimaryInterface: systemPrimaryInterface,
            systemPrimaryServiceID: systemPrimaryServiceID,
            systemPrimaryServiceName: primaryName,
            physicalTransport: resolvedPhysicalTransport,
            globalIPv4Router: globalRouter,
            timestamp: Date()
        )
    }

    private func triggerSnapshot() {
        guard isRunning else { return }
        let snapshot = captureSnapshotOnQueue()
        if let last = lastDeliveredSnapshot, snapshot.isSemanticallyEqualTo(last) {
            Self.logger.debug("Suppressing redundant snapshot broadcast (semantically identical)")
            return
        }
        lastDeliveredSnapshot = snapshot
        stateMachine.process(snapshot: snapshot)
        callbackLock.lock()
        let generation = deliveryGeneration
        callbackLock.unlock()
        deliveryQueue.async { [weak self] in
            guard let self = self else { return }
            self.callbackLock.lock()
            let handler = self.deliveryGeneration == generation ? self.callback : nil
            self.callbackLock.unlock()
            handler?(snapshot)
        }
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
                if let interfaceRouter = ipv4Dict["Router"] as? String {
                    router = interfaceRouter
                }
            }
        }

        if router == nil, let sid = serviceID {
            let serviceIPv4Key = "State:/Network/Service/\(sid)/IPv4" as CFString
            if let serviceDict = SCDynamicStoreCopyValue(store, serviceIPv4Key) as? [String: Any] {
                if let serviceRouter = serviceDict["Router"] as? String {
                    router = serviceRouter
                }
                if ipv4Addresses.isEmpty, let serviceAddrs = serviceDict["Addresses"] as? [String] {
                    ipv4Addresses = serviceAddrs
                }
                if subnetMasks.isEmpty, let serviceSubnets = serviceDict["SubnetMasks"] as? [String] {
                    subnetMasks = serviceSubnets
                }
            }
        }

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
