import AppKit

@MainActor
final class OverlayManager {
    private var window: PrivacyOverlayWindow?

    func showOverlay(at frame: CGRect) {
        if let window {
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
        } else {
            let newWindow = PrivacyOverlayWindow(frame: frame)
            newWindow.orderFrontRegardless()
            window = newWindow
        }
    }

    func hideOverlay() {
        window?.orderOut(nil)
    }

    func destroyOverlay() {
        window?.orderOut(nil)
        window = nil
    }
}
