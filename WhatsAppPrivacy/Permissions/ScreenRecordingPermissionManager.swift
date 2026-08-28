import AppKit
import CoreGraphics

@MainActor
final class ScreenRecordingPermissionManager: ObservableObject {
    @Published private(set) var isAuthorized: Bool = false

    private var pollTimer: Timer?

    func startMonitoring() {
        refresh()
        // Same rationale as AccessibilityManager's trust-state timer: low,
        // fixed cadence, purely to notice a grant made in System Settings
        // without the user having to relaunch the app.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Triggers the system permission prompt the first time this is called;
    /// CGRequestScreenCaptureAccess does not re-prompt once the user has
    /// answered once (granted or denied), matching how AXIsProcessTrustedWithOptions
    /// behaves for Accessibility. Call this only when the user actually
    /// selects Pixelate -- never at launch, since Blur and Redact don't need
    /// this permission at all.
    func requestAccess() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    private func refresh() {
        isAuthorized = CGPreflightScreenCaptureAccess()
    }
}
