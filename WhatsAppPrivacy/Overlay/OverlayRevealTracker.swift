import AppKit
import Combine

@MainActor
final class OverlayRevealTracker: ObservableObject {
    @Published private(set) var isPeeking: Bool = false

    private let settings: PrivacySettings
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var currentOverlayFrame: CGRect?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: PrivacySettings) {
        self.settings = settings
        bindSettings()
    }

    func updateOverlayFrame(_ frame: CGRect?) {
        self.currentOverlayFrame = frame
        reevaluateState()
    }

    func startTracking() {
        stopTracking()

        // Global and local mouse tracking for hover peek
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reevaluateHover()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.reevaluateHover()
            }
            return event
        }

        // Global and local modifier tracking for Option-key peek
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlags(event.modifierFlags)
            }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlags(event.modifierFlags)
            }
            return event
        }
    }

    func stopTracking() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalFlagsMonitor { NSEvent.removeMonitor(globalFlagsMonitor) }
        if let localFlagsMonitor { NSEvent.removeMonitor(localFlagsMonitor) }

        globalMouseMonitor = nil
        localMouseMonitor = nil
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        isPeeking = false
    }

    private func bindSettings() {
        settings.$revealMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reevaluateState()
            }
            .store(in: &cancellables)
    }

    private func reevaluateState() {
        switch settings.revealMode {
        case .none:
            isPeeking = false
        case .hoverPeek:
            reevaluateHover()
        case .modifierPeek:
            let flags = NSEvent.modifierFlags
            handleFlags(flags)
        }
    }

    private func reevaluateHover() {
        guard settings.revealMode == .hoverPeek, let frame = currentOverlayFrame else {
            if settings.revealMode != .modifierPeek { isPeeking = false }
            return
        }
        let mouseLocation = NSEvent.mouseLocation
        let hovering = frame.contains(mouseLocation)
        if isPeeking != hovering {
            isPeeking = hovering
        }
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        guard settings.revealMode == .modifierPeek else { return }
        let optionHeld = flags.contains(.option)
        if isPeeking != optionHeld {
            isPeeking = optionHeld
        }
    }
}
