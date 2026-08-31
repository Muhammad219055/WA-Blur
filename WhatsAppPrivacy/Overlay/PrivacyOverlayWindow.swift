import AppKit
import SwiftUI

final class PrivacyOverlayWindow: NSWindow {
    init(frame: CGRect, settings: PrivacySettings, capture: WhatsAppWindowCapture, revealTracker: OverlayRevealTracker) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // The core click-through requirement: WhatsApp underneath receives
        // all mouse events as if this window weren't there.
        ignoresMouseEvents = true
        hasShadow = false
        // .floating, not .normal: WhatsApp's own window can be re-raised by
        // far more than clicks or app-switches -- confirmed live, a hover-
        // to-raise utility (e.g. AutoRaise) re-raises it continuously just
        // from mouse movement. Keeping this overlay at .normal and re-
        // asserting "order above WhatsApp" after each raise produced a
        // constant, highly visible flicker, since there's no notification
        // for "some window's z-order changed" to react to in time -- only
        // periodic polling, which can't keep up with hover-driven raises.
        // .floating is structurally immune to this class of disruption: a
        // floating window is always above every normal-level window
        // regardless of how often WhatsApp's own window gets re-raised, so
        // there is nothing left to race against. The risk this reintroduces
        // (floating sits above *any* app's window, not just WhatsApp's) is
        // handled instead in AppDelegate by hiding the overlay outright
        // when a genuinely overlapping window becomes frontmost.
        level = .floating
        // .fullScreenAuxiliary (new in Phase 2): by default, a Space
        // currently showing another app's native-fullscreen window refuses
        // ordinary windows from other apps entirely -- without this flag, a
        // freshly-created overlay window would get bounced back to the
        // regular desktop instead of appearing on WhatsApp's fullscreen
        // Space. Still deliberately NOT .canJoinAllSpaces (see below): that
        // flag makes a window a permanent fixture on *every* Space
        // simultaneously, which is what caused the original cross-desktop
        // leak Phase 1 shipped with. .fullScreenAuxiliary only grants
        // entry to a fullscreen Space that the app is legitimately
        // following into via the Space-change handling in AppDelegate; it
        // does not make the window omnipresent.
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        // Explicit, not relying on the default: this window belongs to an
        // accessory-policy app that is itself never "the active app," so if
        // this defaulted to true the overlay could vanish whenever ANY
        // other app is frontmost -- which is always, for us.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: PrivacyContentRouter(settings: settings, capture: capture, revealTracker: revealTracker))
    }
}
