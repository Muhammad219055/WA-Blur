import SwiftUI

@main
struct WhatsAppPrivacyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                appState: appDelegate.appState,
                privacySettings: appDelegate.privacySettings,
                launchAtLogin: appDelegate.launchAtLogin
            )
        } label: {
            MenuBarIconView(appState: appDelegate.appState)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarIconView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Image(systemName: appState.isPrivacyEnabled ? "eye.slash.fill" : "eye.fill")
    }
}
