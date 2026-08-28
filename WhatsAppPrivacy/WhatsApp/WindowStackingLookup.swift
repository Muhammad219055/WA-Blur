import CoreGraphics

/// Looks up a process's main on-screen window (frame + CGWindowID) via the
/// CoreGraphics window-server API, so the overlay can tell whether some
/// other app's window is genuinely covering WhatsApp -- not just that a
/// different app became active.
///
/// This is a separate, small file because it talks to CGWindowListCopyWindowInfo,
/// a different framework family from the Accessibility APIs the rest of
/// WhatsApp/ uses. Frames returned here are in the CoreGraphics/AX global
/// coordinate space (top-left origin), NOT Cocoa's -- callers comparing two
/// results from this file never need to convert, since both sides are in
/// the same space; only mixing with an already-Cocoa-converted frame (e.g.
/// AppState.whatsAppFrame) would require going through AXCoordinateConverter.
enum WindowStackingLookup {
    struct WindowInfo {
        let windowNumber: CGWindowID
        let frame: CGRect
    }

    /// The largest on-screen, normal-layer (layer 0) window owned by `pid`.
    /// Layer 0 excludes menu bar items, tooltips, and other chrome, and the
    /// largest-area heuristic reliably picks the main document window over
    /// any small popovers/panels the process might also own.
    static func mainWindow(forProcessIdentifier pid: pid_t) -> WindowInfo? {
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: AnyObject]] else {
            return nil
        }

        let candidates: [(info: [String: AnyObject], frame: CGRect)] = windowList.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int) == Int(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: AnyObject],
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }
            return (info, frame)
        }

        guard let best = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
              let windowNumber = (best.info[kCGWindowNumber as String] as? Int).map({ CGWindowID($0) }) else {
            return nil
        }
        return WindowInfo(windowNumber: windowNumber, frame: best.frame)
    }

    /// True only if `pid` has a window CGWindowListCopyWindowInfo reports as
    /// on-screen *right now* -- which, critically, is Space-aware: a window
    /// on a Space that isn't currently active does not appear here. This is
    /// the ground truth this task uses to decide whether WhatsApp is visible
    /// on whichever Space just became active.
    static func isWindowOnScreen(forProcessIdentifier pid: pid_t) -> Bool {
        mainWindow(forProcessIdentifier: pid) != nil
    }
}
