import Foundation
import AppKit

/// Permission lifecycle used across audio & automation (spec §26).
enum PermissionState: Sendable, Equatable {
    case unknown, requesting, granted, denied, restricted
}

enum SystemSettingsPane {
    /// Deep-links into System Settings. Falls back to opening the app.
    static func open(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        if let url, NSWorkspace.shared.open(url) { return }
        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(fallback)
        }
    }

    static func openScreenRecording() { open("Privacy_ScreenCapture") }
    static func openAutomation() { open("Privacy_Automation") }
}
