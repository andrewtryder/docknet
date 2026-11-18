import AppKit

private final class FlippedContentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

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
    private let headerIconView = NSImageView()
    let primaryContainer = NSStackView()
    let otherContainer = NSStackView()
    private let notifyCheckbox: NSButton
    private let launchAtLoginCheckbox: NSButton
    private let styleSegmentedControl: NSSegmentedControl

    // Render deduplication state
    private var lastRenderedSnapshot: NetworkSnapshot?
    private var lastRenderedIconState: StatusIconState?

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
        notifyCheckbox = NSButton(checkboxWithTitle: "Notify on connection changes", target: nil, action: nil)
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
        styleSegmentedControl = NSSegmentedControl(
            labels: ["Compact", "Detailed"],
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 480))
        root.setAccessibilityElement(true)
        root.setAccessibilityIdentifier("docknet.detailed")
        root.setAccessibilityLabel("DockNet Detailed View")
        view = root

        let mainStack = makeScrolledMainStack(in: root)
        addHeaderSection(to: mainStack)
        addConnectionSections(to: mainStack)
        addPreferencesAndActions(to: mainStack)

        // Initial snapshot populate
        update(with: networkMonitor.currentSnapshot)
    }

    private func makeScrolledMainStack(in root: NSView) -> NSStackView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        let documentView = FlippedContentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            mainStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 14),
            mainStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -14),
        ])
        return mainStack
    }

    private func addHeaderSection(to mainStack: NSStackView) {
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.alignment = .centerY

        headerIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerIconView.widthAnchor.constraint(equalToConstant: 20),
            headerIconView.heightAnchor.constraint(equalToConstant: 20),
        ])
        headerIconView.setAccessibilityElement(true)
        headerIconView.setAccessibilityIdentifier("docknet.status.icon")
        headerStack.addArrangedSubview(headerIconView)

        let titleLabel = NSTextField(labelWithString: "DockNet")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.setAccessibilityIdentifier("docknet.header.title")
        headerStack.addArrangedSubview(titleLabel)

        mainStack.addArrangedSubview(headerStack)
        addSeparator(to: mainStack)
    }

    private func addConnectionSections(to mainStack: NSStackView) {
        let primaryHeading = NSTextField(labelWithString: "PRIMARY CONNECTION")
        primaryHeading.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        primaryHeading.textColor = .secondaryLabelColor
        mainStack.addArrangedSubview(primaryHeading)

        primaryContainer.orientation = .vertical
        primaryContainer.alignment = .leading
        primaryContainer.spacing = 3
        primaryContainer.translatesAutoresizingMaskIntoConstraints = false
        primaryContainer.setAccessibilityElement(true)
        primaryContainer.setAccessibilityIdentifier("docknet.detailed.primary")
        primaryContainer.setAccessibilityLabel("Primary Connection")
        mainStack.addArrangedSubview(primaryContainer)
        primaryContainer.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        addSeparator(to: mainStack)

        let otherHeading = NSTextField(labelWithString: "OTHER CONNECTIONS")
        otherHeading.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        otherHeading.textColor = .secondaryLabelColor
        mainStack.addArrangedSubview(otherHeading)

        otherContainer.orientation = .vertical
        otherContainer.alignment = .leading
        otherContainer.spacing = 6
        otherContainer.translatesAutoresizingMaskIntoConstraints = false
        otherContainer.setAccessibilityElement(true)
        otherContainer.setAccessibilityIdentifier("docknet.detailed.otherConnections")
        otherContainer.setAccessibilityLabel("Other Connections")
        mainStack.addArrangedSubview(otherContainer)
        otherContainer.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        addSeparator(to: mainStack)
    }

    private func addPreferencesAndActions(to mainStack: NSStackView) {
        // 4. Preferences Section
        notifyCheckbox.target = self
        notifyCheckbox.action = #selector(toggleNotificationsAction)
        notifyCheckbox.setAccessibilityIdentifier("docknet.notifications")
        notifyCheckbox.font = NSFont.systemFont(ofSize: 12)
        mainStack.addArrangedSubview(notifyCheckbox)

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLoginAction)
        launchAtLoginCheckbox.setAccessibilityIdentifier("docknet.launchAtLogin")
        launchAtLoginCheckbox.font = NSFont.systemFont(ofSize: 12)
        mainStack.addArrangedSubview(launchAtLoginCheckbox)

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

        styleSegmentedControl.target = self
        styleSegmentedControl.action = #selector(styleSegmentedChanged(_:))
        styleSegmentedControl.selectedSegment = (presentationPreferences.style == .compact) ? 0 : 1
        styleSegmentedControl.setAccessibilityIdentifier("docknet.presentation.segmented")
        styleSegmentedControl.setAccessibilityLabel("Display Style")
        styleRow.addArrangedSubview(styleSegmentedControl)

        mainStack.addArrangedSubview(styleRow)
        addSeparator(to: mainStack)

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
    }

    // MARK: - Snapshot Population

    public func update(with snapshot: NetworkSnapshot) {
        guard isViewLoaded else { return }

        // Update header icon only when icon state changes
        let state = StatusIconState.from(snapshot: snapshot)
        if state != lastRenderedIconState {
            lastRenderedIconState = state
            headerIconView.image = StatusIconRenderer.image(for: state)
            headerIconView.setAccessibilityLabel(state.accessibilityLabel)
        }

        // Rebuild connection cards only when meaningful network content changes
        let needsConnectionRebuild: Bool
        if let last = lastRenderedSnapshot {
            needsConnectionRebuild = !last.isSemanticallyEqualTo(snapshot)
        } else {
            needsConnectionRebuild = true
        }

        if needsConnectionRebuild {
            lastRenderedSnapshot = snapshot
            rebuildConnectionSections(for: snapshot)
        }

        // Update Preferences
        notifyCheckbox.state = notificationManager.isPreferenceEnabled ? .on : .off
        launchAtLoginCheckbox.state = loginItemManager.isLaunchAtLoginEnabled ? .on : .off
        styleSegmentedControl.selectedSegment = (presentationPreferences.style == .compact) ? 0 : 1
    }

    private func rebuildConnectionSections(for snapshot: NetworkSnapshot) {
        primaryContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if snapshot.actualPrimaryIsWired, let active = snapshot.activePrimaryWiredInterface {
            renderPrimaryWired(active)
        } else if snapshot.isWifiPrimary {
            renderPrimaryWifi(snapshot)
        } else {
            renderPrimaryOffline()
        }

        otherContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let otherWired = snapshot.actualPrimaryIsWired
            ? snapshot.wiredInterfaces.filter { !$0.isPrimary }
            : snapshot.wiredInterfaces
        let showWifiStandby = snapshot.actualPrimaryIsWired

        if otherWired.isEmpty, !showWifiStandby {
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
    }

    // MARK: - UI Construction Helpers

    private func addSeparator(to mainStack: NSStackView) {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
    }

    func makeBadge(title: String, tone: StatusIndicatorView.Tone) -> NSTextField {
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
        onStyleChanged(newStyle)
    }

    @objc private func refreshAction() {
        networkMonitor.refresh()
    }

    @objc private func openNetworkSettingsAction() {
        WorkspaceURLOpener().openNetworkSettings()
    }

    @objc private func openAboutAction() {
        AboutWindowController.shared.showAboutWindow()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
