import Foundation
import os

/// Unified network monitor combining SystemConfiguration and Network.framework,
/// feeding snapshots into the NetworkStateMachine.
public final class NetworkMonitor: NetworkMonitoringProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "NetworkMonitor")

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
            Self.logger.debug("PathMonitor observed reachability update: satisfied=\(pathInfo.isSatisfied)")
            // NWPathMonitor provides supplementary reachability only and must not synthesize
            // or overwrite systemPrimaryInterface. Request authoritative refresh from SCDynamicStore.
            self.scMonitor.requestRefresh()
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
