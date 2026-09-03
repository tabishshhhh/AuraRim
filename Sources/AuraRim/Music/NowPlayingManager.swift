import Foundation
import AppKit

/// Chooses an active music source, polls it adaptively, and extracts album
/// colors only when the track identity changes (spec §50, §51, §52).
@MainActor
final class NowPlayingManager {
    private let providers: [MusicProvider]
    private var pollTask: Task<Void, Never>?
    private var lastSignature: String?
    private var colorCache = ColorCache()
    private var artworkSignature: String?
    private var artworkData: Data?

    /// Fired when the current track changes (or clears).
    var onTrack: ((TrackMetadata?) -> Void)?
    /// Fired with freshly extracted album colors.
    var onColors: (((primary: ColorValue, secondary: ColorValue)) -> Void)?

    init(providers: [MusicProvider] = [AppleMusicProvider(), SpotifyProvider()]) {
        self.providers = providers
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in await self?.loop() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func loop() async {
        while !Task.isCancelled {
            let track = await activeTrack()
            await handle(track)
            let interval = pollInterval(for: track)
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    /// Prefer a source that is actually playing; fall back to any running source.
    private func activeTrack() async -> TrackMetadata? {
        var fallback: TrackMetadata?
        for provider in providers where provider.isRunning() {
            if let t = await provider.currentTrack() {
                if t.playbackState == .playing { return t }
                if fallback == nil { fallback = t }
            }
        }
        return fallback
    }

    private func handle(_ track: TrackMetadata?) async {
        guard let track else {
            if lastSignature != nil { lastSignature = nil; artworkSignature = nil; artworkData = nil; onTrack?(nil) }
            return
        }
        let sig = track.signature

        // Emit the track with any artwork we already have for it.
        var enriched = track
        if sig == artworkSignature { enriched.artworkData = artworkData }
        onTrack?(enriched)

        guard sig != lastSignature else { return }
        lastSignature = sig

        // Track changed — fetch artwork once, then attach it + resolve colors.
        guard let provider = providers.first(where: { $0.bundleIdentifier == track.bundleIdentifier }),
              let data = await provider.artwork() else { return }
        artworkSignature = sig
        artworkData = data
        enriched.artworkData = data
        onTrack?(enriched)

        if let cached = colorCache.get(sig) { onColors?(cached); return }
        guard let image = NSImage(data: data)?.cgImageForColors(),
              let colors = ArtworkColorExtractor.extract(from: image) else { return }
        colorCache.set(sig, colors)
        onColors?(colors)
    }

    private func pollInterval(for track: TrackMetadata?) -> Double {
        guard let track else { return 8 }                 // no source: relaxed
        switch track.playbackState {
        case .playing: return 1
        case .paused: return 4
        case .stopped: return 8
        }
    }
}

/// Bounded LRU color cache keyed by track signature (spec §52).
private struct ColorCache {
    private var store: [String: (primary: ColorValue, secondary: ColorValue)] = [:]
    private var order: [String] = []
    private let limit = 200

    mutating func get(_ key: String) -> (primary: ColorValue, secondary: ColorValue)? {
        guard let v = store[key] else { return nil }
        touch(key)
        return v
    }

    mutating func set(_ key: String, _ value: (primary: ColorValue, secondary: ColorValue)) {
        store[key] = value
        touch(key)
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            store[oldest] = nil
        }
    }

    private mutating func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

extension NSImage {
    /// A CGImage suitable for color extraction.
    func cgImageForColors() -> CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
