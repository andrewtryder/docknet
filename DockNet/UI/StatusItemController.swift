import AppKit
import os

/// Native AppKit status bar item controller managing the DockNet menu bar item and dynamic NSMenu.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "StatusItemController")

    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let networkMonitor: NetworkMonitor
    private let notificationManager: NotificationManager
    private let loginItemManager: LoginItemManager
    private var currentIconState: StatusIconState?

    public init(
        networkMonitor: NetworkMonitor,
        notificationManager: NotificationManager,
        loginItemManager: LoginItemManager
    ) {
        self.networkMonitor = networkMonitor
        self.notificationManager = notificationManager
        self.loginItemManager = loginItemManager

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()

        super.init()

        self.menu.delegate = self
        self.menu.autoenablesItems = false
        self.statusItem.menu = self.menu

        if let button = statusItem.button {
            button.setAccessibilityElement(true)
            button.setAccessibilityIdentifier("docknet.status.icon")
        }

        updateIcon(snapshot: networkMonitor.currentSnapshot)
    }

    public func updateSnapshot(_ snapshot: NetworkSnapshot) {
        updateIcon(snapshot: snapshot)
    }

    private func updateIcon(snapshot: NetworkSnapshot) {
        let state = StatusIconState.from(snapshot: snapshot)
        guard state != currentIconState else { return }
        currentIconState = state

        guard let button = statusItem.button else { return }
        button.image = StatusIconRenderer.image(for: state)
        button.toolTip = state.accessibilityLabel
        button.setAccessibilityLabel(state.accessibilityLabel)
        button.setAccessibilityValue(state.accessibilityLabel)
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        buildMenuItems()
    }

    private func buildMenuItems() {
        menu.removeAllItems()

        let snapshot = networkMonitor.currentSnapshot

        // 1. Primary Connection
        let primaryHeader = NSMenuItem(title: "Primary Connection", action: nil, keyEquivalent: "")
        primaryHeader.isEnabled = false
        menu.addItem(primaryHeader)

        if snapshot.actualPrimaryIsWired, let active = snapshot.activePrimaryWiredInterface {
            let item = NSMenuItem(title: "\(active.serviceName) (Primary)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)

            let detail = NSMenuItem(title: "   \(active.bsdName) · \(active.ipv4Address ?? "No IP")", action: nil, keyEquivalent: "")
            detail.isEnabled = false
            menu.addItem(detail)

            if let speed = active.linkSpeed {
                let speedItem = NSMenuItem(title: "   \(speed)", action: nil, keyEquivalent: "")
                speedItem.isEnabled = false
                menu.addItem(speedItem)
            }
        } else if snapshot.isWifiPrimary {
            let item = NSMenuItem(title: "Wi-Fi (Primary)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)

            let detail = NSMenuItem(title: "   \(snapshot.wifi.bsdName) · \(snapshot.wifi.primaryIPv4Address ?? "No IP")", action: nil, keyEquivalent: "")
            detail.isEnabled = false
            menu.addItem(detail)
        } else {
            let item = NSMenuItem(title: "No Active Primary Connection", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Other Connections
        let otherWired = snapshot.actualPrimaryIsWired
            ? snapshot.wiredInterfaces.filter { !$0.isPrimary }
            : snapshot.wiredInterfaces
        let showWifiStandby = snapshot.actualPrimaryIsWired

        if !otherWired.isEmpty || showWifiStandby {
            let otherHeader = NSMenuItem(title: "Other Connections", action: nil, keyEquivalent: "")
            otherHeader.isEnabled = false
            menu.addItem(otherHeader)

            for iface in otherWired {
                let title = "\(iface.serviceName) · \(iface.statusSummary) (\(iface.bsdName)\(iface.ipv4Address.map { " · \($0)" } ?? ""))"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }

            if showWifiStandby {
                let wifiTitle = "Wi-Fi · \(snapshot.wifiStatusText) (\(snapshot.wifi.bsdName)\(snapshot.wifi.primaryIPv4Address.map { " · \($0)" } ?? ""))"
                let item = NSMenuItem(title: wifiTitle, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }

            menu.addItem(NSMenuItem.separator())
        }

        // 3. Preferences
        let notifyItem = NSMenuItem(
            title: "Notify on connection changes",
            action: #selector(toggleNotificationsAction),
            keyEquivalent: ""
        )
        notifyItem.target = self
        notifyItem.state = notificationManager.isPreferenceEnabled ? .on : .off
        menu.addItem(notifyItem)

        loginItemManager.refreshStatus()
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLoginAction),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = loginItemManager.isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Actions
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(title: "Open Network Settings…", action: #selector(openNetworkSettingsAction), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About DockNet…", action: #selector(openAboutAction), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit DockNet", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func toggleNotificationsAction() {
        let current = notificationManager.isPreferenceEnabled
        Task { @MainActor in
            _ = await notificationManager.setPreferenceEnabled(!current)
        }
    }

    @objc private func toggleLaunchAtLoginAction() {
        loginItemManager.toggleLaunchAtLogin()
    }

    @objc private func refreshAction() {
        networkMonitor.refresh()
    }

    @objc private func openNetworkSettingsAction() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")
            ?? URL(string: "x-apple.systempreferences:")!
        WorkspaceURLOpener().open(url)
    }

    @objc private func openAboutAction() {
        AboutWindowController.shared.showAboutWindow()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
