import AppKit
import Combine

// @MainActor on the class itself: several stored property initializers here
// (AppState(), AccessibilityManager(), WhatsAppDetector()) are @MainActor-
// isolated types, and Swift 6 strict concurrency rejects a main-actor-
// isolated default value in an otherwise-nonisolated type.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private let accessibilityManager = AccessibilityManager()
    private lazy var windowTracker = WhatsAppWindowTracker(accessibilityManager: accessibilityManager)
    private let detector = WhatsAppDetector()
    private lazy var overlayManager = OverlayManager()
    private var hotkeyManager: GlobalHotkeyManager?
    private var currentWhatsAppPID: pid_t?
    private var activationObserver: NSObjectProtocol?
    /// True while some other app's window is genuinely covering WhatsApp's
    /// window (see bindAppActivation) -- the overlay hides so that window
    /// isn't obstructed, distinct from isPrivacyEnabled/isWhatsAppRunning.
    private var overlaySuppressedByOverlappingWindow = false
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders alongside Info.plist's LSUIElement: guarantees
        // no Dock icon/app switcher entry even if plist processing timing
        // ever changes.
        NSApp.setActivationPolicy(.accessory)

        bindDetector()
        bindAccessibilityTrust()
        bindWindowFrame()
        bindPrivacyToggle()
        bindAppActivation()

        accessibilityManager.startMonitoringTrustState()
        detector.startMonitoring()

        let hotkeyManager = GlobalHotkeyManager { [weak self] in
            self?.appState.togglePrivacy()
        }
        hotkeyManager.register()
        self.hotkeyManager = hotkeyManager
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregister()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        windowTracker.stopTracking()
        detector.stopMonitoring()
        accessibilityManager.stopMonitoringTrustState()
        overlayManager.destroyOverlay()
    }

    private func bindDetector() {
        detector.$runningApp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] runningApp in
                guard let self else { return }
                self.appState.isWhatsAppRunning = runningApp != nil
                self.currentWhatsAppPID = runningApp?.processIdentifier
                if let runningApp {
                    self.windowTracker.startTracking(pid: runningApp.processIdentifier)
                    // Establish initial suppression state immediately rather
                    // than waiting for the next activation change, in case
                    // WhatsApp was detected while some other overlapping
                    // window was already frontmost.
                    self.refreshSuppression(forFrontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
                } else {
                    self.windowTracker.stopTracking()
                    self.appState.whatsAppFrame = nil
                    self.overlaySuppressedByOverlappingWindow = false
                    self.overlayManager.destroyOverlay()
                }
            }
            .store(in: &cancellables)
    }

    private func bindAccessibilityTrust() {
        accessibilityManager.$isTrusted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] trusted in
                self?.appState.accessibilityTrusted = trusted
            }
            .store(in: &cancellables)
    }

    private func bindWindowFrame() {
        windowTracker.$frame
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                guard let self else { return }
                self.appState.whatsAppFrame = frame
                self.syncOverlay()
            }
            .store(in: &cancellables)
    }

    private func bindPrivacyToggle() {
        appState.$isPrivacyEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncOverlay()
            }
            .store(in: &cancellables)
    }

    /// The overlay sits at .floating level (see PrivacyOverlayWindow), so it
    /// is always above WhatsApp's own window with no risk of flicker from
    /// WhatsApp re-raising itself (clicks, hover-to-raise utilities, etc.) --
    /// that class of event needs no reaction at all now. The one thing
    /// .floating does NOT handle correctly on its own is a genuinely
    /// different app's window placed on top of WhatsApp, which would
    /// otherwise render behind this overlay. That case is rare enough
    /// (an app activation, not a per-click event) to handle by checking,
    /// on each activation, whether the newly-frontmost app's window
    /// actually overlaps WhatsApp's -- and hiding the overlay only then.
    private func bindAppActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            // This notification fires while the window server is still
            // raising the newly-activated app's window, not after -- a
            // short settle delay lets that finish before we read its frame,
            // so the overlap check sees the window's real, final position.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.refreshSuppression(forFrontmostPID: app.processIdentifier)
            }
        }
    }

    private func refreshSuppression(forFrontmostPID frontmostPID: pid_t?) {
        guard let waPID = currentWhatsAppPID else { return }

        let suppressed: Bool
        if frontmostPID == waPID || frontmostPID == nil {
            suppressed = false
        } else if let waFrame = WindowStackingLookup.mainWindow(forProcessIdentifier: waPID)?.frame,
                  let otherFrame = WindowStackingLookup.mainWindow(forProcessIdentifier: frontmostPID!)?.frame {
            suppressed = waFrame.intersects(otherFrame)
        } else {
            // Couldn't determine the other window's bounds -- default to
            // not suppressing, since understating an actual overlap only
            // risks a momentarily-obstructed window, while overstating one
            // would silently drop privacy protection.
            suppressed = false
        }

        if suppressed != overlaySuppressedByOverlappingWindow {
            overlaySuppressedByOverlappingWindow = suppressed
            syncOverlay()
        }
    }

    private func syncOverlay() {
        guard appState.isWhatsAppRunning, let frame = appState.whatsAppFrame else {
            overlayManager.destroyOverlay()
            return
        }
        guard appState.isPrivacyEnabled, !overlaySuppressedByOverlappingWindow else {
            overlayManager.hideOverlay()
            return
        }
        overlayManager.showOverlay(at: frame)
    }
}
