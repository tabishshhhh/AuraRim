import SwiftUI
import Combine

/// Full-screen ambient lyrics for the lock/idle experience: big, centered,
/// word-by-word lyrics with a glowing album-colored rim that gently breathes and
/// pulses with the beat.
///
/// This is the *compliant* lock-screen display. macOS does not allow any app to
/// draw on the true secure lock screen, so — like Verci — AuraRim shows this
/// full-screen window when the screen locks or the screensaver starts.
struct AmbientLyricsView: View {
    @Bindable var state: AppState

    @State private var lyrics: Lyrics?
    @State private var loading = true
    @State private var clock = PlaybackClock()
    @State private var breathe = false
    @State private var beatLevel: Double = 0

    // Low-rate poll of the audio bus. Drives only the rim's opacity/scale (cheap
    // GPU transforms on the cached ring) — never a per-frame redraw of the glow.
    private let beatTimer = Timer.publish(every: 1.0 / 24.0, on: .main, in: .common).autoconnect()

    private var track: TrackMetadata? { state.currentTrack }
    private var colors: (primary: ColorValue, secondary: ColorValue) { state.targetColors }

    // Performance: the background and glow ring are STATIC siblings — rendered
    // once and cached, never re-run by the lyrics timeline. Only the lyrics word
    // fill animates, in a low-rate TimelineView. (An earlier version re-rendered
    // the whole full-screen view — glow + shadows — at 60fps and pinned the CPU
    // at ~100%, which glitched the whole app and dropped frames that blanked the
    // rim's bottom edge.)
    var body: some View {
        ZStack {
            background
            glowRim.allowsHitTesting(false)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                lyricsContent(now: clock.currentTime)
                    .padding(.horizontal, 90)
                    .frame(maxWidth: 1150)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .ignoresSafeArea()
        .task(id: track?.signature) { await load() }
        .onChange(of: track?.playbackPosition ?? 0) { _, _ in sync() }
        .onChange(of: track?.playbackState) { _, _ in sync() }
        .onReceive(beatTimer) { _ in
            let a = state.animationBus?.load() ?? .idle
            let target = Double(min(1, a.beat * 0.9 + a.amplitude * 0.25))
            beatLevel += (target - beatLevel) * 0.5   // light smoothing
        }
    }

    // MARK: Background
    //
    // Static (no per-frame parameters) so it rasterizes once and is cached —
    // recomputing a full-screen gradient every frame is needless CPU.

    private var background: some View {
        RadialGradient(colors: [colors.primary.color.opacity(0.28), .black],
                       center: .center, startRadius: 40, endRadius: 760)
    }

    // MARK: Glowing rim
    //
    // Album-colored glow built from concentric strokes (widest+faintest →
    // narrow+bright) that fake a soft bloom over the black background — NO
    // blur/shadow/blendMode/drawingGroup, all of which re-rasterize the full
    // screen every frame and pegged the CPU at ~100%. The strokes are constant,
    // so Core Animation caches them; only cheap `.opacity`/`.scaleEffect`
    // transforms animate — a slow breathe plus a beat flash from `beatLevel`.
    private var glowRim: some View {
        let p = colors.primary.color
        let s = colors.secondary.color
        let shape = RoundedRectangle(cornerRadius: 46, style: .continuous)
        let ring = LinearGradient(colors: [p, s, p], startPoint: .topLeading, endPoint: .bottomTrailing)
        let layers: [(w: CGFloat, o: Double)] = [(32, 0.06), (24, 0.09), (17, 0.14),
                                                 (11, 0.22), (6, 0.4), (3, 0.8), (1.5, 1.0)]
        return ZStack {
            // Base ring: gentle continuous breathe (implicit GPU animation).
            ZStack {
                ForEach(layers.indices, id: \.self) { i in
                    shape.stroke(ring, lineWidth: layers[i].w).opacity(layers[i].o)
                }
            }
            .opacity(breathe ? 1.0 : 0.72)
            .scaleEffect(breathe ? 1.006 : 1.0)

            // Beat flash: a brighter copy whose opacity/scale ride the beat.
            ZStack {
                shape.stroke(ring, lineWidth: 9).opacity(0.5)
                shape.stroke(ring, lineWidth: 3)
            }
            .opacity(beatLevel * 0.85)
            .scaleEffect(1.0 + beatLevel * 0.01)
        }
        .padding(18)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    // MARK: Lyrics

    @ViewBuilder private func lyricsContent(now: TimeInterval) -> some View {
        if let lyrics, !lyrics.lines.isEmpty {
            let active = lyrics.lines.lastIndex { ($0.time ?? .infinity) <= now } ?? 0
            VStack(spacing: 36) {
                if active - 1 >= 0 { neighbor(lyrics.lines[active - 1].text) }
                activeLine(lyrics.lines[active], now: now)
                if active + 1 < lyrics.lines.count { neighbor(lyrics.lines[active + 1].text) }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.9), value: active)
        } else if !loading, let track {
            VStack(spacing: 16) {
                Text(track.title).font(.system(size: 58, weight: .heavy))
                Text(track.artist).font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
        } else {
            ProgressView().controlSize(.large).tint(.white)
        }
    }

    private func neighbor(_ text: String) -> some View {
        Text(text.isEmpty ? "♪" : text)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.white.opacity(0.22))
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder private func activeLine(_ line: LyricLine, now: TimeInterval) -> some View {
        if let words = line.words, !words.isEmpty {
            let activeIdx = words.lastIndex { $0.time <= now } ?? 0
            FlowLayout(spacing: 18, lineSpacing: 12) {
                ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                    wordView(w, isActive: i == activeIdx, now: now)
                }
            }
        } else {
            Text(line.text.isEmpty ? "♪" : line.text)
                .font(.system(size: 60, weight: .heavy))
                .foregroundStyle(colors.primary.color)
                .multilineTextAlignment(.center)
        }
    }

    private func wordView(_ w: LyricWord, isActive: Bool, now: TimeInterval) -> some View {
        let lit = smoothstep(w.time - 0.06, w.time + 0.16, now)
        let base = colors.primary.color
        let word = w.text.trimmingCharacters(in: .whitespaces)
        return Text(word.isEmpty ? "♪" : word)
            // Uniform size keeps the line from reflowing; the active word grows
            // via a (layout-free) scale + glow so it "pops" like the reference.
            .font(.system(size: 56, weight: .heavy))
            .foregroundStyle(isActive ? .white : base.opacity(0.3 + 0.6 * lit))
            .scaleEffect(isActive ? 1.14 : 1.0)
            .shadow(color: isActive ? base.opacity(0.9) : .clear, radius: isActive ? 20 : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isActive)
    }

    // MARK: Helpers

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private func sync() {
        guard let t = track else { return }
        clock.update(position: t.playbackPosition, playing: t.playbackState == .playing,
                     signature: t.signature)
    }

    private func load() async {
        guard let track else { loading = false; lyrics = nil; return }
        loading = true; lyrics = nil
        clock.update(position: track.playbackPosition, playing: track.playbackState == .playing,
                     signature: track.signature)
        lyrics = await LyricsProvider.fetch(title: track.title, artist: track.artist,
                                            album: track.album, duration: track.duration)
        loading = false
    }
}
