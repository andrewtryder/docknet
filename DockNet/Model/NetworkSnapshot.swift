import Foundation

/// A point-in-time snapshot of the system's discovered network interfaces, macOS routing state,
/// and resolved physical transport (strictly physical Ethernet, Wi-Fi, or none).
public struct NetworkSnapshot: Equatable, Sendable {
    /// All discovered physical wired Ethernet interfaces, sorted by macOS Network Service Order.
    public let wiredInterfaces: [WiredInterfaceState]

    /// The Wi-Fi interface (typically en0).
    public let wifi: NetworkInterfaceInfo

    /// The raw global system default route reported by macOS (e.g. "en6", "en0", or "utun5").
    public let systemPrimaryInterface: String?

    /// The Service ID of the system's global primary service.
    public let systemPrimaryServiceID: String?

    /// The human-readable name of the system's global primary service.
    public let systemPrimaryServiceName: String?

    /// The authoritative underlying physical network transport (Ethernet > Wi-Fi),
    /// completely isolated from VPNs, Tailscale, or tunnel overlays.
    public let physicalTransport: PhysicalTransport

    /// The default IPv4 gateway router.
    public let globalIPv4Router: String?

    /// Timestamp when snapshot was captured.
    public let timestamp: Date

    public init(
        wiredInterfaces: [WiredInterfaceState] = [],
        wifi: NetworkInterfaceInfo,
        primaryInterface: String? = nil,
        primaryServiceID: String? = nil,
        primaryServiceName: String? = nil,
        systemPrimaryInterface: String? = nil,
        systemPrimaryServiceID: String? = nil,
        systemPrimaryServiceName: String? = nil,
        physicalTransport: PhysicalTransport? = nil,
        globalIPv4Router: String? = nil,
        timestamp: Date = Date()
    ) {
        self.wiredInterfaces = wiredInterfaces
        self.wifi = wifi

        let resolvedSysPrimary = systemPrimaryInterface ?? primaryInterface
        self.systemPrimaryInterface = resolvedSysPrimary
        self.systemPrimaryServiceID = systemPrimaryServiceID ?? primaryServiceID
        self.systemPrimaryServiceName = systemPrimaryServiceName ?? primaryServiceName
        self.globalIPv4Router = globalIPv4Router
        self.timestamp = timestamp

        if let explicitPhysical = physicalTransport {
            self.physicalTransport = explicitPhysical
        } else {
            self.physicalTransport = PhysicalTransportResolver.resolve(
                systemPrimaryInterface: resolvedSysPrimary,
                systemPrimaryServiceName: self.systemPrimaryServiceName,
                wiredInterfaces: wiredInterfaces,
                wifi: wifi
            )
        }
    }

    /// Compares two snapshots for semantic equality, ignoring the capture timestamp.
    public func isSemanticallyEqualTo(_ other: NetworkSnapshot) -> Bool {
        return wiredInterfaces == other.wiredInterfaces &&
            wifi == other.wifi &&
            systemPrimaryInterface == other.systemPrimaryInterface &&
            systemPrimaryServiceID == other.systemPrimaryServiceID &&
            systemPrimaryServiceName == other.systemPrimaryServiceName &&
            physicalTransport == other.physicalTransport &&
            globalIPv4Router == other.globalIPv4Router
    }

    /// The BSD name of the authoritative physical primary connection (e.g. "en6", "en0", or nil).
    public var physicalPrimaryInterface: String? {
        physicalTransport.bsdName
    }

    /// The category of physical transport (ethernet, wifi, none).
    public var physicalPrimaryType: PhysicalTransportKind {
        physicalTransport.kind
    }

    /// Alias for physicalPrimaryInterface for backward compatibility with existing observers.
    public var primaryInterface: String? {
        physicalPrimaryInterface
    }

    /// Primary service ID alias.
    public var primaryServiceID: String? {
        systemPrimaryServiceID
    }

    /// Primary service name alias.
    public var primaryServiceName: String? {
        physicalTransport.serviceName ?? systemPrimaryServiceName
    }

    /// The preferred wired interface: the first healthy (ready) wired interface in macOS service order.
    public var preferredWiredInterface: WiredInterfaceState? {
        wiredInterfaces.first(where: { $0.isPreferred }) ??
        wiredInterfaces
            .filter { $0.enabled && $0.isReady }
            .sorted { (lhs, rhs) -> Bool in
                (lhs.serviceOrder ?? Int.max) < (rhs.serviceOrder ?? Int.max)
            }
            .first
    }

    /// Whether the resolved physical primary connection is physical Ethernet.
    public var actualPrimaryIsWired: Bool {
        physicalTransport.kind == .ethernet
    }

    /// Backward-compatibility helper returning the preferred or first wired interface.
    public var ethernet: WiredInterfaceState? {
        preferredWiredInterface ?? wiredInterfaces.first
    }

    /// Whether the resolved physical primary connection is Wi-Fi.
    public var isWifiPrimary: Bool {
        physicalTransport.kind == .wifi
    }

    /// Returns the active WiredInterfaceState if physical primary is currently a wired adapter.
    public var activePrimaryWiredInterface: WiredInterfaceState? {
        guard physicalTransport.kind == .ethernet, let bsd = physicalTransport.bsdName else { return nil }
        return wiredInterfaces.first(where: { $0.bsdName == bsd })
    }

    /// Status summary text for Wi-Fi (Connected · Primary, Connected · Standby, Disconnected).
    public var wifiStatusText: String {
        if isWifiPrimary {
            return "Connected · Primary"
        } else if wifi.isLinkActive {
            return "Connected · Standby"
        } else {
            return "Disconnected"
        }
    }
}
