import AppKit
@preconcurrency import ApplicationServices
import Combine

/// Wraps the lifetime of one AXObserver registration: the observer itself,
/// the notifications added to it, and the retained callback box. `invalidate()`
/// must be called exactly once to release the callback and detach from the
/// run loop; failing to call it leaks the callback box.
final class AXWindowObservation {
    private let observer: AXObserver
    private let appElement: AXUIElement
    private let notifications: [String]
    private let boxRef: Unmanaged<AXObservationCallbackBox>

    init(observer: AXObserver, appElement: AXUIElement, notifications: [String], boxRef: Unmanaged<AXObservationCallbackBox>) {
        self.observer = observer
        self.appElement = appElement
        self.notifications = notifications
        self.boxRef = boxRef
    }

    func invalidate() {
        for notification in notifications {
            AXObserverRemoveNotification(observer, appElement, notification as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        boxRef.release()
    }
}

final class AXObservationCallbackBox: @unchecked Sendable {
    let callback: () -> Void
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
}

@MainActor
final class AccessibilityManager: ObservableObject {
    @Published private(set) var isTrusted: Bool = false

    private var pollTimer: Timer?

    func startMonitoringTrustState() {
        refreshTrustState(promptIfNeeded: true)
        // Foundation Timer (not the DispatchSourceTimer used for window-frame
        // safety-net polling elsewhere) is appropriate here: this only runs
        // while the app is alive at all, at a low fixed 2s cadence, purely to
        // notice a permission grant made in System Settings.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTrustState(promptIfNeeded: false)
            }
        }
    }

    func stopMonitoringTrustState() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refreshTrustState(promptIfNeeded: Bool) {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded]
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func mainWindowFrame(forProcessIdentifier pid: pid_t) -> CGRect? {
        guard isTrusted else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        guard let window = focusedWindow(of: appElement) ?? firstWindow(of: appElement) else {
            return nil
        }
        return frame(of: window)
    }

    func observeWindow(forProcessIdentifier pid: pid_t, onChange: @escaping () -> Void) -> AXWindowObservation? {
        guard isTrusted else { return nil }

        var observerRef: AXObserver?
        guard AXObserverCreate(pid, axObservationCallback, &observerRef) == .success, let observer = observerRef else {
            return nil
        }

        let box = AXObservationCallbackBox(callback: onChange)
        let boxRef = Unmanaged.passRetained(box)
        let appElement = AXUIElementCreateApplication(pid)

        let notifications = [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification
        ]
        for notification in notifications {
            AXObserverAddNotification(observer, appElement, notification as CFString, boxRef.toOpaque())
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        return AXWindowObservation(observer: observer, appElement: appElement, notifications: notifications, boxRef: boxRef)
    }

    private func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value else {
            return nil
        }
        // AX API contract: a successful copy of kAXFocusedWindowAttribute
        // always yields a CFTypeRef that is in fact an AXUIElement.
        return (value as! AXUIElement)
    }

    private func firstWindow(of appElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return nil
        }
        return windows.first
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        // AX API contract: kAXPositionAttribute/kAXSizeAttribute always yield
        // AXValue-wrapped CGPoint/CGSize on success.
        let gotPosition = AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        let gotSize = AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard gotPosition, gotSize else { return nil }

        return CGRect(origin: position, size: size)
    }
}

/// Top-level, non-capturing C callback required by AXObserverCreate. Looks up
/// the real handler via the retained box passed as `refcon`.
private func axObservationCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let box = Unmanaged<AXObservationCallbackBox>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in
        box.callback()
    }
}
