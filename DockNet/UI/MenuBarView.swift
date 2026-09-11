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
            }

            Divider()
                .accessibilityHidden(true)

            // Primary Connection Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Primary Connection")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .accessibilityLabel("Primary Connection Section")

                primaryConnectionCard
            }

            Divider()
                .accessibilityHidden(true)

            // Other Connections Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Other Connections")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .accessibilityLabel("Other Connections Section")

                otherConnectionsList
            }

            Divider()
                .accessibilityHidden(true)

            // Preferences & Toggles
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
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
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Disabled by macOS ·")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Open Settings…") {
                                viewModel.openNotificationSettings()
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        }
                        .padding(.leading, 18)
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
        .frame(width: 340)
    }

    // MARK: - Primary Connection Card

    @ViewBuilder
    private var primaryConnectionCard: some View {
        if viewModel.snapshot.actualPrimaryIsWired, let active = viewModel.snapshot.activePrimaryWiredInterface {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)

                    Text(active.serviceName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    Text("Primary")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(3)
                        .accessibilityIdentifier("docknet.wired.\(active.bsdName).primary")
                        .accessibilityLabel("Primary Wired Interface")
                        .accessibilityValue("Primary")
                }

                HStack(spacing: 4) {
                    Text("Ethernet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("docknet.primary.type")
                        .accessibilityLabel("Ethernet")
                        .accessibilityValue("Ethernet")

                    Text("·")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(active.bsdName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("\(active.bsdName) · \(active.ipv4Address ?? "No IP")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("docknet.primary.interface")
                    .accessibilityLabel("\(active.bsdName) · \(active.ipv4Address ?? "No IP")")
                    .accessibilityValue("\(active.bsdName) · \(active.ipv4Address ?? "No IP")")

                if let speed = active.linkSpeed {
                    Text(speed)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("docknet.wired.\(active.bsdName).speed")
                        .accessibilityLabel("Link Speed \(speed)")
                        .accessibilityValue(speed)
                }

                // Hidden semantic label for tests checking statusSummary
                Text(active.statusSummary)
                    .accessibilityIdentifier("docknet.wired.\(active.bsdName).health")
                    .accessibilityLabel(active.statusSummary)
                    .accessibilityValue(active.statusSummary)
                    .frame(width: 0, height: 0)
                    .clipped()
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(6)

        } else if viewModel.snapshot.isWifiPrimary {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)

                    Text("Wi-Fi")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("docknet.primary.type")
                        .accessibilityLabel("Wi-Fi")
                        .accessibilityValue("Wi-Fi")

                    Spacer()

                    Text("Primary")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(3)
                        .accessibilityIdentifier("docknet.wifi.health")
                        .accessibilityLabel("Wi-Fi Status Primary")
                        .accessibilityValue("Primary")
                }

                Text("\(viewModel.snapshot.wifi.bsdName)\(viewModel.snapshot.wifi.primaryIPv4Address.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("docknet.primary.interface")
                    .accessibilityLabel("\(viewModel.snapshot.wifi.bsdName) · \(viewModel.snapshot.wifi.primaryIPv4Address ?? "No IP")")
                    .accessibilityValue("\(viewModel.snapshot.wifi.bsdName) · \(viewModel.snapshot.wifi.primaryIPv4Address ?? "No IP")")
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(6)

        } else {
            // Offline / degraded state
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.snapshot.wiredInterfaces.contains(where: { $0.health == .degraded }) ? Color.red : Color.gray)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)

                    Text(viewModel.activeConnectionTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("docknet.primary.type")
                        .accessibilityLabel(viewModel.activeConnectionTitle)
                        .accessibilityValue(viewModel.activeConnectionTitle)

                    Spacer()
                }

                Text(viewModel.activeConnectionSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("docknet.primary.interface")
                    .accessibilityLabel(viewModel.activeConnectionSubtitle)
                    .accessibilityValue(viewModel.activeConnectionSubtitle)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(6)
        }
    }

    // MARK: - Other Connections List

    @ViewBuilder
    private var otherConnectionsList: some View {
        let otherWired = viewModel.snapshot.actualPrimaryIsWired
            ? viewModel.wiredInterfaces.filter { !$0.isPrimary }
            : viewModel.wiredInterfaces

        let showWifiInOther = viewModel.snapshot.actualPrimaryIsWired

        if otherWired.isEmpty && !showWifiInOther {
            Text("No other connections")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(otherWired) { iface in
                    compactWiredRow(iface)
                }

                if showWifiInOther {
                    compactWifiStandbyRow
                }
            }
        }
    }

    private func compactWiredRow(_ iface: WiredInterfaceState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor(for: iface.health))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                Text(iface.serviceName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("docknet.wired.\(iface.bsdName).name")
                    .accessibilityLabel(iface.serviceName)
                    .accessibilityValue(iface.serviceName)

                Spacer()

                Text(iface.bsdName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("BSD Interface \(iface.bsdName)")
            }

            HStack {
                Text(iface.statusSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("docknet.wired.\(iface.bsdName).health")
                    .accessibilityLabel(iface.statusSummary)
                    .accessibilityValue(iface.statusSummary)

                Spacer()

                if let ip = iface.ipv4Address {
                    Text(ip)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("docknet.wired.\(iface.bsdName).address")
                        .accessibilityLabel("IP Address \(ip)")
                        .accessibilityValue(ip)
                }
            }
        }
        .padding(6)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(4)
    }

    private var compactWifiStandbyRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                Text("Wi-Fi")
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Text(viewModel.snapshot.wifi.bsdName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("docknet.wifi.interface")
                    .accessibilityLabel("Wi-Fi Interface \(viewModel.snapshot.wifi.bsdName)")
            }

            HStack {
                Text(viewModel.wifiStatusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("docknet.wifi.health")
                    .accessibilityLabel("Wi-Fi Status \(viewModel.wifiStatusText)")
                    .accessibilityValue(viewModel.wifiStatusText)

                Spacer()

                if let ip = viewModel.snapshot.wifi.primaryIPv4Address {
                    Text(ip)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("docknet.wifi.address")
                        .accessibilityLabel("Wi-Fi IP Address \(ip)")
                        .accessibilityValue(ip)
                }
            }
        }
        .padding(6)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(4)
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
