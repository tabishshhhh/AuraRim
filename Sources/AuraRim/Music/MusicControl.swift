import Foundation

/// Transport control for supported music apps (spec §23). Automation permission
/// is only exercised when the user actually presses a control.
enum MusicControl {
    enum Command: String { case playPause = "playpause", next = "next track", previous = "previous track" }

    private static func appName(for bundleId: String) -> String? {
        switch bundleId {
        case "com.spotify.client": return "Spotify"
        case "com.apple.Music": return "Music"
        default: return nil
        }
    }

    @MainActor
    static func send(_ command: Command, bundleIdentifier: String) async {
        guard let app = appName(for: bundleIdentifier) else { return }
        _ = await AppleScriptRunner.run("tell application \"\(app)\" to \(command.rawValue)")
    }

    /// Seek relative to the current position, in seconds (can be negative).
    @MainActor
    static func seek(by seconds: Int, bundleIdentifier: String) async {
        guard let app = appName(for: bundleIdentifier) else { return }
        _ = await AppleScriptRunner.run(
            "tell application \"\(app)\" to set player position to (player position + \(seconds))")
    }
}
