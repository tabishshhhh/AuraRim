import Foundation
import os

/// Normalized, renderer-facing snapshot of the audio pipeline (spec §37).
/// Raw audio never reaches the UI/renderer — only these smoothed values do.
struct AnimationState: Sendable, Equatable {
    var beat: Float = 0        // decaying beat impulse envelope 0…1
    var bass: Float = 0        // 40–180 Hz band energy 0…1
    var mids: Float = 0
    var highs: Float = 0
    var amplitude: Float = 0   // smoothed RMS 0…1
    var silence: Float = 1     // 0 = loud, 1 = fully silent
    var elapsedTime: Float = 0 // seconds since capture start

    static let idle = AnimationState()
}

/// Lock-protected, Sendable box used as the audio → renderer handoff.
/// Written by the analysis queue, read once per rendered frame. Avoids routing
/// high-frequency audio through SwiftUI observation (spec §62).
final class AnimationStateBus: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: AnimationState.idle)

    func store(_ state: AnimationState) {
        lock.withLock { $0 = state }
    }

    func load() -> AnimationState {
        lock.withLock { $0 }
    }
}
