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
    func currentTrack() async -> TrackMetadata?
    /// Fetch artwork for the currently playing track. Called only when the track
    /// signature changes (spec §51), so it can be relatively expensive.
    func artwork() async -> Data?
}
