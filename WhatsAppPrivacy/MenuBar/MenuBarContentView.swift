import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var privacySettings: PrivacySettings
    @ObservedObject var launchAtLogin: LaunchAtLoginManager

    var body: some View {
        Group {
            statusSection
            Divider()

            if appState.accessibilityTrusted {
                Button(appState.isPrivacyEnabled ? "Turn Privacy Off" : "Turn Privacy On") {
                    appState.togglePrivacy()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Menu("Region") {
                    ForEach(PrivacyRegionScope.allCases, id: \.self) { scope in
                        Button {
                            privacySettings.regionScope = scope
                        } label: {
                            if privacySettings.regionScope == scope {
                                Label(scope.menuTitle, systemImage: "checkmark")
                            } else {
                                Text(scope.menuTitle)
                            }
                        }
                    }
                }

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

                Menu("Reveal Behavior") {
                    ForEach(PrivacyRevealMode.allCases, id: \.self) { mode in
                        Button {
                            privacySettings.revealMode = mode
                        } label: {
                            if privacySettings.revealMode == mode {
                                Label(mode.menuTitle, systemImage: "checkmark")
                            } else {
                                Text(mode.menuTitle)
                            }
                        }
                    }
                }

                Divider()

                Button {
                    launchAtLogin.toggle()
                } label: {
                    if launchAtLogin.isEnabled {
                        Label("Launch at Login", systemImage: "checkmark")
                    } else {
                        Text("Launch at Login")
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
            Text("Privacy: \(appState.isPrivacyEnabled ? "ON" : "OFF") (\(privacySettings.regionScope.menuTitle))")
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
