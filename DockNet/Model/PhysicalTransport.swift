import Foundation

/// The discrete physical connection categories supported by DockNet.
public enum PhysicalTransportKind: String, Codable, Equatable, Sendable, CustomStringConvertible {
    case ethernet = "Ethernet"
    case wifi = "Wi-Fi"
    case none = "None"

    public var description: String { rawValue }
}

/// Represents the resolved underlying physical network transport.
/// VPNs, tunnels, and virtual interfaces are never represented as physical transports.
public struct PhysicalTransport: Equatable, Sendable {
    public let kind: PhysicalTransportKind
    public let bsdName: String?
    public let serviceName: String?
    public let ipv4Address: String?

    public init(
        kind: PhysicalTransportKind,
        bsdName: String? = nil,
        serviceName: String? = nil,
        ipv4Address: String? = nil
    ) {
        self.kind = kind
        self.bsdName = bsdName
        self.serviceName = serviceName
        self.ipv4Address = ipv4Address
    }

    public static let none = PhysicalTransport(kind: .none, bsdName: nil, serviceName: nil, ipv4Address: nil)
}

/// Pure domain resolver for identifying virtual/overlay interfaces and resolving
/// the authoritative physical transport (Ethernet > Wi-Fi) regardless of active VPN tunnels.
public struct PhysicalTransportResolver: Sendable {

    /// Determines if a BSD interface name or service name represents an overlay, tunnel, or virtual interface.
    public static func isVirtualOrOverlay(bsdName: String, serviceName: String? = nil) -> Bool {
        let bsd = bsdName.lowercased()

        // Exclude classic virtual & tunnel BSD prefixes
        let excludedPrefixes = [
            "utun",     // Userspace tunnels (WireGuard, Tailscale, OpenVPN, IPsec)
            "ipsec",    // Native macOS IPsec tunnels
            "ppp",      // Point-to-Point protocol tunnels
            "gif",      // Generic IP-in-IP tunnels
            "stf",      // 6to4 tunnel interfaces
            "bridge",   // Software bridges (Thunderbolt Bridge, VM bridges)
            "awdl",     // Apple Wireless Direct Link (AirDrop/AirPlay)
            "llw",      // Low latency WLAN
            "lo"        // Loopback (lo0)
        ]

        if excludedPrefixes.contains(where: { bsd.hasPrefix($0) }) {
            return true
        }

        // Exclude by service name keywords
        if let name = serviceName?.lowercased() {
            let overlayKeywords = [
                "tailscale",
                "vpn",
                "tunnel",
                "bridge",
                "packet-tunnel",
                "network extension"
            ]
            if overlayKeywords.contains(where: { name.contains($0) }) {
                return true
            }
        }

        return false
    }

    /// Resolves the authoritative physical transport from the system primary interface,
    /// available wired Ethernet services, Wi-Fi, and the previous physical primary BSD.
    ///
    /// Order of evidence:
    /// 1. If systemPrimaryInterface is a recognized physical Ethernet or Wi-Fi interface: use it as authoritative.
    /// 2. If systemPrimaryInterface is a VPN/tunnel/virtual interface:
    ///    a. If last-known physical primary was healthy Ethernet and remains healthy: preserve it.
    ///    b. If that physical interface becomes unhealthy/disconnected: choose healthy Ethernet by service order, else Wi-Fi.
    ///    c. When an Ethernet service transitions to Ready while Wi-Fi is physical connection: treat healthy Ethernet as preferred (Ethernet > Wi-Fi).
    ///    d. When all Ethernet becomes unavailable: resolve to Wi-Fi even if global default route is utun/VPN.
    ///    e. If multiple Ethernet services are healthy under VPN: preserve previous if still healthy, otherwise use service order.
    public static func resolve(
        systemPrimaryInterface: String?,
        systemPrimaryServiceName: String? = nil,
        wiredInterfaces: [WiredInterfaceState],
        wifi: NetworkInterfaceInfo,
        previousPhysicalPrimaryBSD: String? = nil
    ) -> PhysicalTransport {
        // 1. Check if the system PrimaryInterface is a recognized physical interface
        if let systemPrimary = systemPrimaryInterface, !isVirtualOrOverlay(bsdName: systemPrimary, serviceName: systemPrimaryServiceName) {
            if let matchingWired = wiredInterfaces.first(where: { $0.bsdName == systemPrimary && $0.isReady }) {
                return PhysicalTransport(
                    kind: .ethernet,
                    bsdName: matchingWired.bsdName,
                    serviceName: matchingWired.serviceName,
                    ipv4Address: matchingWired.ipv4Address
                )
            } else if systemPrimary == wifi.bsdName && wifi.isLinkActive {
                return PhysicalTransport(
                    kind: .wifi,
                    bsdName: wifi.bsdName,
                    serviceName: wifi.serviceName,
                    ipv4Address: wifi.primaryIPv4Address
                )
            }
        }

        // 2. System PrimaryInterface is a VPN, tunnel, virtual interface, or not ready.
        // Resolve the underlying physical transport using the specified order of evidence.

        let readyWired = wiredInterfaces
            .filter { $0.enabled && $0.isReady }
            .sorted { (lhs, rhs) -> Bool in
                let o1 = lhs.serviceOrder ?? Int.max
                let o2 = rhs.serviceOrder ?? Int.max
                if o1 != o2 { return o1 < o2 }
                return lhs.bsdName < rhs.bsdName
            }

        // Check last-known physical primary
        if let prevBSD = previousPhysicalPrimaryBSD {
            // Case A: Last-known was an Ethernet adapter
            if let prevWired = wiredInterfaces.first(where: { $0.bsdName == prevBSD }), prevWired.isReady {
                // Preserved! (Rule 1 & Rule 5)
                return PhysicalTransport(
                    kind: .ethernet,
                    bsdName: prevWired.bsdName,
                    serviceName: prevWired.serviceName,
                    ipv4Address: prevWired.ipv4Address
                )
            }

            // Case B: Last-known was Wi-Fi
            if prevBSD == wifi.bsdName {
                // Rule 3: When an Ethernet service transitions to Ready while Wi-Fi is physical connection,
                // promote healthy Ethernet as preferred (Ethernet > Wi-Fi).
                if let bestWired = readyWired.first {
                    return PhysicalTransport(
                        kind: .ethernet,
                        bsdName: bestWired.bsdName,
                        serviceName: bestWired.serviceName,
                        ipv4Address: bestWired.ipv4Address
                    )
                }

                // If no Ethernet is ready, preserve Wi-Fi
                if wifi.isLinkActive {
                    return PhysicalTransport(
                        kind: .wifi,
                        bsdName: wifi.bsdName,
                        serviceName: wifi.serviceName,
                        ipv4Address: wifi.primaryIPv4Address
                    )
                }
            }
        }

        // Fallback: Pick highest priority ready Ethernet
        if let bestWired = readyWired.first {
            return PhysicalTransport(
                kind: .ethernet,
                bsdName: bestWired.bsdName,
                serviceName: bestWired.serviceName,
                ipv4Address: bestWired.ipv4Address
            )
        }

        // Fallback: Wi-Fi
        if wifi.isLinkActive {
            return PhysicalTransport(
                kind: .wifi,
                bsdName: wifi.bsdName,
                serviceName: wifi.serviceName,
                ipv4Address: wifi.primaryIPv4Address
            )
        }

        return .none
    }
}
