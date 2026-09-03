import QuartzCore

/// Smoothly moves the rim's current colors toward a target in OKLab, never
/// jumping (spec §36). Retargets cleanly if songs are skipped rapidly. Runs a
/// timer only while a transition is in flight, so idle cost is zero.
@MainActor
final class ColorTransitionEngine {
    private(set) var currentPrimary: ColorValue
    private(set) var currentSecondary: ColorValue
    private var fromPrimary: ColorValue
    private var fromSecondary: ColorValue
    private var targetPrimary: ColorValue
    private var targetSecondary: ColorValue

    private var startTime: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0.7
    private var timer: DispatchSourceTimer?

    /// Called on each interpolation step and once at completion.
    var onUpdate: (() -> Void)?

    init(primary: ColorValue, secondary: ColorValue) {
        currentPrimary = primary; currentSecondary = secondary
        fromPrimary = primary; fromSecondary = secondary
        targetPrimary = primary; targetSecondary = secondary
    }

    /// Snap immediately (used when settings change manual colors while no album
    /// transition should occur).
    func snap(primary: ColorValue, secondary: ColorValue) {
        stop()
        currentPrimary = primary; currentSecondary = secondary
        fromPrimary = primary; fromSecondary = secondary
        targetPrimary = primary; targetSecondary = secondary
        onUpdate?()
    }

    /// Begin (or retarget) a transition toward new colors.
    func transition(to primary: ColorValue, secondary: ColorValue, duration: CFTimeInterval = 0.7) {
        guard primary != targetPrimary || secondary != targetSecondary else { return }
        fromPrimary = currentPrimary; fromSecondary = currentSecondary
        targetPrimary = primary; targetSecondary = secondary
        self.duration = max(0.1, duration)
        startTime = CACurrentMediaTime()
        startTimer()
    }

    private func startTimer() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(16))
        t.setEventHandler { [weak self] in self?.step() }
        timer = t
        t.resume()
    }

    private func step() {
        let elapsed = CACurrentMediaTime() - startTime
        let t = min(1, elapsed / duration)
        // Ease-in-out for a premium feel.
        let e = t * t * (3 - 2 * t)
        currentPrimary = ColorValue.mix(fromPrimary, targetPrimary, e)
        currentSecondary = ColorValue.mix(fromSecondary, targetSecondary, e)
        onUpdate?()
        if t >= 1 { stop() }
    }

    private func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit { timer?.cancel() }
}
