import AppKit

@MainActor
final class OverlayManager {
    private var window: PrivacyOverlayWindow?
    private let settings: PrivacySettings
    private let capture: WhatsAppWindowCapture
    let revealTracker: OverlayRevealTracker

    init(settings: PrivacySettings, capture: WhatsAppWindowCapture) {
        self.settings = settings
        self.capture = capture
        self.revealTracker = OverlayRevealTracker(settings: settings)
        self.revealTracker.startTracking()
    }

    /// Ordering the window in once and then only fading `alphaValue` between
    /// 0 and 1 -- never `orderOut`/`orderFront` cycling it -- is what keeps
    /// this window pinned to the Space it was created on. `ignoresMouseEvents`
    /// is already true, so an alpha-0 window still doesn't intercept clicks;
    /// it just isn't visible.
    func showOverlay(at windowFrame: CGRect) {
        let regionFrame = PrivacyRegionCalculator.regionFrame(for: windowFrame, scope: settings.regionScope)

        if let window {
            if window.frame != regionFrame {
                window.setFrame(regionFrame, display: true)
            }
            window.alphaValue = 1
        } else {
            let newWindow = PrivacyOverlayWindow(
                frame: regionFrame,
                settings: settings,
                capture: capture,
                revealTracker: revealTracker
            )
            newWindow.orderFrontRegardless()
            newWindow.alphaValue = 1
            window = newWindow
        }

        revealTracker.updateOverlayFrame(regionFrame)
    }

    func hideOverlay() {
        window?.alphaValue = 0
        revealTracker.updateOverlayFrame(nil)
    }

    func destroyOverlay() {
        window?.orderOut(nil)
        window = nil
        revealTracker.updateOverlayFrame(nil)
    }

    /// Call when the active Space has changed: any existing window may now
    /// be attached to the wrong Space, and there is no public API to move an
    /// existing window to a specific background Space, so the only fix is to
    /// drop it and let the next showOverlay() call create a fresh one while
    /// the correct Space is confirmed active (see AppDelegate).
    func invalidateForSpaceChange() {
        window?.orderOut(nil)
        window = nil
        revealTracker.updateOverlayFrame(nil)
    }
}
