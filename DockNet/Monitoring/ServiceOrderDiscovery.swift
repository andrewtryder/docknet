import Foundation
import SystemConfiguration
import os

/// Discovers configured network services and macOS Network Service Order using SystemConfiguration APIs.
public struct ServiceOrderDiscovery: Sendable {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "ServiceOrderDiscovery")

    public struct DiscoveredService: Equatable, Sendable {
        public let serviceID: String
        public let serviceName: String
        public let bsdName: String
        public let interfaceType: String
        public let enabled: Bool
        public let serviceOrder: Int? // 0-based priority index in macOS service order
    }

    public struct DiscoveryResult: Equatable, Sendable {
        public let wiredEthernetServices: [DiscoveredService]
        public let wifiService: DiscoveredService?
        public let serviceOrderIDs: [String]
    }

    /// Discovers all configured network services and macOS service order.
    public static func discoverServices() -> DiscoveryResult {
        guard let prefs = SCPreferencesCreate(kCFAllocatorDefault, "DockNet" as CFString, nil) else {
            logger.error("Failed to create SCPreferences")
            return DiscoveryResult(wiredEthernetServices: [], wifiService: nil, serviceOrderIDs: [])
        }

        guard let currentSet = SCNetworkSetCopyCurrent(prefs) else {
            logger.error("Failed to copy current SCNetworkSet")
            return DiscoveryResult(wiredEthernetServices: [], wifiService: nil, serviceOrderIDs: [])
        }

        let serviceOrder = (SCNetworkSetGetServiceOrder(currentSet) as? [String]) ?? []
        let networkServicesDict = (SCPreferencesGetValue(prefs, "NetworkServices" as CFString) as? [String: [String: Any]]) ?? [:]

        guard let rawServices = SCNetworkSetCopyServices(currentSet) as? [SCNetworkService] else {
            logger.error("Failed to copy SCNetworkServices from current set")
            return DiscoveryResult(wiredEthernetServices: [], wifiService: nil, serviceOrderIDs: serviceOrder)
        }

        var ethernetServices: [DiscoveredService] = []
        var detectedWifi: DiscoveredService? = nil

        for service in rawServices {
            guard let sid = SCNetworkServiceGetServiceID(service) as String? else { continue }

            // Skip internal or unconfigured dormant raw hardware services
            if let sdict = networkServicesDict[sid],
               let ifaceDict = sdict["Interface"] as? [String: Any],
               let isHidden = ifaceDict["HiddenConfiguration"] as? Bool,
               isHidden {
                continue
            }

            let name = (SCNetworkServiceGetName(service) as String?) ?? "Unknown Service"
            let enabled = SCNetworkServiceGetEnabled(service)
            let orderIndex = serviceOrder.firstIndex(of: sid)

            guard let iface = SCNetworkServiceGetInterface(service) else { continue }
            let bsdName = (SCNetworkInterfaceGetBSDName(iface) as String?) ?? ""
            let ifaceType = (SCNetworkInterfaceGetInterfaceType(iface) as String?) ?? ""

            // Identify Wi-Fi strictly by interface type (kSCNetworkInterfaceTypeIEEE80211)
            if ifaceType == (kSCNetworkInterfaceTypeIEEE80211 as String) {
                if detectedWifi == nil || enabled {
                    detectedWifi = DiscoveredService(
                        serviceID: sid,
                        serviceName: name,
                        bsdName: bsdName,
                        interfaceType: ifaceType,
                        enabled: enabled,
                        serviceOrder: orderIndex
                    )
                }
                continue
            }

            // Explicitly filter out bridges, tunnels, tailscale, and VPNs
            if isExcludedInterface(name: name, bsdName: bsdName, interfaceType: ifaceType) {
                continue
            }

            // Only allow physical Ethernet
            if ifaceType == (kSCNetworkInterfaceTypeEthernet as String) {
                let discovered = DiscoveredService(
                    serviceID: sid,
                    serviceName: name,
                    bsdName: bsdName,
                    interfaceType: ifaceType,
                    enabled: enabled,
                    serviceOrder: orderIndex
                )
                ethernetServices.append(discovered)
            }
        }

        // Sort discovered wired services according to macOS service order (lowest index = highest priority)
        ethernetServices.sort { (lhs, rhs) -> Bool in
            let o1 = lhs.serviceOrder ?? Int.max
            let o2 = rhs.serviceOrder ?? Int.max
            if o1 != o2 {
                return o1 < o2
            }
            return lhs.bsdName < rhs.bsdName // deterministic fallback
        }

        return DiscoveryResult(
            wiredEthernetServices: ethernetServices,
            wifiService: detectedWifi,
            serviceOrderIDs: serviceOrder
        )
    }

    /// Determines if an interface is an internal, virtual, or non-wired interface.
    public static func isExcludedInterface(name: String, bsdName: String, interfaceType: String) -> Bool {
        let lowerName = name.lowercased()
        let lowerBSD = bsdName.lowercased()
        let lowerType = interfaceType.lowercased()

        // Bridges
        if lowerType == "bridge" || lowerBSD.hasPrefix("bridge") || lowerName.contains("thunderbolt bridge") {
            return true
        }

        // VPN / Tailscale / Tunnels
        if lowerType == "vpn" || lowerType == "ppp" || lowerBSD.hasPrefix("utun") || lowerBSD.hasPrefix("ppp") || lowerName.contains("tailscale") || lowerName.contains("vpn") {
            return true
        }

        // AWDL, loopback, virtual interfaces
        if lowerBSD.hasPrefix("awdl") || lowerBSD.hasPrefix("llw") || lowerBSD.hasPrefix("lo") || lowerBSD.hasPrefix("gif") || lowerBSD.hasPrefix("stf") {
            return true
        }

        return false
    }
}
