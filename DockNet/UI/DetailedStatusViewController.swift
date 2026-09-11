import AppKit

/// Native AppKit view controller displaying DockNet's Detailed presentation style.
/// Contains rich visual hierarchy, connection cards, preferences, and utility actions.
/// Designed for zero idle cost when closed.
@MainActor
public final class DetailedStatusViewController: NSViewController {

    // Dependencies
    private let networkMonitor: any NetworkMonitoringProtocol
    private let notificationManager: NotificationManager
    private let loginItemManager: LoginItemManager
    private let presentationPreferences: PresentationPreferences
    private let onStyleChanged: (PresentationStyle) -> Void

    // UI Elements
    private var headerIconView: NSImageView!
    private var primaryContainer: NSStackView!
    private var otherContainer: NSStackView!
    private var notifyCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var styleSegmentedControl: NSSegmentedControl!

    public init(
        networkMonitor: any NetworkMonitoringProtocol,
        notificationManager: NotificationManager,
        loginItemManager: LoginItemManager,
        presentationPreferences: PresentationPreferences,
        onStyleChanged: @escaping (PresentationStyle) -> Void
    ) {
        self.networkMonitor = networkMonitor
        self.notificationManager = notificationManager
        self.loginItemManager = loginItemManager
        self.presentationPreferences = presentationPreferences
        self.onStyleChanged = onStyleChanged
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 480))
        root.setAccessibilityElement(true)
        root.setAccessibilityIdentifier("docknet.detailed")
        root.setAccessibilityLabel("DockNet Detailed View")
        self.view = root

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -14)
        ])

        // 1. Header (Icon + App Name)
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.alignment = .centerY

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20)
        ])
        iconView.setAccessibilityElement(true)
        iconView.setAccessibilityIdentifier("docknet.status.icon")
        self.headerIconView = iconView
        headerStack.addArrangedSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "DockNet")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.setAccessibilityIdentifier("docknet.header.title")
        headerStack.addArrangedSubview(titleLabel)

        mainStack.addArrangedSubview(headerStack)
        mainStack.addArrangedSubview(makeSeparator())

        // 2. PRIMARY CONNECTION Section
        let primaryHeading = NSTextField(labelWithString: "PRIMARY CONNECTION")
        primaryHeading.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        primaryHeading.textColor = .secondaryLabelColor
        mainStack.addArrangedSubview(primaryHeading)

        let primaryCard = NSStackView()
        primaryCard.orientation = .vertical
        primaryCard.alignment = .leading
        primaryCard.spacing = 3
        primaryCard.translatesAutoresizingMaskIntoConstraints = false
        primaryCard.setAccessibilityElement(true)
        primaryCard.setAccessibilityIdentifier("docknet.detailed.primary")
        self.primaryContainer = primaryCard
        mainStack.addArrangedSubview(primaryCard)

        mainStack.addArrangedSubview(makeSeparator())

        // 3. OTHER CONNECTIONS Section
        let otherHeading = NSTextField(labelWithString: "OTHER CONNECTIONS")
        otherHeading.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        otherHeading.textColor = .secondaryLabelColor
        mainStack.addArrangedSubview(otherHeading)

        let otherCard = NSStackView()
        otherCard.orientation = .vertical
        otherCard.alignment = .leading
        otherCard.spacing = 6
        otherCard.translatesAutoresizingMaskIntoConstraints = false
        otherCard.setAccessibilityElement(true)
        otherCard.setAccessibilityIdentifier("docknet.detailed.otherConnections")
        self.otherContainer = otherCard
        mainStack.addArrangedSubview(otherCard)

        mainStack.addArrangedSubview(makeSeparator())

        // 4. Preferences Section
        let notifyBtn = NSButton(
            checkboxWithTitle: "Notify on connection changes",
            target: self,
            action: #selector(toggleNotificationsAction)
        )
        notifyBtn.setAccessibilityIdentifier("docknet.notifications")
        notifyBtn.font = NSFont.systemFont(ofSize: 12)
        self.notifyCheckbox = notifyBtn
        mainStack.addArrangedSubview(notifyBtn)

        let loginBtn = NSButton(
            checkboxWithTitle: "Launch at Login",
            target: self,
            action: #selector(toggleLaunchAtLoginAction)
        )
        loginBtn.setAccessibilityIdentifier("docknet.launchAtLogin")
        loginBtn.font = NSFont.systemFont(ofSize: 12)
        self.launchAtLoginCheckbox = loginBtn
        mainStack.addArrangedSubview(loginBtn)

        // Display Style Selector Row
        let styleRow = NSStackView()
        styleRow.orientation = .horizontal
        styleRow.spacing = 8
        styleRow.alignment = .centerY
        styleRow.translatesAutoresizingMaskIntoConstraints = false

        let styleLabel = NSTextField(labelWithString: "Display Style")
        styleLabel.font = NSFont.systemFont(ofSize: 12)
        styleLabel.textColor = .labelColor
        styleRow.addArrangedSubview(styleLabel)

        let segmented = NSSegmentedControl(
            labels: ["Compact", "Detailed"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(styleSegmentedChanged(_:))
        )
        segmented.selectedSegment = (presentationPreferences.style == .compact) ? 0 : 1
        segmented.setAccessibilityIdentifier("docknet.presentation.segmented")
        self.styleSegmentedControl = segmented
        styleRow.addArrangedSubview(segmented)

        mainStack.addArrangedSubview(styleRow)
        mainStack.addArrangedSubview(makeSeparator())

        // 5. Utility Actions Section
        let actionsStack = NSStackView()
        actionsStack.orientation = .vertical
        actionsStack.alignment = .leading
        actionsStack.spacing = 4

        actionsStack.addArrangedSubview(makeActionButton(
            title: "Refresh",
            action: #selector(refreshAction),
            identifier: "docknet.refresh"
        ))
        actionsStack.addArrangedSubview(makeActionButton(
            title: "Open Network Settings…",
            action: #selector(openNetworkSettingsAction),
            identifier: "docknet.openSettings"
        ))
        actionsStack.addArrangedSubview(makeActionButton(
            title: "About DockNet…",
            action: #selector(openAboutAction),
            identifier: "docknet.about"
        ))
        actionsStack.addArrangedSubview(makeActionButton(
            title: "Quit DockNet",
            action: #selector(quitAction),
            identifier: "docknet.quit"
        ))

        mainStack.addArrangedSubview(actionsStack)

        // Initial snapshot populate
        update(with: networkMonitor.currentSnapshot)
    }

    // MARK: - Snapshot Population

    public func update(with snapshot: NetworkSnapshot) {
        guard isViewLoaded else { return }

        // Update header icon
        let state = StatusIconState.from(snapshot: snapshot)
        headerIconView.image = StatusIconRenderer.image(for: state)
        headerIconView.setAccessibilityLabel(state.accessibilityLabel)

        // Update Primary Connection Card
        primaryContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if snapshot.actualPrimaryIsWired, let active = snapshot.activePrimaryWiredInterface {
            renderPrimaryWired(active)
        } else if snapshot.isWifiPrimary {
            renderPrimaryWifi(snapshot)
        } else {
            renderPrimaryOffline()
        }

        // Update Other Connections
        otherContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let otherWired = snapshot.actualPrimaryIsWired
            ? snapshot.wiredInterfaces.filter { !$0.isPrimary }
            : snapshot.wiredInterfaces
        let showWifiStandby = snapshot.actualPrimaryIsWired

        if otherWired.isEmpty && !showWifiStandby {
            let emptyLabel = NSTextField(labelWithString: "No other connections")
            emptyLabel.font = NSFont.systemFont(ofSize: 12)
            emptyLabel.textColor = .secondaryLabelColor
            otherContainer.addArrangedSubview(emptyLabel)
        } else {
            for iface in otherWired {
                renderOtherWired(iface)
            }
            if showWifiStandby {
                renderOtherWifiStandby(snapshot)
            }
        }

        // Update Preferences
        notifyCheckbox.state = notificationManager.isPreferenceEnabled ? .on : .off
        loginItemManager.refreshStatus()
        launchAtLoginCheckbox.state = loginItemManager.isLaunchAtLoginEnabled ? .on : .off
        styleSegmentedControl.selectedSegment = (presentationPreferences.style == .compact) ? 0 : 1
    }

    // MARK: - View Rendering Helpers

    private func renderPrimaryWired(_ active: WiredInterfaceState) {
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY

        let tone: StatusIndicatorView.Tone
        switch active.health {
        case .ready: tone = .green
        case .linkUp, .obtainingDHCP: tone = .orange
        case .degraded: tone = .red
        default: tone = .gray
        }

        let dot = StatusIndicatorView(tone: tone)
        topRow.addArrangedSubview(dot)

        let nameLabel = NSTextField(labelWithString: active.serviceName)
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        topRow.addArrangedSubview(nameLabel)

        let badge = makeBadge(title: "Primary", tone: .green)
        badge.setAccessibilityIdentifier("docknet.wired.\(active.bsdName).primary")
        topRow.addArrangedSubview(badge)

        primaryContainer.addArrangedSubview(topRow)

        let typeLabel = NSTextField(labelWithString: "Ethernet")
        typeLabel.setAccessibilityIdentifier("docknet.primary.type")
        typeLabel.isHidden = true
        primaryContainer.addArrangedSubview(typeLabel)

        let ifaceText = "Ethernet · \(active.bsdName)"
        let ifaceLabel = NSTextField(labelWithString: ifaceText)
        ifaceLabel.font = NSFont.systemFont(ofSize: 12)
        ifaceLabel.textColor = .secondaryLabelColor
        ifaceLabel.setAccessibilityIdentifier("docknet.primary.interface")
        ifaceLabel.setAccessibilityLabel(ifaceText)
        primaryContainer.addArrangedSubview(ifaceLabel)

        let ipText = active.ipv4Address ?? "No IP"
        let ipLabel = NSTextField(labelWithString: ipText)
        ipLabel.font = NSFont.systemFont(ofSize: 12)
        ipLabel.textColor = .secondaryLabelColor
        primaryContainer.addArrangedSubview(ipLabel)

        if let speed = active.linkSpeed {
            let speedLabel = NSTextField(labelWithString: speed)
            speedLabel.font = NSFont.systemFont(ofSize: 12)
            speedLabel.textColor = .secondaryLabelColor
            speedLabel.setAccessibilityIdentifier("docknet.wired.\(active.bsdName).speed")
            primaryContainer.addArrangedSubview(speedLabel)
        }
    }

    private func renderPrimaryWifi(_ snapshot: NetworkSnapshot) {
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY

        let dot = StatusIndicatorView(tone: .green)
        topRow.addArrangedSubview(dot)

        let nameLabel = NSTextField(labelWithString: "Wi-Fi")
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        topRow.addArrangedSubview(nameLabel)

        let badge = makeBadge(title: "Primary", tone: .green)
        topRow.addArrangedSubview(badge)

        primaryContainer.addArrangedSubview(topRow)

        let typeLabel = NSTextField(labelWithString: "Wi-Fi")
        typeLabel.setAccessibilityIdentifier("docknet.primary.type")
        typeLabel.isHidden = true
        primaryContainer.addArrangedSubview(typeLabel)

        let ifaceText = "\(snapshot.wifi.bsdName) · \(snapshot.wifi.primaryIPv4Address ?? "No IP")"
        let ifaceLabel = NSTextField(labelWithString: ifaceText)
        ifaceLabel.font = NSFont.systemFont(ofSize: 12)
        ifaceLabel.textColor = .secondaryLabelColor
        ifaceLabel.setAccessibilityIdentifier("docknet.primary.interface")
        ifaceLabel.setAccessibilityLabel(ifaceText)
        primaryContainer.addArrangedSubview(ifaceLabel)

        let healthLabel = NSTextField(labelWithString: "Connected · Primary")
        healthLabel.font = NSFont.systemFont(ofSize: 12)
        healthLabel.textColor = .secondaryLabelColor
        healthLabel.setAccessibilityIdentifier("docknet.wifi.health")
        primaryContainer.addArrangedSubview(healthLabel)
    }

    private func renderPrimaryOffline() {
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY

        let dot = StatusIndicatorView(tone: .gray)
        topRow.addArrangedSubview(dot)

        let nameLabel = NSTextField(labelWithString: "No Active Primary Connection")
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = .secondaryLabelColor
        topRow.addArrangedSubview(nameLabel)

        primaryContainer.addArrangedSubview(topRow)

        let typeLabel = NSTextField(labelWithString: "Offline")
        typeLabel.setAccessibilityIdentifier("docknet.primary.type")
        typeLabel.isHidden = true
        primaryContainer.addArrangedSubview(typeLabel)

        let ifaceLabel = NSTextField(labelWithString: "Offline")
        ifaceLabel.setAccessibilityIdentifier("docknet.primary.interface")
        ifaceLabel.isHidden = true
        primaryContainer.addArrangedSubview(ifaceLabel)
    }

    private func renderOtherWired(_ iface: WiredInterfaceState) {
        let row = NSStackView()
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 1
        row.translatesAutoresizingMaskIntoConstraints = false

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY

        let tone: StatusIndicatorView.Tone
        switch iface.health {
        case .ready: tone = .green
        case .linkUp, .obtainingDHCP: tone = .orange
        case .degraded: tone = .red
        default: tone = .gray
        }

        let dot = StatusIndicatorView(tone: tone)
        topRow.addArrangedSubview(dot)

        let name = NSTextField(labelWithString: iface.serviceName)
        name.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        name.setAccessibilityIdentifier("docknet.wired.\(iface.bsdName).name")
        topRow.addArrangedSubview(name)

        let bsdLabel = NSTextField(labelWithString: iface.bsdName)
        bsdLabel.font = NSFont.systemFont(ofSize: 11)
        bsdLabel.textColor = .secondaryLabelColor
        topRow.addArrangedSubview(bsdLabel)

        row.addArrangedSubview(topRow)

        var detailParts: [String] = []
        if let ip = iface.ipv4Address {
            detailParts.append(ip)
        }
        detailParts.append(iface.statusSummary)
        if let speed = iface.linkSpeed {
            detailParts.append(speed)
        }

        let detailText = "     " + detailParts.joined(separator: " · ")
        let detailLabel = NSTextField(labelWithString: detailText)
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.setAccessibilityIdentifier("docknet.wired.\(iface.bsdName).health")
        row.addArrangedSubview(detailLabel)

        otherContainer.addArrangedSubview(row)
    }

    private func renderOtherWifiStandby(_ snapshot: NetworkSnapshot) {
        let row = NSStackView()
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 1
        row.translatesAutoresizingMaskIntoConstraints = false

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY

        let dot = StatusIndicatorView(tone: .gray)
        topRow.addArrangedSubview(dot)

        let name = NSTextField(labelWithString: "Wi-Fi")
        name.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        topRow.addArrangedSubview(name)

        let bsdLabel = NSTextField(labelWithString: snapshot.wifi.bsdName)
        bsdLabel.font = NSFont.systemFont(ofSize: 11)
        bsdLabel.textColor = .secondaryLabelColor
        topRow.addArrangedSubview(bsdLabel)

        row.addArrangedSubview(topRow)

        var detailParts: [String] = []
        if let ip = snapshot.wifi.primaryIPv4Address {
            detailParts.append(ip)
        }
        detailParts.append("Standby")

        let detailText = "     " + detailParts.joined(separator: " · ")
        let detailLabel = NSTextField(labelWithString: detailText)
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.setAccessibilityIdentifier("docknet.wifi.health")
        row.addArrangedSubview(detailLabel)

        otherContainer.addArrangedSubview(row)
    }

    // MARK: - UI Construction Helpers

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 318)
        ])
        return box
    }

    private func makeBadge(title: String, tone: StatusIndicatorView.Tone) -> NSTextField {
        let label = NSTextField(labelWithString: " \(title) ")
        label.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        label.textColor = tone.color
        label.wantsLayer = true
        label.layer?.cornerRadius = 3
        label.layer?.borderWidth = 1
        label.layer?.borderColor = tone.color.withAlphaComponent(0.4).cgColor
        return label
    }

    private func makeActionButton(title: String, action: Selector, identifier: String) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = NSFont.systemFont(ofSize: 12)
        btn.contentTintColor = .linkColor
        btn.setAccessibilityIdentifier(identifier)
        return btn
    }

    // MARK: - Actions

    @objc private func toggleNotificationsAction() {
        let current = notificationManager.isPreferenceEnabled
        Task { @MainActor in
            _ = await notificationManager.setPreferenceEnabled(!current)
            notifyCheckbox.state = notificationManager.isPreferenceEnabled ? .on : .off
        }
    }

    @objc private func toggleLaunchAtLoginAction() {
        loginItemManager.toggleLaunchAtLogin()
        loginItemManager.refreshStatus()
        launchAtLoginCheckbox.state = loginItemManager.isLaunchAtLoginEnabled ? .on : .off
    }

    @objc private func styleSegmentedChanged(_ sender: NSSegmentedControl) {
        let newStyle: PresentationStyle = (sender.selectedSegment == 0) ? .compact : .detailed
        presentationPreferences.style = newStyle
        onStyleChanged(newStyle)
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
