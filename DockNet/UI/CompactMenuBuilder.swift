import AppKit

/// Builds the optimized, text-oriented AppKit NSMenu for DockNet's Compact presentation style.
@MainActor
public enum CompactMenuBuilder {

    public static func build(
        menu: NSMenu,
        snapshot: NetworkSnapshot,
        notificationManager: NotificationManager,
        loginItemManager: LoginItemManager,
        presentationPreferences: PresentationPreferences,
        target: AnyObject
    ) {
        menu.removeAllItems()

        // 1. Primary Connection Section
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

        // 2. Other Connections Section
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

        // 3. Preferences Section
        let notifyItem = NSMenuItem(
            title: "Notify on connection changes",
            action: Selector(("toggleNotificationsAction")),
            keyEquivalent: ""
        )
        notifyItem.target = target
        notifyItem.state = notificationManager.isPreferenceEnabled ? .on : .off
        notifyItem.setAccessibilityIdentifier("docknet.notifications")
        menu.addItem(notifyItem)

        loginItemManager.refreshStatus()
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: Selector(("toggleLaunchAtLoginAction")),
            keyEquivalent: ""
        )
        loginItem.target = target
        loginItem.state = loginItemManager.isLaunchAtLoginEnabled ? .on : .off
        loginItem.setAccessibilityIdentifier("docknet.launchAtLogin")
        menu.addItem(loginItem)

        // Display Style Submenu
        let styleSubmenu = NSMenu(title: "Display Style")
        styleSubmenu.autoenablesItems = false

        let currentStyle = presentationPreferences.style

        let compactItem = NSMenuItem(
            title: "Compact",
            action: Selector(("selectCompactStyleAction")),
            keyEquivalent: ""
        )
        compactItem.target = target
        compactItem.state = (currentStyle == .compact) ? .on : .off
        compactItem.setAccessibilityIdentifier("docknet.presentation.compact")
        styleSubmenu.addItem(compactItem)

        let detailedItem = NSMenuItem(
            title: "Detailed",
            action: Selector(("selectDetailedStyleAction")),
            keyEquivalent: ""
        )
        detailedItem.target = target
        detailedItem.state = (currentStyle == .detailed) ? .on : .off
        detailedItem.setAccessibilityIdentifier("docknet.presentation.detailed")
        styleSubmenu.addItem(detailedItem)

        let styleParentItem = NSMenuItem(title: "Display Style", action: nil, keyEquivalent: "")
        styleParentItem.submenu = styleSubmenu
        styleParentItem.setAccessibilityIdentifier("docknet.presentation")
        menu.addItem(styleParentItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Actions Section
        let refreshItem = NSMenuItem(title: "Refresh", action: Selector(("refreshAction")), keyEquivalent: "r")
        refreshItem.target = target
        refreshItem.setAccessibilityIdentifier("docknet.refresh")
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(title: "Open Network Settings…", action: Selector(("openNetworkSettingsAction")), keyEquivalent: "")
        settingsItem.target = target
        settingsItem.setAccessibilityIdentifier("docknet.openSettings")
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About DockNet…", action: Selector(("openAboutAction")), keyEquivalent: "")
        aboutItem.target = target
        aboutItem.setAccessibilityIdentifier("docknet.about")
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit DockNet", action: Selector(("quitAction")), keyEquivalent: "q")
        quitItem.target = target
        quitItem.setAccessibilityIdentifier("docknet.quit")
        menu.addItem(quitItem)
    }
}
