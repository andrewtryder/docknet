import SwiftUI

public enum StatusIconBadge: Equatable, Sendable {
    case none
    case negotiating
    case degraded
}

/// Reusable status icon view for DockNet menu bar and header presentation.
/// Renders the custom vector RJ45/Wi-Fi glyph as a macOS template image,
/// with subtle monochrome indicators only for negotiating (DHCP) or degraded states.
public struct DockNetStatusIcon: View {
    @ObservedObject var viewModel: StatusViewModel

    public init(viewModel: StatusViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image("DockNetMenuBar")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)

            // Subtle monochrome badge overlays
            switch viewModel.statusIconBadge {
            case .none:
                EmptyView()
            case .negotiating:
                // Small ellipsis / progress indicator
                HStack(spacing: 1) {
                    Circle().frame(width: 2, height: 2)
                    Circle().frame(width: 2, height: 2)
                    Circle().frame(width: 2, height: 2)
                }
                .padding(1)
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(Capsule())
                .offset(x: 2, y: 2)
                .accessibilityHidden(true)

            case .degraded:
                // Small monochrome exclamation indicator
                Image(systemName: "exclamationmark.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 8, height: 8)
                    .background(Color(NSColor.windowBackgroundColor))
                    .clipShape(Circle())
                    .offset(x: 2, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityIdentifier("docknet.status.icon")
        .accessibilityLabel(viewModel.statusIconAccessibilityLabel)
        .accessibilityValue(viewModel.statusIconAccessibilityLabel)
    }
}
