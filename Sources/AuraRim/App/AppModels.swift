import Foundation

/// Visual animation modes (spec §16–18). `rawValue` is passed to the shader as
/// `animationMode`.
enum AnimationMode: Int, Codable, CaseIterable, Sendable {
    case musicSync = 0
    case idle = 1
    case `static` = 2

    var title: String {
        switch self {
        case .musicSync: return "Music Sync"
        case .idle: return "Idle"
        case .static: return "Static"
        }
    }

    var symbol: String {
        switch self {
        case .musicSync: return "waveform"
        case .idle: return "moon.stars"
        case .static: return "circle"
        }
    }
}

/// How the rim colors are chosen (spec §10–11).
enum ColorSource: Int, Codable, Sendable {
    case manual = 0
    case album = 1
}

/// Playback state reported by a music provider.
enum PlaybackState: Int, Codable, Sendable {
    case stopped, playing, paused
}
