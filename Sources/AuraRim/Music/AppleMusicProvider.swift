import Foundation
import AppKit

/// Apple Music (Music.app) metadata via AppleScript (spec §12).
struct AppleMusicProvider: MusicProvider {
    let sourceName = "Apple Music"
    let bundleIdentifier = "com.apple.Music"

    func isRunning() -> Bool { AppleScriptRunner.isRunning(bundleIdentifier: bundleIdentifier) }

    @MainActor func currentTrack() async -> TrackMetadata? {
        guard isRunning() else { return nil }
        let script = """
        tell application "Music"
            if player state is stopped then return {"", "", "", "stopped", 0, 0}
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set trackPos to player position
            set trackDur to duration of current track
            set pstate to player state as text
            return {trackName, trackArtist, trackAlbum, pstate, trackPos, trackDur}
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

    @MainActor func artwork() async -> Data? {
        guard isRunning() else { return nil }
        // Apple Music artwork is local raw data; return it as bytes.
        let script = """
        tell application "Music"
            if player state is stopped then return missing value
            try
                return (data of artwork 1 of current track)
            on error
                return missing value
            end try
        end tell
        """
        guard case let .success(desc) = await AppleScriptRunner.run(script) else { return nil }
        // Raw picture bytes; try to normalize through NSImage → PNG.
        let raw = desc.data
        if !raw.isEmpty, let image = NSImage(data: raw) {
            return image.pngData()
        }
        return raw.isEmpty ? nil : raw
    }
}

extension PlaybackState {
    init(appleScript value: String?) {
        switch value {
        case "playing": self = .playing
        case "paused": self = .paused
        default: self = .stopped
        }
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
