import AppKit

extension DetailedStatusViewController {
    func renderPrimaryWired(_ active: WiredInterfaceState) {
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY

        let tone: StatusIndicatorView.Tone
        switch active.health {
        case .ready: tone = .green
        case .linkUp, .obtainingDHCP, .configured: tone = .orange
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

    func renderPrimaryWifi(_ snapshot: NetworkSnapshot) {
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

    func renderPrimaryOffline() {
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

    func renderOtherWired(_ iface: WiredInterfaceState) {
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
        case .linkUp, .obtainingDHCP, .configured: tone = .orange
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

    func renderOtherWifiStandby(_ snapshot: NetworkSnapshot) {
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
}
