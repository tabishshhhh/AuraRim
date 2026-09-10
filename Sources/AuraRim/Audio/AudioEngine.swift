import Foundation
import QuartzCore

/// Runs the DSP chain on the capture queue and publishes normalized
/// `AnimationState` into the bus. Never touches the main actor.
final class AudioProcessor: @unchecked Sendable {
    private let bus: AnimationStateBus
    private let analyzer: AudioAnalyzer
    private let beat = BeatDetector(cooldown: 0.10, sensitivity: 1.3, fluxThreshold: 0.4)
    private var beatEnv = EnvelopeFollower(attack: 0.01, release: 0.25)
    private var ampEnv = EnvelopeFollower(attack: 0.05, release: 0.30)
    private var silenceEnv = EnvelopeFollower(attack: 0.6, release: 1.2)
    private let fftSize: Int
    private let hop: Int
    private var buffer = [Float]()
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
        // Latency: keep at most a couple of hops queued so the visuals track the
        // audio the user hears rather than a growing backlog.
        let maxBacklog = fftSize + hop * 2
        if buffer.count > maxBacklog { buffer.removeFirst(buffer.count - maxBacklog) }

        while buffer.count >= fftSize {
            let frame = Array(buffer[0..<fftSize])
            buffer.removeFirst(hop)

            // Use audio-time dt (not wall clock) so cooldown/decay stay accurate
            // even when a large capture chunk is processed in one burst.
            let dt = Float(hop) / Float(sampleRate)

            let f = analyzer.process(mono: frame, sampleRate: sampleRate)
            let rawBeat = beat.process(bass: f.bass, flux: f.spectralFlux, dt: dt)

            var state = AnimationState()
            state.beat = beatEnv.impulse(rawBeat, dt: dt, decay: 0.16)
            state.amplitude = ampEnv.update(target: f.rms, dt: dt)
            state.bass = f.bass
            state.mids = f.mids
            state.highs = f.highs
            let silenceTarget: Float = f.rms < 0.02 ? 1 : 0
            state.silence = silenceEnv.update(target: silenceTarget, dt: dt)
            state.elapsedTime = Float(CACurrentMediaTime() - startTime)
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
        // CGPreflight can lag behind the real grant, so we don't hard-gate on it.
        // Trigger the system prompt only on an explicit user action, then let
        // ScreenCaptureKit be the real gate: if permission is truly granted the
        // capture starts even when preflight still reports false.
        if promptIfNeeded && !SystemAudioCapture.permissionGranted() {
            _ = SystemAudioCapture.requestPermission()
        }
        let processor = self.processor
        let capture = SystemAudioCapture(sink: { mono, sr in processor.feed(mono, sampleRate: sr) })
        do {
            try await capture.start()
            self.capture = capture
            isRunning = true
            permission = .granted
            onPermissionChange?(permission)
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
