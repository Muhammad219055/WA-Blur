import AppKit
import SwiftUI

final class PrivacyOverlayWindow: NSWindow {
    init(frame: CGRect) {
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
        // Deliberately NOT .canJoinAllSpaces: that flag makes a window a
        // permanent fixture on every Space simultaneously (like a desktop
        // wallpaper or the Dock), not something that "follows" the app it's
        // tracking. With it set, this overlay was painting itself over
        // unrelated desktops and other apps' fullscreen Spaces whenever the
        // user switched away from WhatsApp's Space -- exactly backwards for
        // a privacy tool. Leaving collectionBehavior at its default keeps
        // this window confined to whichever Space it's currently on, same
        // as any ordinary window. Following WhatsApp across a Space change
        // it makes on its own, and native fullscreen support, are explicit
        // Phase 1 non-goals (see the design spec) and remain a known
        // limitation until a later phase adds per-Space window handling.
        collectionBehavior = [.ignoresCycle]
        // Explicit, not relying on the default: this window belongs to an
        // accessory-policy app that is itself never "the active app," so if
        // this defaulted to true the overlay could vanish whenever ANY
        // other app is frontmost -- which is always, for us.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: PrivacyOverlayView())
    }
}
