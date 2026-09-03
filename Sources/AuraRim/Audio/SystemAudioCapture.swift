import Foundation
import ScreenCaptureKit
import CoreMedia
import AVFoundation
import CoreGraphics

/// Captures audio produced by the Mac itself via ScreenCaptureKit (spec §13).
/// This is *system* audio — never the microphone. Emits mono Float frames to a
/// sink. Requires the Screen & System Audio Recording permission.
///
/// The capture callback runs on a background queue; nothing here touches the
/// main actor, so `@unchecked Sendable` is safe.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.aurarim.audiocapture")
    private let sink: @Sendable ([Float], Double) -> Void
    private(set) var sampleRate: Double = 48_000

    init(sink: @escaping @Sendable ([Float], Double) -> Void) {
        self.sink = sink
    }

    /// Non-prompting permission check (does not show the system dialog).
    static func permissionGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Explicitly request permission (shows the system dialog once).
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "AuraRim", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display to attach audio capture to."])
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(sampleRate)
        config.channelCount = 2
        // Keep the video path minimal — we only want audio.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        Log.audio.info("System audio capture started")
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        Log.audio.info("System audio capture stopped")
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        do {
            try sampleBuffer.withAudioBufferList { buffers, _ in
                guard let first = buffers.first, let data = first.mData else { return }
                let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
                let ptr = data.assumingMemoryBound(to: Float.self)
                // ScreenCaptureKit delivers non-interleaved Float32; channel 0 is
                // enough for energy/beat analysis.
                var mono = [Float](repeating: 0, count: count)
                for i in 0..<count { mono[i] = ptr[i] }
                if !mono.isEmpty { sink(mono, sampleRate) }
            }
        } catch {
            Log.audio.error("Audio buffer read failed")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.audio.error("Audio stream stopped with error: \(error.localizedDescription)")
    }
}
