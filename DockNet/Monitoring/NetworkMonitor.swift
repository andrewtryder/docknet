import Foundation
import os

/// Unified network monitor combining SystemConfiguration and Network.framework,
/// feeding snapshots into the NetworkStateMachine.
public final class NetworkMonitor: NetworkMonitoringProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.local.DockNet", category: "NetworkMonitor")

    private let scMonitor: SystemConfigurationMonitor
    private let pathMonitor: PathMonitor
    public let stateMachine: NetworkStateMachine

    private let lock = NSLock()
    private var _currentSnapshot: NetworkSnapshot
    public var onSnapshotUpdated: (@Sendable (NetworkSnapshot) -> Void)?

    public init(stateMachine: NetworkStateMachine = NetworkStateMachine()) {
        self.stateMachine = stateMachine
        self.scMonitor = SystemConfigurationMonitor(stateMachine: stateMachine)
        self.pathMonitor = PathMonitor()

        let emptyWifi = NetworkInterfaceInfo(bsdName: "en0", serviceName: "Wi-Fi", isLinkActive: false)
        self._currentSnapshot = NetworkSnapshot(wiredInterfaces: [], wifi: emptyWifi)

        setupBindings()
    }

    public var currentSnapshot: NetworkSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return _currentSnapshot
    }

    private func setupBindings() {
        scMonitor.onSnapshotUpdated = { [weak self] snapshot in
            guard let self = self else { return }
            self.handleNewSnapshot(snapshot)
        }

        pathMonitor.onPathUpdated = { [weak self] pathInfo in
            guard let self = self else { return }
            self.lock.lock()
            let current = self._currentSnapshot
            self.lock.unlock()

            if let nwPrimary = pathInfo.primaryInterfaceName, nwPrimary != current.primaryInterface {
                Self.logger.debug("PathMonitor observed primary interface shift to \(nwPrimary)")
                let updated = NetworkSnapshot(
                    wiredInterfaces: current.wiredInterfaces,
                    wifi: current.wifi,
                    primaryInterface: nwPrimary,
                    primaryServiceID: current.primaryServiceID,
                    primaryServiceName: current.primaryServiceName,
                    globalIPv4Router: current.globalIPv4Router,
                    timestamp: Date()
                )
                self.handleNewSnapshot(updated)
            }
        }
    }

    private func handleNewSnapshot(_ snapshot: NetworkSnapshot) {
        lock.lock()
        _currentSnapshot = snapshot
        lock.unlock()

        stateMachine.process(snapshot: snapshot)
        onSnapshotUpdated?(snapshot)
    }

    public func startMonitoring() {
        Self.logger.info("Starting network monitoring")
        scMonitor.start()
        pathMonitor.start()
    }

    public func stopMonitoring() {
        Self.logger.info("Stopping network monitoring")
        scMonitor.stop()
        pathMonitor.stop()
    }

    public func refresh() {
        Self.logger.debug("Explicit refresh requested")
        scMonitor.requestRefresh()
    }
}
