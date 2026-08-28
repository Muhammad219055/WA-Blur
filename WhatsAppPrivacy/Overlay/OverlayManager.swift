import AppKit

@MainActor
final class OverlayManager {
    private var window: PrivacyOverlayWindow?

    /// Ordering the window in once and then only fading `alphaValue` between
    /// 0 and 1 -- never `orderOut`/`orderFront` cycling it -- is what keeps
    /// this window pinned to the Space it was created on. `ignoresMouseEvents`
    /// is already true, so an alpha-0 window still doesn't intercept clicks;
    /// it just isn't visible.
    func showOverlay(at frame: CGRect) {
        if let window {
            if window.frame != frame {
                window.setFrame(frame, display: true)
            }
            window.alphaValue = 1
        } else {
            let newWindow = PrivacyOverlayWindow(frame: frame)
            newWindow.orderFrontRegardless()
            newWindow.alphaValue = 1
            window = newWindow
        }
    }

    func hideOverlay() {
        window?.alphaValue = 0
    }

    func destroyOverlay() {
        window?.orderOut(nil)
        window = nil
    }

    /// Call when the active Space has changed: any existing window may now
    /// be attached to the wrong Space, and there is no public API to move an
    /// existing window to a specific background Space, so the only fix is to
    /// drop it and let the next showOverlay() call create a fresh one while
    /// the correct Space is confirmed active (see AppDelegate).
    func invalidateForSpaceChange() {
        window?.orderOut(nil)
        window = nil
    }
}
