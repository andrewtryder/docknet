import AppKit
import os

/// Manages the lifecycle, presentation, and snapshot updates of the Detailed NSPopover.
/// Designed for zero idle cost when closed.
@MainActor
public final class DetailedPopoverController: NSObject, NSPopoverDelegate {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "DetailedPopoverController")

    private let popover: NSPopover
    private let statusViewController: DetailedStatusViewController
    private let networkMonitor: any NetworkMonitoringProtocol

    public var isShown: Bool {
        popover.isShown
    }

    public init(
        networkMonitor: any NetworkMonitoringProtocol,
        notificationManager: NotificationManager,
        loginItemManager: LoginItemManager,
        presentationPreferences: PresentationPreferences,
        onStyleChanged: @escaping (PresentationStyle) -> Void
    ) {
        self.networkMonitor = networkMonitor
        self.popover = NSPopover()

        let vc = DetailedStatusViewController(
            networkMonitor: networkMonitor,
            notificationManager: notificationManager,
            loginItemManager: loginItemManager,
            presentationPreferences: presentationPreferences,
            onStyleChanged: { [weak popover = self.popover] newStyle in
                onStyleChanged(newStyle)
                if newStyle == .compact {
                    popover?.performClose(nil)
                }
            }
        )
        self.statusViewController = vc

        super.init()

        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    private var lastClosedTimestamp: TimeInterval = 0

    /// Toggles the detailed popover relative to the status item button.
    public func togglePopover(anchorView: NSView) {
        if popover.isShown {
            closePopover()
        } else {
            let timeSinceClose = ProcessInfo.processInfo.systemUptime - lastClosedTimestamp
            if timeSinceClose < 0.25 {
                return
            }
            showPopover(anchorView: anchorView)
        }
    }

    /// Displays the popover anchored to the specified view using the latest snapshot.
    public func showPopover(anchorView: NSView) {
        guard !popover.isShown else { return }
        Self.logger.debug("Opening detailed popover")
        statusViewController.update(with: networkMonitor.currentSnapshot)
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        anchorView.window?.makeKey()
    }

    /// Closes the popover if currently visible.
    public func closePopover() {
        guard popover.isShown else { return }
        Self.logger.debug("Closing detailed popover")
        popover.performClose(nil)
    }

    /// Updates the view controller with the new snapshot ONLY if the popover is currently visible.
    public func updateSnapshot(_ snapshot: NetworkSnapshot) {
        guard popover.isShown else { return }
        statusViewController.update(with: snapshot)
    }

    // MARK: - NSPopoverDelegate

    public func popoverDidClose(_ notification: Notification) {
        lastClosedTimestamp = ProcessInfo.processInfo.systemUptime
        Self.logger.debug("Detailed popover closed")
    }
}
