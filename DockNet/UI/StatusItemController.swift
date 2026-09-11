import AppKit
import os

/// Native AppKit status bar item controller managing the DockNet menu bar item,
/// routing between Compact (NSMenu) and Detailed (NSPopover) presentation styles.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "StatusItemController")

    public let statusItem: NSStatusItem
    public let menu: NSMenu
    public let networkMonitor: any NetworkMonitoringProtocol
    public let notificationManager: NotificationManager
    public let loginItemManager: LoginItemManager
    public let presentationPreferences: PresentationPreferences

    private var currentIconState: StatusIconState?
    public private(set) var detailedPopoverController: DetailedPopoverController?

    public init(
        networkMonitor: any NetworkMonitoringProtocol,
        notificationManager: NotificationManager,
        loginItemManager: LoginItemManager,
        presentationPreferences: PresentationPreferences = PresentationPreferences()
    ) {
        self.networkMonitor = networkMonitor
        self.notificationManager = notificationManager
        self.loginItemManager = loginItemManager
        self.presentationPreferences = presentationPreferences

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()

        super.init()

        self.menu.delegate = self
        self.menu.autoenablesItems = false

        if let button = statusItem.button {
            button.setAccessibilityElement(true)
            button.setAccessibilityIdentifier("docknet.status.icon")
        }

        applyPresentationStyle(presentationPreferences.style)
        updateIcon(snapshot: networkMonitor.currentSnapshot)
    }

    public func updateSnapshot(_ snapshot: NetworkSnapshot) {
        updateIcon(snapshot: snapshot)
        if let popover = detailedPopoverController, popover.isShown {
            popover.updateSnapshot(snapshot)
        }
    }

    public func setPresentationStyle(_ style: PresentationStyle) {
        guard presentationPreferences.style != style else { return }
        Self.logger.info("Switching presentation style to \(style.rawValue)")
        presentationPreferences.style = style
        applyPresentationStyle(style)
    }

    private func applyPresentationStyle(_ style: PresentationStyle) {
        switch style {
        case .compact:
            detailedPopoverController?.closePopover()
            statusItem.menu = self.menu
            if let button = statusItem.button {
                button.target = nil
                button.action = nil
            }

        case .detailed:
            menu.cancelTracking()
            statusItem.menu = nil
            if let button = statusItem.button {
                button.target = self
                button.action = #selector(statusItemClicked(_:))
            }
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if detailedPopoverController == nil {
            detailedPopoverController = DetailedPopoverController(
                networkMonitor: networkMonitor,
                notificationManager: notificationManager,
                loginItemManager: loginItemManager,
                presentationPreferences: presentationPreferences,
                onStyleChanged: { [weak self] newStyle in
                    self?.setPresentationStyle(newStyle)
                }
            )
        }

        detailedPopoverController?.togglePopover(anchorView: button)
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
        CompactMenuBuilder.build(
            menu: menu,
            snapshot: networkMonitor.currentSnapshot,
            notificationManager: notificationManager,
            loginItemManager: loginItemManager,
            presentationPreferences: presentationPreferences,
            target: self
        )
    }

    // MARK: - Menu Actions

    @objc public func selectCompactStyleAction() {
        setPresentationStyle(.compact)
    }

    @objc public func selectDetailedStyleAction() {
        setPresentationStyle(.detailed)
    }

    @objc public func toggleNotificationsAction() {
        let current = notificationManager.isPreferenceEnabled
        Task { @MainActor in
            _ = await notificationManager.setPreferenceEnabled(!current)
        }
    }

    @objc public func toggleLaunchAtLoginAction() {
        loginItemManager.toggleLaunchAtLogin()
    }

    @objc public func refreshAction() {
        networkMonitor.refresh()
    }

    @objc public func openNetworkSettingsAction() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")
            ?? URL(string: "x-apple.systempreferences:")!
        WorkspaceURLOpener().open(url)
    }

    @objc public func openAboutAction() {
        AboutWindowController.shared.showAboutWindow()
    }

    @objc public func quitAction() {
        NSApp.terminate(nil)
    }
}
