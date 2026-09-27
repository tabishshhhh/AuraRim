import Foundation

/// Visual animation modes (spec §16–18). `rawValue` is passed to the shader as
/// `animationMode`.
enum AnimationMode: Int, Codable, CaseIterable, Sendable {
    // Raw values match the shader's `animationMode` uniform.
    case `default` = 3
    case musicSync = 0
    case idle = 1
    case noAnimation = 2

    var title: String {
        switch self {
        case .default: return "Default"
        case .musicSync: return "Music Sync"
        case .idle: return "Idle"
        case .noAnimation: return "No Animation"
        }
    }

    var symbol: String {
        switch self {
        case .default: return "sparkles"
        case .musicSync: return "waveform"
        case .idle: return "moon.stars"
        case .noAnimation: return "circle"
        }
    }
}

/// Number of colors in the rim gradient (spec §10).
enum GradientMode: Int, Codable, CaseIterable, Sendable {
    case one = 1
    case two = 2
    var title: String { self == .one ? "1 Color" : "2 Colors" }
}

/// How synced lyrics are presented. Original implementations, but the palette of
/// styles is designed to match/exceed verci.xyz (Focus/Karaoke/Spotlight plus
/// Ship, Fisheye and Visual). Word-level styles use real per-word (YRC) timing.
enum LyricsStyle: Int, Codable, CaseIterable, Sendable {
    case focus = 0      // scrolling list, active line bright (Apple Music-like)
    case karaoke = 1    // per-word light-up across the active line (real YRC timing)
    case spotlight = 2  // one large centered line with faint neighbors
    case ship = 3       // 3D drifting wall of words (Verci "Ship")
    case fisheye = 4    // convex lens stack, current word closest (Verci "Fisheye")
    case visual = 5     // each word paired with a matched SF Symbol (Verci "Visual")

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .karaoke: return "Karaoke"
        case .spotlight: return "Spotlight"
        case .ship: return "Ship"
        case .fisheye: return "Fisheye"
        case .visual: return "Visual"
        }
    }
    var symbol: String {
        switch self {
        case .focus: return "text.alignleft"
        case .karaoke: return "mic"
        case .spotlight: return "textformat.size.larger"
        case .ship: return "square.stack.3d.up"
        case .fisheye: return "circle.circle"
        case .visual: return "sparkles.rectangle.stack"
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
