import ServiceManagement
import Foundation

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled: Bool = false

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func setEnabled(_ enable: Bool) {
        do {
            if enable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // ServiceManagement registration errors handled gracefully
        }
        refreshStatus()
    }

    func toggle() {
        setEnabled(!isEnabled)
    }
}
