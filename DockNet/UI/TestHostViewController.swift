import AppKit
import os

/// Native AppKit test host view controller providing a predictable, accessible UI surface
/// for XCUITest automation (--ui-testing mode). Zero SwiftUI dependencies.
@MainActor
public final class TestHostViewController: NSViewController {
    private let networkMonitor: any NetworkMonitoringProtocol
    private let notificationManager: NotificationManager
    private let loginItemManager: LoginItemManager

    private var contentStack: NSStackView!
    private var iconView: NSImageView!
    private var headerTitle: NSTextField!

    private var primaryTypeLabel: NSTextField!
    private var primaryInterfaceLabel: NSTextField!
    private var primaryCardsContainer: NSStackView!

    private var otherConnectionsContainer: NSStackView!

    private var notificationsCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!

    public init(
        networkMonitor: any NetworkMonitoringProtocol,
        notificationManager: NotificationManager,
        loginItemManager: LoginItemManager
    ) {
        self.networkMonitor = networkMonitor
        self.notificationManager = notificationManager
        self.loginItemManager = loginItemManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 750))
        self.view = root

        let scrollView = NSScrollView(frame: root.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        root.addSubview(scrollView)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor, constant: -14)
        ])

        self.contentStack = stack

        // 1. Header
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.spacing = 8

        let icon = NSImageView()
        icon.setAccessibilityElement(true)
        icon.setAccessibilityIdentifier("docknet.status.icon")
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22)
        ])
        self.iconView = icon
        headerStack.addArrangedSubview(icon)

        let title = NSTextField(labelWithString: "DockNet")
        title.font = NSFont.boldSystemFont(ofSize: 14)
        title.setAccessibilityIdentifier("docknet.header.title")
        title.setAccessibilityLabel("DockNet Application")
        self.headerTitle = title
        headerStack.addArrangedSubview(title)

        stack.addArrangedSubview(headerStack)
        stack.addArrangedSubview(makeSeparator())

        // 2. Primary Connection Section
        let primarySectionLabel = NSTextField(labelWithString: "PRIMARY CONNECTION")
        primarySectionLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        primarySectionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(primarySectionLabel)

        let primaryCard = NSStackView()
        primaryCard.orientation = .vertical
        primaryCard.alignment = .leading
        primaryCard.spacing = 4
        self.primaryCardsContainer = primaryCard
        stack.addArrangedSubview(primaryCard)

        stack.addArrangedSubview(makeSeparator())

        // 3. Other Connections Section
        let otherSectionLabel = NSTextField(labelWithString: "OTHER CONNECTIONS")
        otherSectionLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        otherSectionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(otherSectionLabel)

        let otherContainer = NSStackView()
        otherContainer.orientation = .vertical
        otherContainer.alignment = .leading
        otherContainer.spacing = 4
        self.otherConnectionsContainer = otherContainer
        stack.addArrangedSubview(otherContainer)

        stack.addArrangedSubview(makeSeparator())

        // 4. Preferences & Toggles
        let notifyBtn = NSButton(checkboxWithTitle: "Notify on connection changes", target: self, action: #selector(toggleNotifications))
        notifyBtn.setAccessibilityIdentifier("docknet.notifications")
        notifyBtn.state = notificationManager.isPreferenceEnabled ? .on : .off
        self.notificationsCheckbox = notifyBtn
        stack.addArrangedSubview(notifyBtn)

        let loginBtn = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(toggleLogin))
        loginBtn.setAccessibilityIdentifier("docknet.launchAtLogin")
        loginBtn.state = loginItemManager.isLaunchAtLoginEnabled ? .on : .off
        self.launchAtLoginCheckbox = loginBtn
        stack.addArrangedSubview(loginBtn)

        stack.addArrangedSubview(makeSeparator())

        // 5. Actions
        let refreshBtn = NSButton(title: "Refresh", target: self, action: #selector(handleRefresh))
        refreshBtn.bezelStyle = .rounded
        refreshBtn.setAccessibilityIdentifier("docknet.refresh")
        stack.addArrangedSubview(refreshBtn)

        let settingsBtn = NSButton(title: "Open Network Settings…", target: self, action: #selector(handleSettings))
        settingsBtn.bezelStyle = .rounded
        settingsBtn.setAccessibilityIdentifier("docknet.openSettings")
        stack.addArrangedSubview(settingsBtn)

        let aboutBtn = NSButton(title: "About DockNet…", target: self, action: #selector(handleAbout))
        aboutBtn.bezelStyle = .rounded
        aboutBtn.setAccessibilityIdentifier("docknet.about")
        stack.addArrangedSubview(aboutBtn)

        let quitBtn = NSButton(title: "Quit DockNet", target: self, action: #selector(handleQuit))
        quitBtn.bezelStyle = .rounded
        quitBtn.setAccessibilityIdentifier("docknet.quit")
        stack.addArrangedSubview(quitBtn)

        update(with: networkMonitor.currentSnapshot)
    }

    public func update(with snapshot: NetworkSnapshot) {
        let state = StatusIconState.from(snapshot: snapshot)
        iconView.image = StatusIconRenderer.image(for: state)
        iconView.setAccessibilityLabel(state.accessibilityLabel)
        iconView.setAccessibilityValue(state.accessibilityLabel)
        iconView.setAccessibilityTitle(state.accessibilityLabel)

        // Clear previous cards
        primaryCardsContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        otherConnectionsContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Update Primary Card
        if snapshot.actualPrimaryIsWired, let active = snapshot.activePrimaryWiredInterface {
            let typeLabel = NSTextField(labelWithString: "Ethernet")
            typeLabel.setAccessibilityIdentifier("docknet.primary.type")
            typeLabel.setAccessibilityLabel("Ethernet")
            typeLabel.setAccessibilityValue("Ethernet")
            typeLabel.setAccessibilityTitle("Ethernet")
            primaryCardsContainer.addArrangedSubview(typeLabel)

            let ifaceDetail = "\(active.bsdName) · \(active.ipv4Address ?? "No IP")"
            let ifaceLabel = NSTextField(labelWithString: ifaceDetail)
            ifaceLabel.setAccessibilityIdentifier("docknet.primary.interface")
            ifaceLabel.setAccessibilityLabel(ifaceDetail)
            ifaceLabel.setAccessibilityValue(ifaceDetail)
            ifaceLabel.setAccessibilityTitle(ifaceDetail)
            primaryCardsContainer.addArrangedSubview(ifaceLabel)

            let primaryBadge = NSTextField(labelWithString: "Primary")
            primaryBadge.setAccessibilityIdentifier("docknet.wired.\(active.bsdName).primary")
            primaryBadge.setAccessibilityLabel("Primary")
            primaryBadge.setAccessibilityValue("Primary")
            primaryBadge.setAccessibilityTitle("Primary")
            primaryCardsContainer.addArrangedSubview(primaryBadge)

            let healthLabel = NSTextField(labelWithString: active.statusSummary)
            healthLabel.setAccessibilityIdentifier("docknet.wired.\(active.bsdName).health")
            healthLabel.setAccessibilityLabel(active.statusSummary)
            healthLabel.setAccessibilityValue(active.statusSummary)
            healthLabel.setAccessibilityTitle(active.statusSummary)
            primaryCardsContainer.addArrangedSubview(healthLabel)

            if let speed = active.linkSpeed {
                let speedLabel = NSTextField(labelWithString: speed)
                speedLabel.setAccessibilityIdentifier("docknet.wired.\(active.bsdName).speed")
                speedLabel.setAccessibilityLabel(speed)
                speedLabel.setAccessibilityValue(speed)
                speedLabel.setAccessibilityTitle(speed)
                primaryCardsContainer.addArrangedSubview(speedLabel)
            }
        } else if snapshot.isWifiPrimary {
            let typeLabel = NSTextField(labelWithString: "Wi-Fi")
            typeLabel.setAccessibilityIdentifier("docknet.primary.type")
            typeLabel.setAccessibilityLabel("Wi-Fi")
            typeLabel.setAccessibilityValue("Wi-Fi")
            typeLabel.setAccessibilityTitle("Wi-Fi")
            primaryCardsContainer.addArrangedSubview(typeLabel)

            let ifaceDetail = "\(snapshot.wifi.bsdName) · \(snapshot.wifi.primaryIPv4Address ?? "No IP")"
            let ifaceLabel = NSTextField(labelWithString: ifaceDetail)
            ifaceLabel.setAccessibilityIdentifier("docknet.primary.interface")
            ifaceLabel.setAccessibilityLabel(ifaceDetail)
            ifaceLabel.setAccessibilityValue(ifaceDetail)
            ifaceLabel.setAccessibilityTitle(ifaceDetail)
            primaryCardsContainer.addArrangedSubview(ifaceLabel)

            let wifiHealth = NSTextField(labelWithString: "Connected · Primary")
            wifiHealth.setAccessibilityIdentifier("docknet.wifi.health")
            wifiHealth.setAccessibilityLabel("Connected · Primary")
            wifiHealth.setAccessibilityValue("Primary")
            wifiHealth.setAccessibilityTitle("Primary")
            primaryCardsContainer.addArrangedSubview(wifiHealth)
        } else {
            let typeLabel = NSTextField(labelWithString: snapshot.isWifiPrimary ? "Wi-Fi" : (snapshot.actualPrimaryIsWired ? "Ethernet" : "Wi-Fi"))
            typeLabel.setAccessibilityIdentifier("docknet.primary.type")
            typeLabel.setAccessibilityLabel("Wi-Fi")
            typeLabel.setAccessibilityValue("Wi-Fi")
            typeLabel.setAccessibilityTitle("Wi-Fi")
            primaryCardsContainer.addArrangedSubview(typeLabel)

            let ifaceLabel = NSTextField(labelWithString: "Offline")
            ifaceLabel.setAccessibilityIdentifier("docknet.primary.interface")
            primaryCardsContainer.addArrangedSubview(ifaceLabel)
        }

        // Other connections:
        let otherWired = snapshot.actualPrimaryIsWired
            ? snapshot.wiredInterfaces.filter { !$0.isPrimary }
            : snapshot.wiredInterfaces

        for iface in otherWired {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 6

            let nameLabel = NSTextField(labelWithString: iface.serviceName)
            nameLabel.setAccessibilityIdentifier("docknet.wired.\(iface.bsdName).name")
            nameLabel.setAccessibilityLabel(iface.serviceName)
            row.addArrangedSubview(nameLabel)

            let healthLabel = NSTextField(labelWithString: iface.statusSummary)
            healthLabel.setAccessibilityIdentifier("docknet.wired.\(iface.bsdName).health")
            healthLabel.setAccessibilityLabel(iface.statusSummary)
            healthLabel.setAccessibilityValue(iface.statusSummary)
            row.addArrangedSubview(healthLabel)

            if iface.isPrimary {
                let pBadge = NSTextField(labelWithString: "Primary")
                pBadge.setAccessibilityIdentifier("docknet.wired.\(iface.bsdName).primary")
                pBadge.setAccessibilityLabel("Primary")
                row.addArrangedSubview(pBadge)
            }

            if let speed = iface.linkSpeed {
                let speedLabel = NSTextField(labelWithString: speed)
                speedLabel.setAccessibilityIdentifier("docknet.wired.\(iface.bsdName).speed")
                speedLabel.setAccessibilityLabel(speed)
                row.addArrangedSubview(speedLabel)
            }

            otherConnectionsContainer.addArrangedSubview(row)
        }

        if snapshot.actualPrimaryIsWired {
            let wifiRow = NSStackView()
            wifiRow.orientation = .horizontal
            wifiRow.spacing = 6

            let wifiName = NSTextField(labelWithString: "Wi-Fi")
            wifiRow.addArrangedSubview(wifiName)

            let wifiHealth = NSTextField(labelWithString: snapshot.wifiStatusText)
            wifiHealth.setAccessibilityIdentifier("docknet.wifi.health")
            wifiHealth.setAccessibilityLabel(snapshot.wifiStatusText)
            wifiHealth.setAccessibilityValue(snapshot.wifiStatusText)
            wifiRow.addArrangedSubview(wifiHealth)

            otherConnectionsContainer.addArrangedSubview(wifiRow)
        }

        notificationsCheckbox.state = notificationManager.isPreferenceEnabled ? .on : .off
        loginItemManager.refreshStatus()
        launchAtLoginCheckbox.state = loginItemManager.isLaunchAtLoginEnabled ? .on : .off
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 312)
        ])
        return box
    }

    @objc private func toggleNotifications() {
        let current = notificationManager.isPreferenceEnabled
        Task { @MainActor in
            _ = await notificationManager.setPreferenceEnabled(!current)
            notificationsCheckbox.state = notificationManager.isPreferenceEnabled ? .on : .off
        }
    }

    @objc private func toggleLogin() {
        loginItemManager.toggleLaunchAtLogin()
        loginItemManager.refreshStatus()
        launchAtLoginCheckbox.state = loginItemManager.isLaunchAtLoginEnabled ? .on : .off
    }

    @objc private func handleRefresh() {
        networkMonitor.refresh()
    }

    @objc private func handleSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")
            ?? URL(string: "x-apple.systempreferences:")!
        WorkspaceURLOpener().open(url)
    }

    @objc private func handleAbout() {
        AboutWindowController.shared.showAboutWindow()
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}
