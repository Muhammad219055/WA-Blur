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
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: PrivacyOverlayView())
    }
}
