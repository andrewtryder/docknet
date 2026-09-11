import Foundation

/// Defines connection categories for primary network routing.
public enum ConnectionType: String, Equatable, Sendable {
    case ethernet
    case wifi
    case other
    case none
}

/// Represents the active primary connection details.
public struct PrimaryConnection: Equatable, Sendable {
    public let type: ConnectionType
    public let serviceName: String?
    public let bsdName: String
    public let ipv4Address: String?

    public init(
        type: ConnectionType,
        serviceName: String? = nil,
        bsdName: String,
        ipv4Address: String? = nil
    ) {
        self.type = type
        self.serviceName = serviceName
        self.bsdName = bsdName
        self.ipv4Address = ipv4Address
    }
}

/// Represents a state transition between two primary connections.
public struct ConnectionTransition: Equatable, Sendable {
    public let from: PrimaryConnection
    public let to: PrimaryConnection

    public init(from: PrimaryConnection, to: PrimaryConnection) {
        self.from = from
        self.to = to
    }
}

/// Pure data model representing a user notification.
public struct DockNetNotification: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String

    public init(identifier: String, title: String, body: String) {
        self.identifier = identifier
        self.title = title
        self.body = body
    }
}

/// Pure formatter producing notification titles and bodies for stable transitions.
public struct NotificationFormatter: Sendable {
    public static func format(
        transition: ConnectionTransition,
        sequence: Int = Int(Date().timeIntervalSince1970 * 1000)
    ) -> DockNetNotification? {
        let from = transition.from
        let to = transition.to

        // Same interface -> no notification
        if from == to || (from.bsdName == to.bsdName && from.type == to.type) {
            return nil
        }

        let id = "docknet.primary-transition.\(sequence)"

        // Case 1: Wi-Fi -> Ethernet
        if from.type == .wifi && to.type == .ethernet {
            let sName = to.serviceName ?? "Ethernet"
            let ipPart = to.ipv4Address.map { " · \($0)" } ?? ""
            return DockNetNotification(
                identifier: id,
                title: "Switched to Ethernet",
                body: "\(sName) · \(to.bsdName)\(ipPart)"
            )
        }

        // Case 2: Ethernet -> Wi-Fi
        if from.type == .ethernet && to.type == .wifi {
            let ipPart = to.ipv4Address.map { " · \($0)" } ?? ""
            return DockNetNotification(
                identifier: id,
                title: "Switched to Wi-Fi",
                body: "Using \(to.bsdName)\(ipPart)"
            )
        }

        // Case 3: Ethernet -> different Ethernet (e.g. en8 -> en6)
        if from.type == .ethernet && to.type == .ethernet {
            let sName = to.serviceName ?? "Ethernet"
            let ipPart = to.ipv4Address.map { " · \($0)" } ?? ""
            return DockNetNotification(
                identifier: id,
                title: "Switched Ethernet connection",
                body: "\(sName) · \(to.bsdName)\(ipPart)"
            )
        }

        // General fallback
        if to.type == .ethernet {
            let sName = to.serviceName ?? "Ethernet"
            return DockNetNotification(
                identifier: id,
                title: "Switched to Ethernet",
                body: "\(sName) · \(to.bsdName)"
            )
        } else if to.type == .wifi {
            return DockNetNotification(
                identifier: id,
                title: "Switched to Wi-Fi",
                body: "Using \(to.bsdName)"
            )
        }

        return nil
    }
}
