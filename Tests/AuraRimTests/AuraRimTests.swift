import XCTest
import CoreGraphics
@testable import AuraRim

final class BeatDetectorTests: XCTestCase {
    func testSilenceProducesNoBeat() {
        let d = BeatDetector()
        for _ in 0..<100 {
            XCTAssertEqual(d.process(bass: 0, flux: 0, dt: 0.02), 0)
        }
    }

    func testKickTransientFires() {
        let d = BeatDetector()
        // Establish a low baseline.
        for _ in 0..<50 { _ = d.process(bass: 0.05, flux: 0.1, dt: 0.02) }
        // A sudden bass+flux spike should register as a beat.
        let strength = d.process(bass: 0.9, flux: 1.5, dt: 0.2)
        XCTAssertGreaterThan(strength, 0)
    }

    func testCooldownSuppressesDoubleTrigger() {
        let d = BeatDetector()
        for _ in 0..<50 { _ = d.process(bass: 0.05, flux: 0.1, dt: 0.02) }
        let first = d.process(bass: 0.9, flux: 1.5, dt: 0.2)
        let immediate = d.process(bass: 0.9, flux: 1.5, dt: 0.01) // within cooldown
        XCTAssertGreaterThan(first, 0)
        XCTAssertEqual(immediate, 0)
    }
}

final class AudioAnalyzerTests: XCTestCase {
    func testSilenceHasLowEnergy() {
        let a = AudioAnalyzer(fftSize: 1024)
        let f = a.process(mono: [Float](repeating: 0, count: 1024), sampleRate: 48_000)
        XCTAssertEqual(f.rms, 0, accuracy: 0.001)
        XCTAssertLessThan(f.bass, 0.05)
    }

    func testBassSineHasBassEnergy() {
        let a = AudioAnalyzer(fftSize: 1024)
        let sr = 48_000.0, hz = 100.0
        let samples = (0..<1024).map { Float(sin(2 * Double.pi * hz * Double($0) / sr)) }
        let f = a.process(mono: samples, sampleRate: sr)
        XCTAssertGreaterThan(f.bass, 0.1)
        XCTAssertGreaterThan(f.rms, 0.1)
    }
}

final class EnvelopeTests: XCTestCase {
    func testImpulseDecays() {
        var e = EnvelopeFollower()
        let peak = e.impulse(1.0, dt: 0.0, decay: 0.25)
        let later = e.impulse(0.0, dt: 0.25, decay: 0.25)
        XCTAssertEqual(peak, 1.0, accuracy: 0.001)
        XCTAssertLessThan(later, peak)
        XCTAssertGreaterThan(later, 0)
    }
}

final class ColorTests: XCTestCase {
    func testOKLabMidpoint() {
        let mid = ColorValue.mix(.vibrantViolet, .coolBlue, 0.5)
        XCTAssertGreaterThan(mid.b, 0.4)             // stays blue-ish, not grey
        XCTAssertGreaterThan(mid.r, 0.1)
    }

    func testExtractSolidColor() throws {
        let img = try makeSolidImage(r: 0.8, g: 0.2, b: 0.6)
        let colors = try XCTUnwrap(ArtworkColorExtractor.extract(from: img))
        // Primary should be reddish-magenta; secondary distinct.
        XCTAssertGreaterThan(colors.primary.r, colors.primary.g)
        XCTAssertNotEqual(colors.primary, colors.secondary)
    }

    private func makeSolidImage(r: CGFloat, g: CGFloat, b: CGFloat) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        return try XCTUnwrap(ctx.makeImage())
    }
}

final class PreferencesTests: XCTestCase {
    func testRoundTrip() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "AuraRimTests.\(UUID().uuidString)"))
        let prefs = Preferences(suite)
        prefs.set(true, .rimEnabled)
        prefs.set(22.0, .thickness)
        prefs.set(ColorValue(r: 0.1, g: 0.2, b: 0.3), .primaryColor)
        XCTAssertEqual(prefs.bool(.rimEnabled), true)
        XCTAssertEqual(prefs.double(.thickness), 22.0)
        XCTAssertEqual(prefs.color(.primaryColor, default: .coolBlue).g, 0.2, accuracy: 0.001)
    }
}

final class TrackIdentityTests: XCTestCase {
    func testSignatureChangesWithTrack() {
        let base = TrackMetadata(title: "A", artist: "B", album: "C", duration: 1, playbackPosition: 0,
                                 playbackState: .playing, bundleIdentifier: "id", sourceName: "S", artworkData: nil)
        var other = base; other.title = "Z"
        XCTAssertNotEqual(base.signature, other.signature)
        var samePosition = base; samePosition.playbackPosition = 30
        XCTAssertEqual(base.signature, samePosition.signature)   // position must not change identity
    }
}

final class PlaybackClockTests: XCTestCase {
    func testPausedHoldsPosition() {
        var c = PlaybackClock()
        c.update(position: 30, playing: false, signature: "a")
        XCTAssertEqual(c.currentTime, 30, accuracy: 0.01)
    }

    func testSeekReanchors() {
        var c = PlaybackClock()
        c.update(position: 30, playing: false, signature: "a")
        c.update(position: 90, playing: false, signature: "a")   // big jump = seek
        XCTAssertEqual(c.currentTime, 90, accuracy: 0.01)
    }

    func testTrackChangeReanchors() {
        var c = PlaybackClock()
        c.update(position: 60, playing: false, signature: "a")
        c.update(position: 0, playing: false, signature: "b")    // new track
        XCTAssertEqual(c.currentTime, 0, accuracy: 0.01)
    }

    func testPlayingAdvances() {
        var c = PlaybackClock()
        c.update(position: 10, playing: true, signature: "a")
        XCTAssertGreaterThanOrEqual(c.currentTime, 10)
    }
}

final class LicenseStateTests: XCTestCase {
    func testIsActive() {
        XCTAssertTrue(LicenseState.active(key: "k").isActive)
        XCTAssertFalse(LicenseState.unactivated.isActive)
        XCTAssertFalse(LicenseState.invalid(reason: "x").isActive)
    }
}
