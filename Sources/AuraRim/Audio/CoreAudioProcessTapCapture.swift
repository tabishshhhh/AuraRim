import Foundation
import CoreAudio

/// Abstraction over a system-audio source. Both the CoreAudio process tap
/// (primary) and ScreenCaptureKit (fallback) conform, so `AudioEngine` can pick
/// the best available path without the DSP chain caring which one is live.
protocol AudioCapturing: AnyObject, Sendable {
    var sampleRate: Double { get }
    func start() async throws
    func stop() async
}

/// Low-latency system-audio capture via CoreAudio **Process Taps** (macOS 14.4+).
/// This is the purpose-built, audio-only path (spec §13): a private tap on the
/// global output mix, routed through a private aggregate device and read with a
/// bare HAL IOProc. Versus ScreenCaptureKit it has lower, steadier latency
/// (direct HAL callbacks, not tied to screen refresh) — so beats land on time —
/// and a lighter audio-only permission. Emits mono Float frames to a sink; never
/// the microphone.
///
/// The IOProc runs on a real-time audio thread and nothing here touches the main
/// actor, so `@unchecked Sendable` is safe.
@available(macOS 14.4, *)
final class CoreAudioProcessTapCapture: AudioCapturing, @unchecked Sendable {
    private let sink: @Sendable ([Float], Double) -> Void
    private(set) var sampleRate: Double = 48_000

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioDeviceID(0)
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "com.aurarim.tap-io", qos: .userInteractive)

    init(sink: @escaping @Sendable ([Float], Double) -> Void) {
        self.sink = sink
    }

    func start() async throws {
        // 1. Private mono global tap; original audio keeps playing (unmuted).
        let desc = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.name = "AuraRim Tap"
        desc.muteBehavior = .unmuted
        desc.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(desc, &tap), "create process tap")
        guard tap != kAudioObjectUnknown else {
            throw err("process tap not created (permission not granted yet)")
        }
        tapID = tap

        // 2. Tap format → sample rate.
        if let asbd = try? tapFormat(tap), asbd.mSampleRate > 0 { sampleRate = asbd.mSampleRate }

        // 3. Private aggregate: a REAL output device as main sub-device, with the
        //    tap riding as a sub-tap. (Tap-as-main with no sub-device = silence.)
        let outputUID = try defaultOutputDeviceUID()
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AuraRim Tap Aggregate",
            kAudioAggregateDeviceUIDKey: "com.aurarim.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: desc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        var agg = AudioDeviceID(0)
        try check(AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &agg), "create aggregate device")
        aggregateID = agg

        // 4. Bare HAL IOProc (AVAudioEngine silently ignores tap aggregates).
        let sink = self.sink
        let sr = self.sampleRate
        var proc: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, agg, ioQueue) { _, inInputData, _, _, _ in
            CoreAudioProcessTapCapture.emit(inInputData, sampleRate: sr, to: sink)
        }, "create IO proc")
        guard let proc else { throw err("IO proc not created") }
        ioProcID = proc
        try check(AudioDeviceStart(agg, proc), "start device")
        Log.audio.info("CoreAudio process tap started @ \(self.sampleRate, format: .fixed(precision: 0)) Hz")
    }

    func stop() async {
        // Cleanup order matters: stop & destroy the proc, then aggregate, then tap.
        if let proc = ioProcID {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
            ioProcID = nil
        }
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = 0 }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = kAudioObjectUnknown }
        Log.audio.info("CoreAudio process tap stopped")
    }

    // MARK: IO callback

    private static func emit(_ inInputData: UnsafePointer<AudioBufferList>, sampleRate: Double,
                             to sink: @Sendable ([Float], Double) -> Void) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
        guard let buf = abl.first, let data = buf.mData else { return }
        let channels = max(1, Int(buf.mNumberChannels))
        let totalFloats = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
        guard totalFloats > 0 else { return }
        let ptr = data.assumingMemoryBound(to: Float.self)

        if channels == 1 || abl.count > 1 {
            // Mono buffer (our tap), or non-interleaved: channel 0 is enough.
            let mono = Array(UnsafeBufferPointer(start: ptr, count: totalFloats))
            sink(mono, sampleRate)
        } else {
            // Interleaved multi-channel: average down to mono.
            let frames = totalFloats / channels
            var mono = [Float](repeating: 0, count: frames)
            for f in 0..<frames {
                var s: Float = 0
                for c in 0..<channels { s += ptr[f * channels + c] }
                mono[f] = s / Float(channels)
            }
            sink(mono, sampleRate)
        }
    }

    // MARK: Property helpers

    private func tapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &asbd), "tap format")
        return asbd
    }

    private func defaultOutputDeviceUID() throws -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var devID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                             &addr, 0, nil, &size, &devID), "default output device")

        addr.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(devID, &addr, 0, nil, &uidSize, &uid), "output device uid")
        guard let cf = uid?.takeRetainedValue() else { throw err("output device has no UID") }
        return cf as String
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw err("\(what) failed (OSStatus \(status))") }
    }

    private func err(_ message: String) -> NSError {
        NSError(domain: "AuraRim.CoreAudioTap", code: -1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
