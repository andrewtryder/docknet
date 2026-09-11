import Foundation
import os

/// Pure state machine that evaluates network snapshots, derives health for each wired interface,
/// determines the preferred wired interface based on macOS service order, tracks physical transport
/// independent of overlays/VPNs, and emits deduplicated transition events.
public final class NetworkStateMachine: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "NetworkStateMachine")

    public enum TransitionEvent: Equatable, Sendable, CustomStringConvertible {
        case ethernetStateChanged(bsdName: String, from: EthernetHealthState, to: EthernetHealthState)
        case preferredWiredChanged(from: String?, to: String?)
        case physicalPrimaryChanged(from: String?, to: String?)
        case systemPrimaryChanged(from: String?, to: String?)

        // Backward compatibility
        public static func primaryPathChanged(from: String?, to: String?) -> TransitionEvent {
            .physicalPrimaryChanged(from: from, to: to)
        }

        public var description: String {
            switch self {
            case .ethernetStateChanged(let bsdName, let from, let to):
                return "ethernet \(bsdName): \(from) -> \(to)"
            case .preferredWiredChanged(let from, let to):
                let fromStr = from ?? "none"
                let toStr = to ?? "none"
                return "preferred wired interface \(fromStr) -> \(toStr)"
            case .physicalPrimaryChanged(let from, let to):
                let fromStr = from ?? "none"
                let toStr = to ?? "none"
                return "physical primary \(fromStr) -> \(toStr)"
            case .systemPrimaryChanged(let from, let to):
                let fromStr = from ?? "none"
                let toStr = to ?? "none"
                return "system primary \(fromStr) -> \(toStr)"
            }
        }
    }

    private let lock = NSLock()
    private var _interfaceHealthMap: [String: EthernetHealthState] = [:]
    private var _preferredWiredBSD: String? = nil
    private var _currentPhysicalPrimaryBSD: String? = nil
    private var _currentSystemPrimaryInterface: String? = nil
    private var _lastSnapshot: NetworkSnapshot? = nil

    public init(
        initialPhysicalPrimary: String? = nil,
        initialPreferredWired: String? = nil,
        initialPrimaryInterface: String? = nil
    ) {
        let primary = initialPhysicalPrimary ?? initialPrimaryInterface
        self._currentPhysicalPrimaryBSD = primary
        self._preferredWiredBSD = initialPreferredWired
        self._currentSystemPrimaryInterface = primary
    }

    public var currentPhysicalPrimaryBSD: String? {
        lock.lock()
        defer { lock.unlock() }
        return _currentPhysicalPrimaryBSD
    }

    public var currentPrimaryInterface: String? {
        currentPhysicalPrimaryBSD
    }

    public var currentSystemPrimaryInterface: String? {
        lock.lock()
        defer { lock.unlock() }
        return _currentSystemPrimaryInterface
    }

    public var preferredWiredBSD: String? {
        lock.lock()
        defer { lock.unlock() }
        return _preferredWiredBSD
    }

    public var lastSnapshot: NetworkSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return _lastSnapshot
    }

    public func health(for bsdName: String) -> EthernetHealthState {
        lock.lock()
        defer { lock.unlock() }
        return _interfaceHealthMap[bsdName] ?? .disconnected
    }

    /// Evaluates the Ethernet health state given an interface's link and IPv4 info.
    public static func evaluateEthernetState(
        isLinkActive: Bool,
        ipv4Address: String?,
        router: String?,
        previousState: EthernetHealthState = .disconnected
    ) -> EthernetHealthState {
        guard isLinkActive else {
            return .disconnected
        }

        guard let ip = ipv4Address, !ip.isEmpty, ip != "0.0.0.0" else {
            if previousState == .disconnected {
                return .linkUp
            } else {
                return .obtainingDHCP
            }
        }

        // Check for APIPA / self-assigned link local 169.254.x.x
        if ip.hasPrefix("169.254.") {
            return .degraded
        }

        // Basic IPv4 format validation
        let parts = ip.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ Int($0).map { $0 >= 0 && $0 <= 255 } ?? false }) else {
            return .degraded
        }

        if let gateway = router, !gateway.isEmpty {
            return .ready
        } else {
            return .obtainingDHCP
        }
    }

    /// Evaluates an array of discovered wired interfaces, updating health and selecting the preferred interface.
    /// `isPrimary` is evaluated against the physicalPrimaryInterface (not raw VPN tunnel).
    public func evaluateWiredInterfaces(
        from interfaces: [NetworkInterfaceInfo],
        physicalPrimaryInterface: String? = nil,
        primaryInterface: String? = nil,
        linkSpeedDetector: (any LinkSpeedDetecting)? = nil
    ) -> [WiredInterfaceState] {
        lock.lock()
        defer { lock.unlock() }

        let activePhysical = physicalPrimaryInterface ?? primaryInterface

        var evaluated: [WiredInterfaceState] = []

        for iface in interfaces {
            let isPresent = iface.isHardwarePresent
            let priorState = _interfaceHealthMap[iface.bsdName] ?? .cableDisconnected
            let evaluatedHealth: EthernetHealthState

            if !iface.enabled {
                evaluatedHealth = .disabled
            } else if !isPresent {
                evaluatedHealth = .adapterNotPresent
            } else if !iface.isLinkActive {
                evaluatedHealth = .cableDisconnected
            } else {
                evaluatedHealth = Self.evaluateEthernetState(
                    isLinkActive: true,
                    ipv4Address: iface.primaryIPv4Address,
                    router: iface.router,
                    previousState: priorState
                )
            }

            let speed = iface.isLinkActive ? linkSpeedDetector?.detectLinkSpeed(for: iface.bsdName) : nil
            let isPrimary = (activePhysical != nil && activePhysical == iface.bsdName)

            let state = WiredInterfaceState(
                serviceID: iface.serviceID ?? iface.bsdName,
                serviceName: iface.serviceName,
                bsdName: iface.bsdName,
                enabled: iface.enabled,
                serviceOrder: iface.serviceOrder,
                linkActive: iface.isLinkActive,
                ipv4Address: iface.primaryIPv4Address,
                subnetMask: iface.primarySubnetMask,
                gateway: iface.router,
                health: evaluatedHealth,
                isPreferred: false,
                isPrimary: isPrimary,
                linkSpeed: speed,
                isHardwarePresent: isPresent
            )
            evaluated.append(state)
        }

        // Determine preferred interface: first enabled && ready interface ordered by serviceOrder
        let readyInterfaces = evaluated
            .filter { $0.enabled && $0.health == .ready }
            .sorted { (lhs, rhs) -> Bool in
                let o1 = lhs.serviceOrder ?? Int.max
                let o2 = rhs.serviceOrder ?? Int.max
                if o1 != o2 { return o1 < o2 }
                return lhs.bsdName < rhs.bsdName
            }

        let preferredID = readyInterfaces.first?.serviceID

        // Re-map with isPreferred flag
        return evaluated.map { iface in
            WiredInterfaceState(
                serviceID: iface.serviceID,
                serviceName: iface.serviceName,
                bsdName: iface.bsdName,
                enabled: iface.enabled,
                serviceOrder: iface.serviceOrder,
                linkActive: iface.linkActive,
                ipv4Address: iface.ipv4Address,
                subnetMask: iface.subnetMask,
                gateway: iface.gateway,
                health: iface.health,
                isPreferred: iface.serviceID == preferredID,
                isPrimary: iface.isPrimary,
                linkSpeed: iface.linkSpeed,
                isHardwarePresent: iface.isHardwarePresent
            )
        }
    }

    /// Processes an incoming network snapshot, updates internal state, and returns deduplicated transition events.
    @discardableResult
    public func process(snapshot: NetworkSnapshot) -> [TransitionEvent] {
        lock.lock()
        defer { lock.unlock() }

        var events: [TransitionEvent] = []

        // 1. Process health changes per wired interface
        for iface in snapshot.wiredInterfaces {
            let prior = _interfaceHealthMap[iface.bsdName] ?? .disconnected
            if iface.health != prior {
                let event = TransitionEvent.ethernetStateChanged(bsdName: iface.bsdName, from: prior, to: iface.health)
                events.append(event)
                Self.logger.info("\(event.description, privacy: .public)")
                _interfaceHealthMap[iface.bsdName] = iface.health
            }
        }

        // 2. Process preferred wired interface changes
        let newPreferred = snapshot.preferredWiredInterface?.bsdName
        if newPreferred != _preferredWiredBSD {
            let event = TransitionEvent.preferredWiredChanged(from: _preferredWiredBSD, to: newPreferred)
            events.append(event)
            Self.logger.info("\(event.description, privacy: .public)")
            _preferredWiredBSD = newPreferred
        }

        // 3. Process physical primary changes (authoritative physical transport)
        let newPhysical = snapshot.physicalPrimaryInterface
        if newPhysical != _currentPhysicalPrimaryBSD {
            let event = TransitionEvent.physicalPrimaryChanged(from: _currentPhysicalPrimaryBSD, to: newPhysical)
            events.append(event)
            Self.logger.info("\(event.description, privacy: .public)")
            _currentPhysicalPrimaryBSD = newPhysical
        }

        // 4. Process raw system primary changes (informational)
        let newSystem = snapshot.systemPrimaryInterface
        if newSystem != _currentSystemPrimaryInterface {
            let event = TransitionEvent.systemPrimaryChanged(from: _currentSystemPrimaryInterface, to: newSystem)
            events.append(event)
            Self.logger.debug("\(event.description, privacy: .public)")
            _currentSystemPrimaryInterface = newSystem
        }

        _lastSnapshot = snapshot
        return events
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _interfaceHealthMap.removeAll()
        _preferredWiredBSD = nil
        _currentPhysicalPrimaryBSD = nil
        _currentSystemPrimaryInterface = nil
        _lastSnapshot = nil
    }
}
