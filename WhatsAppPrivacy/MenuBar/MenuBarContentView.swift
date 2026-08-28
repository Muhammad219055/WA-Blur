import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            statusSection
            Divider()
            if appState.accessibilityTrusted {
                Button(appState.isPrivacyEnabled ? "Turn Privacy Off" : "Turn Privacy On") {
                    appState.togglePrivacy()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            } else {
                Button("Open Accessibility Settings…") {
                    openAccessibilitySettings()
                }
            }
            Divider()
            Button("Quit WhatsApp Privacy") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if !appState.accessibilityTrusted {
            Text("Accessibility access needed to detect and follow the WhatsApp window.")
        } else if !appState.isWhatsAppRunning {
            Text("Waiting for WhatsApp…")
        } else {
            Text("Privacy: \(appState.isPrivacyEnabled ? "ON" : "OFF")")
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
