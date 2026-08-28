import AppKit
import Combine

@MainActor
final class WhatsAppDetector: ObservableObject {
    @Published private(set) var runningApp: RunningAppInfo?

    private let workspace: NSWorkspace
    private var observers: [NSObjectProtocol] = []

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func startMonitoring() {
        refreshFromCurrentlyRunningApps()

        let center = workspace.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let info = RunningAppInfo(app)
            Task { @MainActor [weak self] in
                self?.handle(app: info, running: true)
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let info = RunningAppInfo(app)
            Task { @MainActor [weak self] in
                self?.handle(app: info, running: false)
            }
        })
    }

    func stopMonitoring() {
        let center = workspace.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    private func refreshFromCurrentlyRunningApps() {
        if let match = workspace.runningApplications.map(RunningAppInfo.init).first(where: WhatsAppIdentity.matches) {
            runningApp = match
        }
    }

    private func handle(app: RunningAppInfo, running: Bool) {
        guard WhatsAppIdentity.matches(app) else { return }
        runningApp = running ? app : nil
    }
}
