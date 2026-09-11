import Foundation

/// A point-in-time snapshot of the system's discovered network interfaces and routing state.
public struct NetworkSnapshot: Equatable, Sendable {
    /// All discovered physical wired Ethernet interfaces, sorted by macOS Network Service Order.
    public let wiredInterfaces: [WiredInterfaceState]

    /// The Wi-Fi interface (typically en0).
    public let wifi: NetworkInterfaceInfo

    /// The BSD name of the system's actual default route (e.g. "en8" or "en0").
    public let primaryInterface: String?

    /// The Service ID of the system's primary service (from State:/Network/Global/IPv4).
    public let primaryServiceID: String?

    /// The human-readable name of the system's primary service (e.g. "USB 10/100/1000 LAN" or "Wi-Fi").
    public let primaryServiceName: String?

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
        globalIPv4Router: String? = nil,
        timestamp: Date = Date()
    ) {
        self.wiredInterfaces = wiredInterfaces
        self.wifi = wifi
        self.primaryInterface = primaryInterface
        self.primaryServiceID = primaryServiceID
        self.primaryServiceName = primaryServiceName
        self.globalIPv4Router = globalIPv4Router
        self.timestamp = timestamp
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

    /// Whether the system's default IPv4 route currently points through any wired Ethernet adapter.
    public var actualPrimaryIsWired: Bool {
        guard let primary = primaryInterface else { return false }
        return wiredInterfaces.contains(where: { $0.bsdName == primary })
    }

    /// Backward-compatibility helper returning the preferred or first wired interface.
    public var ethernet: WiredInterfaceState? {
        preferredWiredInterface ?? wiredInterfaces.first
    }

    /// Whether the system's default IPv4 route currently points through Wi-Fi.
    public var isWifiPrimary: Bool {
        primaryInterface == wifi.bsdName
    }

    /// Returns the active WiredInterfaceState if primaryInterface is currently a wired adapter.
    public var activePrimaryWiredInterface: WiredInterfaceState? {
        guard let primary = primaryInterface else { return nil }
        return wiredInterfaces.first(where: { $0.bsdName == primary })
    }

    /// Status summary text for Wi-Fi (Connected · Primary, Connected · Standby, Disconnected)
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
