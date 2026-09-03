import Foundation

/// Adaptive bass-transient beat detector (spec §15, §64). Maintains a rolling
/// baseline of bass energy and fires when energy deviates upward AND spectral
/// flux confirms an onset AND the cooldown has elapsed. Pure & testable.
final class BeatDetector {
    private var history: [Float]
    private var index = 0
    private var filled = 0
    private var timeSinceLastBeat: Float = 1
    private let cooldown: Float
    private let sensitivity: Float
    private let fluxThreshold: Float

    init(historyFrames: Int = 43, cooldown: Float = 0.12,
         sensitivity: Float = 1.45, fluxThreshold: Float = 0.6) {
        self.history = [Float](repeating: 0, count: historyFrames)
        self.cooldown = cooldown
        self.sensitivity = sensitivity
        self.fluxThreshold = fluxThreshold
    }

    /// Returns beatStrength 0…1 (0 = no beat this frame). `dt` is seconds since
    /// the previous call.
    func process(bass: Float, flux: Float, dt: Float) -> Float {
        timeSinceLastBeat += dt
        let baseline = currentBaseline()
        push(bass)

        let deviation = bass / max(baseline, 1e-4)
        guard deviation > sensitivity,
              flux > fluxThreshold,
              timeSinceLastBeat > cooldown else { return 0 }

        timeSinceLastBeat = 0
        // Normalize deviation over an expected range into 0…1.
        let strength = min(1, max(0, (deviation - sensitivity) / 2.0))
        return max(0.25, strength)
    }

    private func currentBaseline() -> Float {
        guard filled > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<filled { sum += history[i] }
        return sum / Float(filled)
    }

    private func push(_ v: Float) {
        history[index] = v
        index = (index + 1) % history.count
        filled = min(filled + 1, history.count)
    }
}

/// Attack/release envelope follower (spec §69). Fast rise, slow fall to avoid
/// jitter. Also used for the decaying beat impulse.
struct EnvelopeFollower {
    var value: Float = 0
    let attack: Float   // seconds
    let release: Float

    init(attack: Float = 0.04, release: Float = 0.28) {
        self.attack = attack; self.release = release
    }

    mutating func update(target: Float, dt: Float) -> Float {
        let coeff = target > value
            ? 1 - expf(-dt / max(attack, 1e-4))
            : 1 - expf(-dt / max(release, 1e-4))
        value += (target - value) * coeff
        return value
    }

    /// Decaying impulse: `beatEnvelope = max(newBeat, prev * exp(-dt/decay))`.
    mutating func impulse(_ newBeat: Float, dt: Float, decay: Float = 0.25) -> Float {
        value = max(newBeat, value * expf(-dt / decay))
        return value
    }
}
