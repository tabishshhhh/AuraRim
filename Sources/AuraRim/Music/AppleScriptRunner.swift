import Foundation
import AppKit

/// Runs AppleScript off the main thread and returns the event descriptor.
/// Used for supported music-app automation (spec §12). Automation permission is
/// only exercised when a target app is actually running.
enum AppleScriptRunner {
    struct ScriptError: Error { let message: String }

    static func run(_ source: String) async -> Result<NSAppleEventDescriptor, ScriptError> {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    cont.resume(returning: .failure(ScriptError(message: "Invalid script")))
                    return
                }
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo, let number = errorInfo[NSAppleScript.errorNumber] as? Int, number != 0 {
                    let msg = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(number)"
                    cont.resume(returning: .failure(ScriptError(message: msg)))
                } else {
                    cont.resume(returning: .success(result))
                }
            }
        }
    }

    static func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
