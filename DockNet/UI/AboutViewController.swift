import AppKit

/// Compact, polished native AppKit About view controller for DockNet.
@MainActor
public final class AboutViewController: NSViewController {
    public let urlOpener: any URLOpening

    public init(urlOpener: any URLOpening = WorkspaceURLOpener()) {
        self.urlOpener = urlOpener
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 360))
        self.view = root

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24)
        ])

        // 1. App Icon
        let iconView = NSImageView()
        iconView.image = NSImage(named: "DockNetAboutIcon") ?? NSImage(named: NSImage.applicationIconName)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(true)
        iconView.setAccessibilityRole(.image)
        iconView.setAccessibilityIdentifier("docknet.about.icon")
        iconView.setAccessibilityLabel("DockNet Application Icon")
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64)
        ])
        stack.addArrangedSubview(iconView)

        // 2. Title
        let titleLabel = NSTextField(labelWithString: "DockNet")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.setAccessibilityIdentifier("docknet.about.name")
        titleLabel.setAccessibilityLabel("DockNet")
        stack.addArrangedSubview(titleLabel)

        // 3. Version
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
        let versionStr = "Version \(version) (\(build))"
        let versionLabel = NSTextField(labelWithString: versionStr)
        versionLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.setAccessibilityIdentifier("docknet.about.version")
        versionLabel.setAccessibilityLabel(versionStr)
        stack.addArrangedSubview(versionLabel)

        // 4. Description
        let descLabel = NSTextField(labelWithString: "Automatic Ethernet/Wi-Fi connection monitoring for macOS.")
        descLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(descLabel)

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalToConstant: 240)
        ])
        stack.addArrangedSubview(separator)

        // 5. Author Credit
        let authorLabel = NSTextField(labelWithString: "Andrew Ryder")
        authorLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        authorLabel.alignment = .center
        authorLabel.setAccessibilityIdentifier("docknet.about.author")
        authorLabel.setAccessibilityLabel("Andrew Ryder")
        stack.addArrangedSubview(authorLabel)

        // 6. GitHub Button
        let gitHubButton = NSButton(title: "View on GitHub", target: self, action: #selector(openGitHub))
        gitHubButton.bezelStyle = .rounded
        gitHubButton.setAccessibilityIdentifier("docknet.about.github")
        gitHubButton.setAccessibilityLabel("View DockNet on GitHub")
        stack.addArrangedSubview(gitHubButton)

        // 7. URL label
        let urlLabel = NSTextField(labelWithString: "github.com/andrewtryder/docknet")
        urlLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        urlLabel.textColor = .tertiaryLabelColor
        urlLabel.alignment = .center
        stack.addArrangedSubview(urlLabel)
    }

    @objc private func openGitHub() {
        let url = URL(string: "https://github.com/andrewtryder/docknet")!
        urlOpener.open(url)
    }
}
