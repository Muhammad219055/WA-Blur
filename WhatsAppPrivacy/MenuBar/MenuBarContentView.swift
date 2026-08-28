import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var privacySettings: PrivacySettings

    var body: some View {
        Group {
            statusSection
            Divider()
            if appState.accessibilityTrusted {
                Button(appState.isPrivacyEnabled ? "Turn Privacy Off" : "Turn Privacy On") {
                    appState.togglePrivacy()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                Menu("Style") {
                    ForEach(PrivacyRenderStyle.allCases, id: \.self) { style in
                        Button {
                            privacySettings.renderStyle = style
                        } label: {
                            if privacySettings.renderStyle == style {
                                Label(style.menuTitle, systemImage: "checkmark")
                            } else {
                                Text(style.menuTitle)
                            }
                        }
                    }
                }
                Menu("Intensity") {
                    ForEach(PrivacyIntensity.allCases, id: \.self) { level in
                        Button {
                            privacySettings.intensity = level
                        } label: {
                            if privacySettings.intensity == level {
                                Label(level.menuTitle, systemImage: "checkmark")
                            } else {
                                Text(level.menuTitle)
                            }
                        }
                    }
                }
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
