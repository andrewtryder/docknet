import Foundation

/// Detailed status of a network interface (such as en8, en6, or en0).
public struct NetworkInterfaceInfo: Equatable, Sendable {
    public let bsdName: String
    public let serviceName: String
    public let serviceID: String?
    public let serviceOrder: Int?
    public let enabled: Bool
    public let isLinkActive: Bool
    public let isHardwarePresent: Bool
    public let ipv4Addresses: [String]
    public let subnetMasks: [String]
    public let router: String?

    public init(
        bsdName: String,
        serviceName: String,
        serviceID: String? = nil,
        serviceOrder: Int? = nil,
        enabled: Bool = true,
        isLinkActive: Bool = false,
        isHardwarePresent: Bool = true,
        ipv4Addresses: [String] = [],
        subnetMasks: [String] = [],
        router: String? = nil
    ) {
        self.bsdName = bsdName
        self.serviceName = serviceName
        self.serviceID = serviceID
        self.serviceOrder = serviceOrder
        self.enabled = enabled
        self.isLinkActive = isLinkActive
        self.isHardwarePresent = isHardwarePresent
        self.ipv4Addresses = ipv4Addresses
        self.subnetMasks = subnetMasks
        self.router = router
    }

    public var primaryIPv4Address: String? {
        ipv4Addresses.first
    }

    public var primarySubnetMask: String? {
        subnetMasks.first
    }

    /// Returns true if the primary IPv4 address is an APIPA / Link-Local address (169.254.x.x)
    public var hasLinkLocalIPv4: Bool {
        guard let ip = primaryIPv4Address else { return false }
        return ip.hasPrefix("169.254.")
    }

    /// Returns true if the interface has a valid, routable, non-link-local IPv4 address
    public var hasValidRoutableIPv4: Bool {
        guard let ip = primaryIPv4Address, !ip.isEmpty else { return false }
        if ip == "0.0.0.0" || hasLinkLocalIPv4 {
            return false
        }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        for part in parts {
            guard let val = Int(part), val >= 0 && val <= 255 else { return false }
        }
        return true
    }

    /// Returns true if the interface has both a valid IPv4 address and a gateway router
    public var isIPv4Ready: Bool {
        hasValidRoutableIPv4 && router != nil && !(router?.isEmpty ?? true)
    }
}
