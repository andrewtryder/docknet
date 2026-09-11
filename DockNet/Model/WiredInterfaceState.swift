import Foundation

/// Represents the evaluated state of a physical wired Ethernet interface/service.
public struct WiredInterfaceState: Equatable, Sendable, Identifiable {
    public var id: String { serviceID }

    public let serviceID: String
    public let serviceName: String
    public let bsdName: String
    public let enabled: Bool
    public let serviceOrder: Int?
    public let linkActive: Bool
    public let ipv4Address: String?
    public let subnetMask: String?
    public let gateway: String?
    public let health: EthernetHealthState
    public let isPreferred: Bool
    public let isPrimary: Bool
    public let linkSpeed: String?
    public let isHardwarePresent: Bool

    public init(
        serviceID: String,
        serviceName: String,
        bsdName: String,
        enabled: Bool = true,
        serviceOrder: Int? = nil,
        linkActive: Bool = false,
        ipv4Address: String? = nil,
        subnetMask: String? = nil,
        gateway: String? = nil,
        health: EthernetHealthState = .cableDisconnected,
        isPreferred: Bool = false,
        isPrimary: Bool = false,
        linkSpeed: String? = nil,
        isHardwarePresent: Bool = true
    ) {
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.bsdName = bsdName
        self.enabled = enabled
        self.serviceOrder = serviceOrder
        self.linkActive = linkActive
        self.ipv4Address = ipv4Address
        self.subnetMask = subnetMask
        self.gateway = gateway
        self.health = health
        self.isPreferred = isPreferred
        self.isPrimary = isPrimary
        self.linkSpeed = linkSpeed
        self.isHardwarePresent = isHardwarePresent
    }

    /// Returns a copy of this state with an updated isPrimary flag.
    public func withPrimary(_ isPrimary: Bool) -> WiredInterfaceState {
        guard self.isPrimary != isPrimary else { return self }
        return WiredInterfaceState(
            serviceID: serviceID,
            serviceName: serviceName,
            bsdName: bsdName,
            enabled: enabled,
            serviceOrder: serviceOrder,
            linkActive: linkActive,
            ipv4Address: ipv4Address,
            subnetMask: subnetMask,
            gateway: gateway,
            health: health,
            isPreferred: isPreferred,
            isPrimary: isPrimary,
            linkSpeed: linkSpeed,
            isHardwarePresent: isHardwarePresent
        )
    }

    /// Whether this interface has an active link and a valid non-169.254 IPv4 address with gateway
    public var isReady: Bool {
        health == .ready
    }

    /// Display string summarizing status (e.g. "Ready · Primary", "Ready · Available", "Adapter Not Present", "Cable Disconnected", "Disabled")
    public var statusSummary: String {
        if !enabled || health == .disabled {
            return "Disabled"
        }
        if !isHardwarePresent || health == .adapterNotPresent {
            return "Adapter Not Present"
        }
        switch health {
        case .ready:
            if isPrimary {
                return "Ready · Primary"
            } else {
                return "Ready · Available"
            }
        case .obtainingDHCP:
            return "Obtaining DHCP"
        case .linkUp:
            return "Connected · Link Detected"
        case .degraded:
            if let ip = ipv4Address, ip.hasPrefix("169.254.") {
                return "Self-Assigned IP (169.254.x.x)"
            }
            return "Degraded"
        case .cableDisconnected, .disconnected:
            return "Cable Disconnected"
        case .adapterNotPresent:
            return "Adapter Not Present"
        case .disabled:
            return "Disabled"
        }
    }
}
