import SwiftUI

public struct MenuBarView: View {
    @ObservedObject var viewModel: StatusViewModel

    public init(viewModel: StatusViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                DockNetStatusIcon(viewModel: viewModel)

                Text("DockNet")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("docknet.header.title")
                    .accessibilityLabel("DockNet Application")
                Spacer()
                overallStatusPill
            }

            Divider()
                .accessibilityHidden(true)

            // Primary Connection Section
            VStack(alignment: .leading, spacing: 4) {
                Text("Primary Connection")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .accessibilityLabel("Primary Connection Section")

                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.snapshot.actualPrimaryIsWired ? Color.green : (viewModel.snapshot.isWifiPrimary ? Color.blue : Color.gray))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)

                    Text(viewModel.activeConnectionTitle)
                        .font(.body)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("docknet.primary.type")
                        .accessibilityLabel(viewModel.activeConnectionTitle)
                        .accessibilityValue(viewModel.activeConnectionTitle)
                }

                Text(viewModel.activeConnectionSubtitle)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("docknet.primary.interface")
                    .accessibilityLabel(viewModel.activeConnectionSubtitle)
                    .accessibilityValue(viewModel.activeConnectionSubtitle)
            }

            Divider()
                .accessibilityHidden(true)

            // Wired Connections Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Wired Connections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .accessibilityLabel("Wired Connections Section")
                    Spacer()
                    Text("\(viewModel.wiredInterfaces.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("\(viewModel.wiredInterfaces.count) wired interfaces configured")
                }

                if viewModel.wiredInterfaces.isEmpty {
                    Text("No Ethernet interfaces configured")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 2)
                        .accessibilityIdentifier("docknet.wired.empty")
                        .accessibilityLabel("No Ethernet interfaces configured")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.wiredInterfaces) { iface in
                            wiredInterfaceRow(iface)
                        }
                    }
                }
            }

            Divider()
                .accessibilityHidden(true)

            // Wi-Fi Section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Wi-Fi")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .accessibilityLabel("Wi-Fi Section")
                    Spacer()
                    Text(viewModel.snapshot.wifi.bsdName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("docknet.wifi.interface")
                        .accessibilityLabel("Wi-Fi Interface \(viewModel.snapshot.wifi.bsdName)")
                }

                HStack {
                    Circle()
                        .fill(viewModel.snapshot.isWifiPrimary ? Color.blue : (viewModel.snapshot.wifi.isLinkActive ? Color.green : Color.gray))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)

                    if let ip = viewModel.snapshot.wifi.primaryIPv4Address {
                        Text(ip)
                            .font(.callout)
                            .accessibilityIdentifier("docknet.wifi.address")
                            .accessibilityLabel("Wi-Fi IP Address \(ip)")
                            .accessibilityValue(ip)
                    } else {
                        Text("No IP")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Wi-Fi has no IP address")
                    }
                    Spacer()
                    Text(viewModel.wifiStatusText)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(viewModel.snapshot.isWifiPrimary ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.12))
                        .foregroundColor(viewModel.snapshot.isWifiPrimary ? .blue : .secondary)
                        .cornerRadius(4)
                        .accessibilityIdentifier("docknet.wifi.health")
                        .accessibilityLabel("Wi-Fi Status \(viewModel.wifiStatusText)")
                        .accessibilityValue(viewModel.wifiStatusText)
                }
            }

            Divider()
                .accessibilityHidden(true)

            // Preferences & Toggles
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Automatic Monitoring", isOn: $viewModel.isAutomaticMonitoringEnabled)
                    .toggleStyle(.checkbox)
                    .font(.subheadline)
                    .accessibilityIdentifier("docknet.automaticMonitoring")
                    .accessibilityLabel("Automatic Monitoring Toggle")

                HStack {
                    Toggle(isOn: Binding(
                        get: { viewModel.isNotificationsEnabled },
                        set: { viewModel.setNotificationsEnabled($0) }
                    )) {
                        Text("Notify on connection changes")
                            .font(.subheadline)
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("docknet.notifications")
                    .accessibilityLabel("Notify on connection changes Toggle")

                    if viewModel.notificationAuthStatus == .denied {
                        Spacer()
                        Button(action: {
                            viewModel.openNotificationSettings()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("Disabled by macOS")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("docknet.notifications.denied")
                        .accessibilityLabel("Notifications disabled by macOS. Click to open Settings.")
                    }
                }

                Toggle(isOn: Binding(
                    get: { viewModel.loginItemManager.isLaunchAtLoginEnabled },
                    set: { viewModel.loginItemManager.setLaunchAtLogin(enabled: $0) }
                )) {
                    Text("Launch at Login")
                        .font(.subheadline)
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("docknet.launchAtLogin")
                .accessibilityLabel("Launch at Login Toggle")
            }

            Divider()
                .accessibilityHidden(true)

            // Actions
            VStack(alignment: .leading, spacing: 6) {
                Button("Refresh") {
                    viewModel.refresh()
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .accessibilityIdentifier("docknet.refresh")
                .accessibilityLabel("Refresh Network State")

                Button("Open Network Settings…") {
                    viewModel.openNetworkSettings()
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .accessibilityIdentifier("docknet.openSettings")
                .accessibilityLabel("Open macOS Network Settings")

                Button("About DockNet…") {
                    viewModel.openAboutWindow()
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .accessibilityIdentifier("docknet.about")
                .accessibilityLabel("About DockNet")

                Button("Quit DockNet") {
                    viewModel.quit()
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundColor(.red)
                .accessibilityIdentifier("docknet.quit")
                .accessibilityLabel("Quit DockNet")
            }
        }
        .padding(14)
        .frame(width: 310)
    }

    // MARK: - Subviews

    private func wiredInterfaceRow(_ iface: WiredInterfaceState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor(for: iface.health))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(iface.serviceName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("docknet.wired.\(iface.bsdName).name")
                    .accessibilityLabel(iface.serviceName)
                    .accessibilityValue(iface.serviceName)

                Spacer()

                if iface.isPrimary {
                    Text("Primary")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(3)
                        .accessibilityIdentifier("docknet.wired.\(iface.bsdName).primary")
                        .accessibilityLabel("Primary Wired Interface")
                        .accessibilityValue("Primary")
                } else if iface.isPreferred {
                    Text("Preferred")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(3)
                        .accessibilityIdentifier("docknet.wired.\(iface.bsdName).preferred")
                        .accessibilityLabel("Preferred Wired Interface")
                        .accessibilityValue("Preferred")
                }

                Text(iface.bsdName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("BSD Interface \(iface.bsdName)")
            }

            HStack {
                Text(iface.statusSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("docknet.wired.\(iface.bsdName).health")
                    .accessibilityLabel(iface.statusSummary)
                    .accessibilityValue(iface.statusSummary)

                Spacer()

                if let ip = iface.ipv4Address {
                    Text(ip)
                        .font(.caption)
                        .fontWeight(.medium)
                        .accessibilityIdentifier("docknet.wired.\(iface.bsdName).address")
                        .accessibilityLabel("IP Address \(ip)")
                        .accessibilityValue(ip)
                }
            }

            if let speed = iface.linkSpeed {
                HStack {
                    Text(speed)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("docknet.wired.\(iface.bsdName).speed")
                        .accessibilityLabel("Link Speed \(speed)")
                        .accessibilityValue(speed)
                    Spacer()
                }
            }
        }
        .padding(6)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(6)
    }

    private var overallStatusPill: some View {
        let isWired = viewModel.snapshot.actualPrimaryIsWired
        let preferred = viewModel.preferredWiredInterface
        let statusTitle = isWired ? (preferred?.serviceName ?? "Ethernet") : (viewModel.snapshot.isWifiPrimary ? "Wi-Fi" : "Offline")

        return HStack(spacing: 4) {
            Circle()
                .fill(isWired ? Color.green : (viewModel.snapshot.isWifiPrimary ? Color.blue : Color.gray))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(statusTitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .accessibilityLabel("Overall Status \(statusTitle)")
        }
        .accessibilityIdentifier("docknet.header.pill")
    }

    private func statusColor(for health: EthernetHealthState) -> Color {
        switch health {
        case .ready:
            return .green
        case .obtainingDHCP, .linkUp:
            return .orange
        case .degraded:
            return .red
        case .cableDisconnected, .disconnected, .adapterNotPresent, .disabled:
            return .gray
        }
    }
}
