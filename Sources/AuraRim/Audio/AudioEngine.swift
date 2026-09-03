import Foundation
import QuartzCore

/// Runs the DSP chain on the capture queue and publishes normalized
/// `AnimationState` into the bus. Never touches the main actor.
final class AudioProcessor: @unchecked Sendable {
    private let bus: AnimationStateBus
    private let analyzer: AudioAnalyzer
    private let beat = BeatDetector()
    private var beatEnv = EnvelopeFollower(attack: 0.01, release: 0.25)
    private var ampEnv = EnvelopeFollower(attack: 0.05, release: 0.30)
    private var silenceEnv = EnvelopeFollower(attack: 0.6, release: 1.2)
    private let fftSize: Int
    private let hop: Int
    private var buffer = [Float]()
    private var lastTime = CACurrentMediaTime()
    private let startTime = CACurrentMediaTime()

    init(bus: AnimationStateBus, fftSize: Int = 1024) {
        self.bus = bus
        self.fftSize = fftSize
        self.hop = fftSize / 2
        self.analyzer = AudioAnalyzer(fftSize: fftSize)
    }

    /// Called from the capture serial queue.
    func feed(_ mono: [Float], sampleRate: Double) {
        buffer.append(contentsOf: mono)
        while buffer.count >= fftSize {
            let frame = Array(buffer[0..<fftSize])
            buffer.removeFirst(hop)

            let now = CACurrentMediaTime()
            let dt = Float(min(0.1, max(0.001, now - lastTime)))
            lastTime = now

            let f = analyzer.process(mono: frame, sampleRate: sampleRate)
            let rawBeat = beat.process(bass: f.bass, flux: f.spectralFlux, dt: dt)

            var state = AnimationState()
            state.beat = beatEnv.impulse(rawBeat, dt: dt, decay: 0.25)
            state.amplitude = ampEnv.update(target: f.rms, dt: dt)
            state.bass = f.bass
            state.mids = f.mids
            state.highs = f.highs
            let silenceTarget: Float = f.rms < 0.02 ? 1 : 0
            state.silence = silenceEnv.update(target: silenceTarget, dt: dt)
            state.elapsedTime = Float(now - startTime)
            bus.store(state)
        }
        // Bound memory if the consumer stalls.
        if buffer.count > fftSize * 8 { buffer.removeFirst(buffer.count - fftSize) }
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
        bus.store(.idle)
    }
}

/// Main-actor orchestrator for audio capture + analysis (spec §13, §39).
/// Starts capture only when Music Sync needs it; stops otherwise to save power.
@MainActor
final class AudioEngine {
    let bus = AnimationStateBus()
    private let processor: AudioProcessor
    private var capture: SystemAudioCapture?
    private(set) var isRunning = false
    private(set) var permission: PermissionState = .unknown
    var onPermissionChange: ((PermissionState) -> Void)?

    init() {
        processor = AudioProcessor(bus: bus)
    }

    /// Non-prompting refresh (safe to call at launch).
    func refreshPermission() {
        let state: PermissionState = SystemAudioCapture.permissionGranted() ? .granted : .denied
        if state != permission { permission = state; onPermissionChange?(state) }
    }

    /// Start capture. Pass `promptIfNeeded: true` only from an explicit user
    /// action (onboarding button / warning banner) so the system dialog is never
    /// sprung at launch.
    func start(promptIfNeeded: Bool = false) async {
        guard !isRunning else { return }
        var granted = SystemAudioCapture.permissionGranted()
        if !granted && promptIfNeeded { granted = SystemAudioCapture.requestPermission() }
        permission = granted ? .granted : .denied
        onPermissionChange?(permission)
        guard granted else {
            Log.audio.notice("Audio permission not granted; staying in idle visuals")
            return
        }
        let processor = self.processor
        let capture = SystemAudioCapture(sink: { mono, sr in processor.feed(mono, sampleRate: sr) })
        do {
            try await capture.start()
            self.capture = capture
            isRunning = true
        } catch {
            Log.audio.error("Failed to start capture: \(error.localizedDescription)")
            permission = .denied
            onPermissionChange?(permission)
        }
    }

    func stop() async {
        guard isRunning || capture != nil else { return }
        await capture?.stop()
        capture = nil
        processor.reset()
        isRunning = false
    }
}
