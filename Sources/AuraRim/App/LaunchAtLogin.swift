import ServiceManagement
import Foundation

/// Launch-at-login via the modern ServiceManagement API (spec §30). Only works
/// for a signed, bundled app; in a bare dev binary it logs and no-ops.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    static func set(_ enabled: Bool) {
        guard #available(macOS 13, *) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.app.error("Launch at login change failed: \(error.localizedDescription)")
        }
    }
}
