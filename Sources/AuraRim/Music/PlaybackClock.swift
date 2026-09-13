import QuartzCore

/// Estimates the current playback position between metadata polls using a
/// monotonic clock, re-anchoring only on real jumps — track change, play/pause
/// transitions, or a large drift (a seek). This keeps lyric sync smooth instead
/// of stuttering every poll (architecture report §2, "Playback clock").
struct PlaybackClock {
    private var anchorPosition: TimeInterval = 0
    private var anchorTime: CFTimeInterval = CACurrentMediaTime()
    private var playing = false
    private var signature = ""

    /// Smoothly estimated position right now.
    var currentTime: TimeInterval {
        playing ? anchorPosition + (CACurrentMediaTime() - anchorTime) : anchorPosition
    }

    /// Feed the latest reported player state. Re-anchors only when needed so the
    /// estimate advances smoothly between ~1 Hz metadata polls.
    mutating func update(position: TimeInterval, playing: Bool, signature: String) {
        let now = CACurrentMediaTime()
        let estimated = self.playing ? anchorPosition + (now - anchorTime) : anchorPosition
        let jumped = signature != self.signature
            || playing != self.playing
            || abs(estimated - position) > 0.75
        if jumped {
            anchorPosition = position
            anchorTime = now
            self.playing = playing
            self.signature = signature
        }
    }
}
