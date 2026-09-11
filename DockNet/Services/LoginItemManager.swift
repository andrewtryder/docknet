import Foundation
import ServiceManagement
import os

/// Manages macOS Launch at Login via modern SMAppService (macOS 13.0+).
@MainActor
public final class LoginItemManager: ObservableObject {
    private static let logger = Logger(subsystem: "com.local.DockNet", category: "LoginItemManager")

    @Published public private(set) var isLaunchAtLoginEnabled: Bool = false
    @Published public private(set) var statusDescription: String = "Disabled"

    private let service = SMAppService.mainApp

    public init() {
        refreshStatus()
    }

    public func refreshStatus() {
        let status = service.status
        switch status {
        case .enabled:
            isLaunchAtLoginEnabled = true
            statusDescription = "Enabled"
        case .notRegistered:
            isLaunchAtLoginEnabled = false
            statusDescription = "Not Registered"
        case .requiresApproval:
            isLaunchAtLoginEnabled = false
            statusDescription = "Requires Approval in System Settings"
        case .notFound:
            isLaunchAtLoginEnabled = false
            statusDescription = "Not Found"
        @unknown default:
            isLaunchAtLoginEnabled = false
            statusDescription = "Unknown"
        }
        Self.logger.debug("Launch at login status: \(self.statusDescription, privacy: .public)")
    }

    public func toggleLaunchAtLogin() {
        setLaunchAtLogin(enabled: !isLaunchAtLoginEnabled)
    }

    public func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                    Self.logger.info("SMAppService registered successfully")
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                    Self.logger.info("SMAppService unregistered successfully")
                }
            }
        } catch {
            Self.logger.error("Failed to update Launch at Login: \(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
    }
}
