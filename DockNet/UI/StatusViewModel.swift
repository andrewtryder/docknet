import Foundation
import SwiftUI
import AppKit
import UserNotifications
import os

@MainActor
public final class StatusViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "StatusViewModel")

    @Published public private(set) var snapshot: NetworkSnapshot
    @Published public var isNotificationsEnabled: Bool
    @Published public var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    public let loginItemManager: LoginItemManager
    public let networkMonitor: any NetworkMonitoringProtocol
    public let notificationManager: NotificationManager
    public let aboutWindowController: AboutWindowController

    public init(
        networkMonitor: any NetworkMonitoringProtocol = NetworkMonitor(),
        loginItemManager: LoginItemManager? = nil,
        notificationManager: NotificationManager = NotificationManager(),
        aboutWindowController: AboutWindowController? = nil
    ) {
        self.networkMonitor = networkMonitor
        self.loginItemManager = loginItemManager ?? LoginItemManager()
        self.notificationManager = notificationManager
        self.aboutWindowController = aboutWindowController ?? AboutWindowController.shared
        self.snapshot = networkMonitor.currentSnapshot
        self.isNotificationsEnabled = notificationManager.isPreferenceEnabled

        setupMonitoring()
        checkNotificationAuthStatus()
    }

    /// Creates a configured StatusViewModel instance based on runtime environment (UI testing vs production).
    public static func makeConfiguredInstance() -> StatusViewModel {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment

        if args.contains("--ui-testing") && !args.contains("--live-mode") {
            var scenario = "wifi"
            var stateFile: String? = nil

            for arg in args {
                if arg.hasPrefix("--state=") {
                    scenario = String(arg.dropFirst("--state=".count))
                } else if arg.hasPrefix("--state-file=") {
                    stateFile = String(arg.dropFirst("--state-file=".count))
                }
            }

            // Fallback to environment variables if arguments were not provided
            if let envScenario = env["DOCKNET_TEST_NETWORK_STATE"] {
                scenario = envScenario
            }
            if let envFile = env["DOCKNET_TEST_STATE_FILE"] {
                stateFile = envFile
            }

            Self.logger.info("Initializing StatusViewModel with MockNetworkMonitor (scenario: \(scenario), stateFile: \(stateFile ?? "none"))")
            let mockMonitor = MockNetworkMonitor(scenario: scenario, stateFilePath: stateFile)

            // Inject mock notification scheduler & mock URL opener for test isolation
            let mockScheduler = MockNotificationScheduler(status: .notDetermined)
            let mockNotificationManager = NotificationManager(
                scheduler: mockScheduler,
                userDefaults: UserDefaults(suiteName: "com.andrewtryder.docknet.tests") ?? .standard,
                debounceInterval: 0 // Immediate execution in tests
            )

            let mockURLOpener = MockURLOpener()
            AboutWindowController.shared.urlOpener = mockURLOpener

            return StatusViewModel(
                networkMonitor: mockMonitor,
                notificationManager: mockNotificationManager,
                aboutWindowController: AboutWindowController.shared
            )
        } else {
            Self.logger.info("Initializing StatusViewModel with production NetworkMonitor")
            return StatusViewModel(
                networkMonitor: NetworkMonitor(),
                notificationManager: NotificationManager(),
                aboutWindowController: AboutWindowController.shared
            )
        }
    }

    private func setupMonitoring() {
        networkMonitor.onSnapshotUpdated = { [weak self] newSnapshot in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.snapshot = newSnapshot
                self.notificationManager.processSnapshot(newSnapshot)
            }
        }

        networkMonitor.startMonitoring()
    }

    private func checkNotificationAuthStatus() {
        Task { [weak self] in
            guard let self = self else { return }
            let status = await self.notificationManager.scheduler.authorizationStatus()
            await MainActor.run {
                self.notificationAuthStatus = status
                if status == .denied && self.isNotificationsEnabled {
                    self.isNotificationsEnabled = false
                    self.notificationManager.isPreferenceEnabled = false
                }
            }
        }
    }

    // MARK: - Notification Preference Action

    public func setNotificationsEnabled(_ enabled: Bool) {
        Task { [weak self] in
            guard let self = self else { return }
            let newStatus = await self.notificationManager.setPreferenceEnabled(enabled)
            await MainActor.run {
                self.notificationAuthStatus = newStatus
                self.isNotificationsEnabled = self.notificationManager.isPreferenceEnabled
            }
        }
    }

    // MARK: - Computed Properties for UI

    public var wiredInterfaces: [WiredInterfaceState] {
        snapshot.wiredInterfaces
    }

    public var preferredWiredInterface: WiredInterfaceState? {
        snapshot.preferredWiredInterface
    }

    public var statusIconAccessibilityLabel: String {
        if snapshot.actualPrimaryIsWired {
            let bsd = snapshot.activePrimaryWiredInterface?.bsdName ?? "ethernet"
            return "DockNet — Ethernet primary, \(bsd)"
        }
        if snapshot.wiredInterfaces.contains(where: { $0.health == .obtainingDHCP || $0.health == .linkUp }) {
            return "DockNet — Ethernet negotiating"
        }
        if snapshot.wiredInterfaces.contains(where: { $0.health == .degraded }) {
            return "DockNet — Ethernet degraded"
        }
        return "DockNet — Wi-Fi primary, \(snapshot.wifi.bsdName)"
    }

    public var statusIconBadge: StatusIconBadge {
        if snapshot.actualPrimaryIsWired {
            return .none
        }
        if snapshot.wiredInterfaces.contains(where: { $0.health == .obtainingDHCP || $0.health == .linkUp }) {
            return .negotiating
        }
        if snapshot.wiredInterfaces.contains(where: { $0.health == .degraded }) {
            return .degraded
        }
        return .none
    }

    public var menuBarIconName: String {
        if snapshot.actualPrimaryIsWired {
            return "cable.connector.horizontal"
        }

        if let preferred = preferredWiredInterface {
            switch preferred.health {
            case .ready:
                return "cable.connector.horizontal"
            case .linkUp, .obtainingDHCP:
                return "cable.connector"
            case .degraded:
                return "exclamationmark.triangle.fill"
            case .cableDisconnected, .disconnected, .adapterNotPresent, .disabled:
                break
            }
        }

        if snapshot.wiredInterfaces.contains(where: { $0.health == .degraded }) {
            return "exclamationmark.triangle.fill"
        }

        if snapshot.wiredInterfaces.contains(where: { $0.health == .obtainingDHCP || $0.health == .linkUp }) {
            return "cable.connector"
        }

        if snapshot.isWifiPrimary {
            return "wifi"
        }

        return "network.slash"
    }

    public var activeConnectionTitle: String {
        switch snapshot.physicalTransport.kind {
        case .ethernet:
            return "Ethernet"
        case .wifi:
            return "Wi-Fi"
        case .none:
            return "No Connection"
        }
    }

    public var activeConnectionSubtitle: String {
        switch snapshot.physicalTransport.kind {
        case .ethernet:
            if let activeWired = snapshot.activePrimaryWiredInterface {
                let ip = activeWired.ipv4Address ?? "No IP"
                return "\(activeWired.serviceName) (\(activeWired.bsdName)) · \(ip)"
            } else if let bsd = snapshot.physicalPrimaryInterface {
                let name = snapshot.physicalTransport.serviceName ?? "Ethernet"
                let ip = snapshot.physicalTransport.ipv4Address ?? "No IP"
                return "\(name) (\(bsd)) · \(ip)"
            } else {
                return "Ethernet"
            }
        case .wifi:
            let ip = snapshot.wifi.primaryIPv4Address ?? "No IP"
            return "\(snapshot.wifi.serviceName) (\(snapshot.wifi.bsdName)) · \(ip)"
        case .none:
            return "Offline"
        }
    }

    public var primaryPathTitle: String {
        switch snapshot.physicalTransport.kind {
        case .ethernet:
            if let activeWired = snapshot.activePrimaryWiredInterface {
                return "Ethernet (\(activeWired.serviceName))"
            }
            return "Ethernet"
        case .wifi:
            return "Wi-Fi (\(snapshot.wifi.bsdName))"
        case .none:
            return "None"
        }
    }

    public var wifiStatusText: String {
        snapshot.wifiStatusText
    }

    // MARK: - User Actions

    public func refresh() {
        Self.logger.info("Manual refresh triggered from UI")
        networkMonitor.refresh()
        checkNotificationAuthStatus()
    }

    public func openAboutWindow() {
        Self.logger.info("Opening About DockNet window")
        aboutWindowController.showAboutWindow()
    }

    public func openNetworkSettings() {
        Self.logger.info("Opening Network Settings")
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else if let fallbackUrl = URL(string: "x-apple.systempreferences:com.apple.preference.network") {
            NSWorkspace.shared.open(fallbackUrl)
        }
    }

    public func openNotificationSettings() {
        Self.logger.info("Opening Notifications Settings")
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else if let fallbackUrl = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(fallbackUrl)
        }
    }

    public func quit() {
        Self.logger.info("Quit requested by user")
        NSApplication.shared.terminate(nil)
    }
}
