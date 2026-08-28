import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders alongside Info.plist's LSUIElement: guarantees
        // no Dock icon/app switcher entry even if plist processing timing
        // ever changes.
        NSApp.setActivationPolicy(.accessory)
    }
}
