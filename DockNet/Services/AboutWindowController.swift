import AppKit
import SwiftUI

/// Manages a single native About window instance for DockNet.
@MainActor
public final class AboutWindowController: NSObject, NSWindowDelegate {
    public static let shared = AboutWindowController()

    private var window: NSWindow?
    public var urlOpener: any URLOpening = WorkspaceURLOpener()

    private override init() {
        super.init()
    }

    /// Displays the About window, creating it if needed or bringing the existing one to the front.
    public func showAboutWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = AboutView(urlOpener: urlOpener)
        let hostingController = NSHostingController(rootView: aboutView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newWindow.center()
        newWindow.title = "About DockNet"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.setAccessibilityIdentifier("docknet.about.window")

        // Window behavior
        newWindow.level = .floating
        newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newWindow.standardWindowButton(.zoomButton)?.isHidden = true

        self.window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        self.window = nil
    }
}
