import Accelerate
import Foundation

/// Instantaneous spectral features for one analysis frame.
struct AudioFeatures: Sendable, Equatable {
    var rms: Float = 0
    var bass: Float = 0       // 40–180 Hz normalized (soft-clipped, for visuals)
    var bassRaw: Float = 0    // 40–180 Hz raw band energy (for beat detection —
                              // NOT soft-clipped, so kick transients keep their ratio)
    var mids: Float = 0       // 180–2000 Hz
    var highs: Float = 0      // 2–8 kHz
    var spectralFlux: Float = 0
}

/// Windowed FFT + band energies via Accelerate (spec §14). Pure and testable:
/// feed it mono sample buffers, get features back. Not thread-safe by itself;
/// drive it from a single serial queue/actor.
final class AudioAnalyzer {
    let fftSize: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let hann: [Float]
    private var window = [Float]()
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    private var previousMagnitudes: [Float]

    init(fftSize: Int = 1024) {
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        var h = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&h, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.hann = h
        self.real = [Float](repeating: 0, count: fftSize / 2)
        self.imag = [Float](repeating: 0, count: fftSize / 2)
        self.magnitudes = [Float](repeating: 0, count: fftSize / 2)
        self.previousMagnitudes = [Float](repeating: 0, count: fftSize / 2)
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    /// Process one frame. `mono.count` should be >= fftSize; extra samples are ignored.
    func process(mono: [Float], sampleRate: Double) -> AudioFeatures {
        guard mono.count >= fftSize else { return AudioFeatures() }

        // RMS on the raw (unwindowed) frame.
        var rms: Float = 0
        vDSP_rmsqv(mono, 1, &rms, vDSP_Length(fftSize))

        // Apply Hann window.
        if window.count != fftSize { window = [Float](repeating: 0, count: fftSize) }
        vDSP_vmul(mono, 1, hann, 1, &window, 1, vDSP_Length(fftSize))

        // Real → split complex, forward FFT, magnitudes.
        magnitudes.withUnsafeMutableBufferPointer { mag in
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    window.withUnsafeBufferPointer { win in
                        win.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { cplx in
                            vDSP_ctoz(cplx, 2, &split, 1, vDSP_Length(fftSize / 2))
                        }
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, mag.baseAddress!, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        // Scale magnitudes.
        var scale = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))

        // Spectral flux: sum of positive changes vs. previous frame (spec §14).
        var flux: Float = 0
        for i in 0..<magnitudes.count {
            let d = magnitudes[i] - previousMagnitudes[i]
            if d > 0 { flux += d }
        }
        previousMagnitudes = magnitudes

        let binHz = Float(sampleRate) / Float(fftSize)
        func bandEnergy(_ lo: Float, _ hi: Float) -> Float {
            let a = max(1, Int(lo / binHz))
            let b = min(magnitudes.count - 1, Int(hi / binHz))
            guard b >= a else { return 0 }
            var sum: Float = 0
            vDSP_sve(Array(magnitudes[a...b]), 1, &sum, vDSP_Length(b - a + 1))
            return sum / Float(b - a + 1)
        }

        var f = AudioFeatures()
        // Perceptual gain: spectra are small; boost then soft-clip to 0…1.
        let bassBand = bandEnergy(40, 180)
        f.rms = softClip(rms * 6)
        f.bass = softClip(bassBand * 90)
        f.bassRaw = bassBand                      // unclipped: preserves transient ratio
        f.mids = softClip(bandEnergy(180, 2000) * 120)
        f.highs = softClip(bandEnergy(2000, 8000) * 160)
        f.spectralFlux = flux
        return f
    }

    private func softClip(_ x: Float) -> Float { 1 - expf(-max(0, x)) }
}
