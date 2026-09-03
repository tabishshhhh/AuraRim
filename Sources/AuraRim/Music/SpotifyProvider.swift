import Foundation

/// Spotify desktop metadata via AppleScript (spec §12). Artwork is an https URL.
struct SpotifyProvider: MusicProvider {
    let sourceName = "Spotify"
    let bundleIdentifier = "com.spotify.client"

    func isRunning() -> Bool { AppleScriptRunner.isRunning(bundleIdentifier: bundleIdentifier) }

    func currentTrack() async -> TrackMetadata? {
        guard isRunning() else { return nil }
        let script = """
        tell application "Spotify"
            if player state is stopped then return {"", "", "", "stopped", 0, 0, ""}
            set t to current track
            set st to (player state as text)
            return {name of t, artist of t, album of t, st, (player position as real), ((duration of t) / 1000), (artwork url of t)}
        end tell
        """
        guard case let .success(desc) = await AppleScriptRunner.run(script),
              desc.numberOfItems >= 6 else { return nil }

        let title = desc.atIndex(1)?.stringValue ?? ""
        guard !title.isEmpty else { return nil }
        return TrackMetadata(
            title: title,
            artist: desc.atIndex(2)?.stringValue ?? "",
            album: desc.atIndex(3)?.stringValue ?? "",
            duration: desc.atIndex(6)?.doubleValue ?? 0,
            playbackPosition: desc.atIndex(5)?.doubleValue ?? 0,
            playbackState: PlaybackState(appleScript: desc.atIndex(4)?.stringValue),
            bundleIdentifier: bundleIdentifier,
            sourceName: sourceName,
            artworkData: nil)
    }

    func artwork() async -> Data? {
        guard isRunning() else { return nil }
        let script = """
        tell application "Spotify"
            if player state is stopped then return ""
            return (artwork url of current track)
        end tell
        """
        guard case let .success(desc) = await AppleScriptRunner.run(script),
              let urlString = desc.stringValue, let url = URL(string: urlString) else { return nil }
        // Album art is fetched from Spotify's CDN; no user data leaves the device.
        return try? await URLSession.shared.data(from: url).0
    }
}
