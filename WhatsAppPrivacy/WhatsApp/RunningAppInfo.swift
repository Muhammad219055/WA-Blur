import AppKit

struct RunningAppInfo: Equatable, Sendable {
    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t

    init(bundleIdentifier: String?, localizedName: String?, processIdentifier: pid_t) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
    }

    init(_ app: NSRunningApplication) {
        self.init(
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName,
            processIdentifier: app.processIdentifier
        )
    }
}
