import Foundation
import AppKit

/// Runs AppleScript off the main thread and returns the event descriptor.
/// Used for supported music-app automation (spec §12). Automation permission is
/// only exercised when a target app is actually running.
enum AppleScriptRunner {
    struct ScriptError: Error { let message: String }

    /// Runs on the main actor. The Automation consent dialog is presented
    /// reliably only for Apple Events sent from the main thread; the call blocks
    /// briefly until the (fast) reply arrives — or until the user answers the
    /// one-time prompt.
    @MainActor
    static func run(_ source: String) async -> Result<NSAppleEventDescriptor, ScriptError> {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(ScriptError(message: "Invalid script"))
        }
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo, let number = errorInfo[NSAppleScript.errorNumber] as? Int, number != 0 {
            let msg = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(number)"
            Log.music.error("AppleScript failed (\(number)): \(msg, privacy: .public)")
            return .failure(ScriptError(message: msg))
        }
        return .success(result)
    }

    static func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
