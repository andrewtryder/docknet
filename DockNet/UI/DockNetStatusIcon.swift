import SwiftUI

public enum StatusIconBadge: Equatable, Sendable {
    case none
    case negotiating
    case degraded
}

/// Reusable status icon view for DockNet menu bar and header presentation.
/// Composes two perfectly aligned vector templates (RJ45 and Wi-Fi arcs),
/// coloring only the currently active physical transport green (active + healthy),
/// amber/orange for negotiating, and secondary/gray for standby.
public struct DockNetStatusIcon: View {
    @ObservedObject var viewModel: StatusViewModel

    public init(viewModel: StatusViewModel) {
        self.viewModel = viewModel
    }

    private var ethernetColor: Color {
        if viewModel.snapshot.actualPrimaryIsWired {
            return .green
        }
        if viewModel.snapshot.wiredInterfaces.contains(where: { $0.health == .obtainingDHCP || $0.health == .linkUp }) {
            return .orange
        }
        return .secondary
    }

    private var wifiColor: Color {
        if viewModel.snapshot.isWifiPrimary {
            return .green
        }
        return .secondary
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                // Ethernet / RJ45 glyph
                Image("DockNetEthernetGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(ethernetColor)
                    .accessibilityHidden(true)

                // Wi-Fi glyph
                Image("DockNetWiFiGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(wifiColor)
                    .accessibilityHidden(true)
            }
            .frame(width: 18, height: 18)

            // Subtle badge overlays for non-primary states
            switch viewModel.statusIconBadge {
            case .none:
                EmptyView()

            case .negotiating:
                // Small amber progress indicator
                HStack(spacing: 1) {
                    Circle().frame(width: 2, height: 2)
                    Circle().frame(width: 2, height: 2)
                    Circle().frame(width: 2, height: 2)
                }
                .foregroundColor(.orange)
                .padding(1)
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(Capsule())
                .offset(x: 2, y: 2)
                .accessibilityHidden(true)

            case .degraded:
                // Compact red exclamation indicator (does not color entire icon)
                Image(systemName: "exclamationmark.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 8, height: 8)
                    .foregroundColor(.red)
                    .background(Color(NSColor.windowBackgroundColor))
                    .clipShape(Circle())
                    .offset(x: 2, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("docknet.status.icon")
        .accessibilityLabel(viewModel.statusIconAccessibilityLabel)
        .accessibilityValue(viewModel.statusIconAccessibilityLabel)
    }
}
