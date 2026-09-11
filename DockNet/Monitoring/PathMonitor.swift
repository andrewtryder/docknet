import Foundation
import Network
import os

/// Observes macOS network path viability and default route selection via Network.framework.
public final class PathMonitor: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "PathMonitor")

    public struct PathStatusInfo: Equatable, Sendable {
        public let isSatisfied: Bool
        public let primaryInterfaceName: String?
        public let availableInterfaceNames: [String]
        public let isExpensive: Bool
        public let isConstrained: Bool

        public init(
            isSatisfied: Bool,
            primaryInterfaceName: String?,
            availableInterfaceNames: [String],
            isExpensive: Bool,
            isConstrained: Bool
        ) {
            self.isSatisfied = isSatisfied
            self.primaryInterfaceName = primaryInterfaceName
            self.availableInterfaceNames = availableInterfaceNames
            self.isExpensive = isExpensive
            self.isConstrained = isConstrained
        }
    }

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private var isMonitoring: Bool = false

    public var onPathUpdated: (@Sendable (PathStatusInfo) -> Void)?

    public init(queue: DispatchQueue = DispatchQueue(label: "com.andrewtryder.docknet.pathmonitor", qos: .utility)) {
        self.monitor = NWPathMonitor()
        self.queue = queue
    }

    deinit {
        stop()
    }

    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let primaryInterface = path.availableInterfaces.first { iface in
                path.usesInterfaceType(iface.type)
            }?.name ?? path.availableInterfaces.first?.name

            let info = PathStatusInfo(
                isSatisfied: path.status == .satisfied,
                primaryInterfaceName: primaryInterface,
                availableInterfaceNames: path.availableInterfaces.map(\.name),
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained
            )

            Self.logger.debug("NWPath updated: satisfied=\(info.isSatisfied), primary=\(info.primaryInterfaceName ?? "none")")
            self.onPathUpdated?(info)
        }

        monitor.start(queue: queue)
    }

    public func stop() {
        guard isMonitoring else { return }
        monitor.cancel()
        isMonitoring = false
    }
}
