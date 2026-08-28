import Carbon.HIToolbox
import AppKit

/// Top-level, non-capturing C callback required by InstallEventHandler.
/// Carbon's Event Manager predates Swift closures capturing context, so this
/// must be a free function; it looks the real handler up by hotkey ID via
/// `GlobalHotkeyManager.invoke`.
private func wabHotKeyEventHandler(_ nextHandler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let id = hotKeyID.id
    Task { @MainActor in
        GlobalHotkeyManager.invoke(id: id)
    }
    return noErr
}

@MainActor
final class GlobalHotkeyManager {
    private static var registry: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var didInstallHandler = false

    private let onToggle: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyID: UInt32?

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
    }

    static func invoke(id: UInt32) {
        registry[id]?()
    }

    /// Registers Carbon's system-wide hotkey for Cmd+Shift+B. Chosen over
    /// NSEvent global monitoring: Secure Input Mode (active whenever any
    /// secure text field has focus system-wide) suppresses NSEvent global
    /// keyDown monitors entirely, but registered Carbon hotkeys keep firing
    /// -- the same mechanism Spotlight's and the screenshot hotkey rely on.
    /// It also genuinely intercepts the combination (Safari's own Bookmarks
    /// Bar shortcut is also Cmd+Shift+B) rather than merely observing it.
    /// Fully decoupled from Accessibility permission -- no TCC prompt is
    /// involved in registering or firing this hotkey.
    func register() {
        Self.installEventHandlerIfNeeded()

        let id = Self.nextID
        Self.nextID += 1
        Self.registry[id] = onToggle
        hotKeyID = id

        let hotKeyIdentifier = EventHotKeyID(signature: OSType(0x5741_4231), id: id) // 'WAB1'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            UInt32(cmdKey | shiftKey),
            hotKeyIdentifier,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        } else {
            Self.registry[id] = nil
            hotKeyID = nil
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        if let hotKeyID {
            Self.registry[hotKeyID] = nil
        }
        hotKeyID = nil
    }

    private static func installEventHandlerIfNeeded() {
        guard !didInstallHandler else { return }
        didInstallHandler = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), wabHotKeyEventHandler, 1, &eventType, nil, nil)
    }
}
