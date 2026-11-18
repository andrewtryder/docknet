import AppKit

extension DetailedStatusViewController {
    private func statusTone(for health: EthernetHealthState) -> StatusIndicatorView.Tone {
        switch health {
        case .ready: return .green
        case .linkUp, .obtainingDHCP, .configured: return .orange
        case .degraded: return .red
        default: return .gray
        }
    }

    private func makeTopStatusRow(
        tone: StatusIndicatorView.Tone,
        nameLabel: NSTextField,
        trailingView: NSView
    ) -> NSStackView {
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.addArrangedSubview(StatusIndicatorView(tone: tone))
        topRow.addArrangedSubview(nameLabel)
        trailingView.setContentCompressionResistancePriority(.required, for: .horizontal)
        topRow.addArrangedSubview(trailingView)
        return topRow
    }

    private func makeTruncatingLabel(
        _ text: String,
        font: NSFont,
        color: NSColor = .labelColor,
        toolTip: String? = nil
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.usesSingleLineMode = true
        label.cell?.truncatesLastVisibleLine = true
        if let tip = toolTip {
            label.toolTip = tip
        }
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func renderPrimaryWired(_ active: WiredInterfaceState) {
        let nameLabel = makeTruncatingLabel(
            active.serviceName,
            font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            toolTip: active.serviceName
        )
        let badge = makeBadge(title: "Primary", tone: .green)
        badge.setAccessibilityIdentifier("docknet.wired.\(active.bsdName).primary")

        let topRow = makeTopStatusRow(tone: statusTone(for: active.health), nameLabel: nameLabel, trailingView: badge)
        primaryContainer.addArrangedSubview(topRow)
        topRow.widthAnchor.constraint(lessThanOrEqualTo: primaryContainer.widthAnchor).isActive = true

        let typeLabel = NSTextField(labelWithString: "Ethernet")
        typeLabel.setAccessibilityIdentifier("docknet.primary.type")
        typeLabel.isHidden = true
        primaryContainer.addArrangedSubview(typeLabel)

        let ifaceText = "Ethernet · \(active.bsdName)"
        let ifaceLabel = makeTruncatingLabel(
            ifaceText,
            font: NSFont.systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        ifaceLabel.setAccessibilityIdentifier("docknet.primary.interface")
        ifaceLabel.setAccessibilityLabel(ifaceText)
        primaryContainer.addArrangedSubview(ifaceLabel)

        let ipLabel = makeTruncatingLabel(
            active.ipv4Address ?? "No IP",
            font: NSFont.systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        primaryContainer.addArrangedSubview(ipLabel)

        if let speed = active.linkSpeed {
            let speedLabel = makeTruncatingLabel(
                speed,
                font: NSFont.systemFont(ofSize: 12),
                color: .secondaryLabelColor
            )
            speedLabel.setAccessibilityIdentifier("docknet.wired.\(active.bsdName).speed")
            primaryContainer.addArrangedSubview(speedLabel)
        }
    }

    func renderPrimaryWifi(_ snapshot: NetworkSnapshot) {
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let dot = StatusIndicatorView(tone: .green)
        topRow.addArrangedSubview(dot)

        let nameLabel = makeTruncatingLabel(
            "Wi-Fi",
            font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        )
        topRow.addArrangedSubview(nameLabel)

        let badge = makeBadge(title: "Primary", tone: .green)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        topRow.addArrangedSubview(badge)

        primaryContainer.addArrangedSubview(topRow)
        topRow.widthAnchor.constraint(lessThanOrEqualTo: primaryContainer.widthAnchor).isActive = true

        let typeLabel = NSTextField(labelWithString: "Wi-Fi")
        typeLabel.setAccessibilityIdentifier("docknet.primary.type")
        typeLabel.isHidden = true
        primaryContainer.addArrangedSubview(typeLabel)

        let ifaceText = "\(snapshot.wifi.bsdName) · \(snapshot.wifi.primaryIPv4Address ?? "No IP")"
        let ifaceLabel = makeTruncatingLabel(
            ifaceText,
            font: NSFont.systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
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

        let name = makeTruncatingLabel(
            iface.serviceName,
            font: NSFont.systemFont(ofSize: 12, weight: .medium),
            toolTip: iface.serviceName
        )
        name.setAccessibilityIdentifier("docknet.wired.\(iface.bsdName).name")

        let bsdLabel = NSTextField(labelWithString: iface.bsdName)
        bsdLabel.font = NSFont.systemFont(ofSize: 11)
        bsdLabel.textColor = .secondaryLabelColor

        let topRow = makeTopStatusRow(tone: statusTone(for: iface.health), nameLabel: name, trailingView: bsdLabel)
        row.addArrangedSubview(topRow)
        topRow.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor).isActive = true

        var detailParts: [String] = []
        if let ipAddress = iface.ipv4Address {
            detailParts.append(ipAddress)
        }
        detailParts.append(iface.statusSummary)
        if let speed = iface.linkSpeed {
            detailParts.append(speed)
        }

        let detailText = "     " + detailParts.joined(separator: " · ")
        let detailLabel = makeTruncatingLabel(
            detailText,
            font: NSFont.systemFont(ofSize: 11),
            color: .secondaryLabelColor,
            toolTip: detailParts.joined(separator: " · ")
        )
        detailLabel.setAccessibilityIdentifier("docknet.wired.\(iface.bsdName).health")
        row.addArrangedSubview(detailLabel)

        otherContainer.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: otherContainer.widthAnchor).isActive = true
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
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let dot = StatusIndicatorView(tone: .gray)
        topRow.addArrangedSubview(dot)

        let name = makeTruncatingLabel(
            "Wi-Fi",
            font: NSFont.systemFont(ofSize: 12, weight: .medium)
        )
        topRow.addArrangedSubview(name)

        let bsdLabel = NSTextField(labelWithString: snapshot.wifi.bsdName)
        bsdLabel.font = NSFont.systemFont(ofSize: 11)
        bsdLabel.textColor = .secondaryLabelColor
        bsdLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        topRow.addArrangedSubview(bsdLabel)

        row.addArrangedSubview(topRow)
        topRow.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor).isActive = true

        var detailParts: [String] = []
        if let ip = snapshot.wifi.primaryIPv4Address {
            detailParts.append(ip)
        }
        detailParts.append("Standby")

        let detailText = "     " + detailParts.joined(separator: " · ")
        let detailLabel = makeTruncatingLabel(
            detailText,
            font: NSFont.systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )
        detailLabel.setAccessibilityIdentifier("docknet.wifi.health")
        row.addArrangedSubview(detailLabel)

        otherContainer.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: otherContainer.widthAnchor).isActive = true
    }
}
