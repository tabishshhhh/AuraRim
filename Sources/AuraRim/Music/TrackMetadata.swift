import Foundation
import AppKit

/// Metadata for the currently playing track (spec §12).
struct TrackMetadata: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var playbackPosition: TimeInterval
    var playbackState: PlaybackState
    var bundleIdentifier: String
    var sourceName: String
    /// PNG/JPEG data for the artwork, if available. Kept as data so it stays
    /// Sendable; decoded to CGImage only when the track identity changes.
    var artworkData: Data?

    /// Stable identity used to decide when to re-extract artwork colors (spec §51).
    var signature: String {
        "\(bundleIdentifier)|\(title)|\(artist)|\(album)"
    }
}

/// Abstraction over a source of now-playing metadata (spec §12). The audio
/// *source* (what drives the rim) is deliberately separate from the *metadata*
/// source (what names the track) — see spec §77.
protocol MusicProvider: Sendable {
    var sourceName: String { get }
    var bundleIdentifier: String { get }
    func isRunning() -> Bool
    // Metadata queries run on the main actor: AppleScript / Apple Events and the
    // Automation consent dialog are only reliable from the main thread, and the
    // event descriptors they return are not Sendable.
    @MainActor func currentTrack() async -> TrackMetadata?
    /// Fetch artwork for the currently playing track. Called only when the track
    /// signature changes (spec §51), so it can be relatively expensive.
    @MainActor func artwork() async -> Data?
}
