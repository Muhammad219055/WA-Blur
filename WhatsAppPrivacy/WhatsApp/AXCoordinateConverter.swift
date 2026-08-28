import AppKit

enum AXCoordinateConverter {
    /// AX and Cocoa global coordinates describe the same combined
    /// multi-display area; they differ only by a single Y flip anchored at
    /// the *primary* (menu-bar) screen's height. This holds regardless of
    /// how many displays exist or how they're arranged, so no other screen's
    /// geometry -- and no backing scale factor, since both spaces are
    /// already in points -- enters this calculation.
    static func cocoaFrame(fromAXFrame axFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: axFrame.origin.x,
            y: primaryScreenHeight - axFrame.origin.y - axFrame.height,
            width: axFrame.width,
            height: axFrame.height
        )
    }

    static func cocoaFrame(fromAXFrame axFrame: CGRect, screens: [NSScreen] = NSScreen.screens) -> CGRect? {
        // AppKit guarantees screens[0] is the screen containing the menu
        // bar, i.e. the one Cocoa's global origin is anchored to.
        guard let primaryScreen = screens.first else { return nil }
        return cocoaFrame(fromAXFrame: axFrame, primaryScreenHeight: primaryScreen.frame.height)
    }
}
