import Foundation

/// Represents the health state of the physical Ethernet interface.
public enum EthernetHealthState: String, Codable, Equatable, Sendable, CustomStringConvertible {
    /// Service is disabled in macOS Network Settings.
    case disabled

    /// Physical adapter hardware is not present/plugged into the system.
    case adapterNotPresent

    /// Physical adapter is present, but Ethernet cable/carrier is disconnected.
    case cableDisconnected

    /// General disconnected fallback.
    case disconnected

    /// Physical link is active, but no IP configuration has started or been received.
    case linkUp

    /// Physical link is active, waiting for DHCP lease or IPv4 address assignment.
    case obtainingDHCP

    /// Physical link is active, valid non-self-assigned IPv4 address and gateway are present.
    case ready

    /// Physical link is active, but configuration is invalid (e.g. 169.254.x.x link-local or missing gateway).
    case degraded

    public var description: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .adapterNotPresent:
            return "Adapter Not Present"
        case .cableDisconnected:
            return "Cable Disconnected"
        case .disconnected:
            return "Disconnected"
        case .linkUp:
            return "Link Detected"
        case .obtainingDHCP:
            return "Obtaining DHCP"
        case .ready:
            return "Ready"
        case .degraded:
            return "Degraded"
        }
    }

    public var sfSymbolName: String {
        switch self {
        case .disabled:
            return "slash.circle"
        case .adapterNotPresent:
            return "cable.connector.slash"
        case .cableDisconnected, .disconnected:
            return "cable.connector.slash"
        case .linkUp, .obtainingDHCP:
            return "cable.connector"
        case .ready:
            return "cable.connector.horizontal"
        case .degraded:
            return "exclamationmark.triangle"
        }
    }

    public var isUsable: Bool {
        self == .ready
    }
}
