import SwiftUI

/// Compact, polished native About view for DockNet.
public struct AboutView: View {
    public let urlOpener: any URLOpening

    public init(urlOpener: any URLOpening = WorkspaceURLOpener()) {
        self.urlOpener = urlOpener
    }

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private let gitHubURL = URL(string: "https://github.com/andrewtryder/docknet")!

    public var body: some View {
        VStack(spacing: 16) {
            // App Vector Icon
            Image("DockNetAboutIcon", bundle: .main)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.primary)
                .accessibilityIdentifier("docknet.about.icon")
                .accessibilityLabel("DockNet Application Icon")

            // Title and Version
            VStack(spacing: 4) {
                Text("DockNet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .accessibilityIdentifier("docknet.about.name")
                    .accessibilityLabel("DockNet")

                Text(appVersionString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("docknet.about.version")
                    .accessibilityLabel(appVersionString)
            }

            // Description
            Text("Automatic Ethernet/Wi-Fi connection monitoring for macOS.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.horizontal, 24)

            // Author Credit
            VStack(spacing: 2) {
                Text("Created by Andrew Ryder")
                    .font(.body)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("docknet.about.author")
                    .accessibilityLabel("Created by Andrew Ryder")

                Text("Creator")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // GitHub Link & Button
            VStack(spacing: 6) {
                Button(action: {
                    urlOpener.open(gitHubURL)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.subheadline)
                        Text("View on GitHub")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("docknet.about.github")
                .accessibilityLabel("View DockNet on GitHub")

                Text("github.com/andrewtryder/docknet")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 320, height: 360)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
