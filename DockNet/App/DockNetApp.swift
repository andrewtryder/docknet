import SwiftUI

@main
struct DockNetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: appDelegate.viewModel)
        } label: {
            DockNetStatusIcon(viewModel: appDelegate.viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
