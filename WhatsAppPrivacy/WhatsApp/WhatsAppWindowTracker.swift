import AppKit
import Combine

@MainActor
final class WhatsAppWindowTracker: ObservableObject {
    @Published private(set) var frame: CGRect?

    private let accessibilityManager: AccessibilityManager
    private var currentPID: pid_t?
    private var observation: AXWindowObservation?
    private var safetyNetTimer: DispatchSourceTimer?
    private var screenChangeObserver: NSObjectProtocol?

    init(accessibilityManager: AccessibilityManager) {
        self.accessibilityManager = accessibilityManager
    }

    func startTracking(pid: pid_t) {
        stopTracking()
        currentPID = pid

        refreshFrame()
        observation = accessibilityManager.observeWindow(forProcessIdentifier: pid) { [weak self] in
            Task { @MainActor in
                self?.refreshFrame()
            }
        }
        startSafetyNetTimer()
        startScreenChangeObserving()
    }

    func stopTracking() {
        observation?.invalidate()
        observation = nil
        stopSafetyNetTimer()
        stopScreenChangeObserving()
        currentPID = nil
        frame = nil
    }

    private func refreshFrame() {
        guard let pid = currentPID,
              let axFrame = accessibilityManager.mainWindowFrame(forProcessIdentifier: pid),
              let cocoaFrame = AXCoordinateConverter.cocoaFrame(fromAXFrame: axFrame) else {
            return
        }
        if frame != cocoaFrame {
            frame = cocoaFrame
        }
    }

    private func startSafetyNetTimer() {
        // DispatchSourceTimer with explicit leeway, not a bare Timer: this is
        // background housekeeping that doesn't need precision, so we let the
        // OS coalesce the wakeup with other system timer activity rather than
        // paying for a tight-tolerance wakeup every second.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(400))
        timer.setEventHandler { [weak self] in
            self?.refreshFrame()
        }
        timer.resume()
        safetyNetTimer = timer
    }

    private func stopSafetyNetTimer() {
        safetyNetTimer?.cancel()
        safetyNetTimer = nil
    }

    private func startScreenChangeObserving() {
        // AX doesn't reliably fire moved/resized when only the *screen*
        // reconfigures (display added/removed/resolution changed) under a
        // stationary window, so this is a separate event-driven trigger.
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshFrame()
        }
    }

    private func stopScreenChangeObserving() {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        screenChangeObserver = nil
    }
}
