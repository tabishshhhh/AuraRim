import SwiftUI

/// Displays lyrics inside the player, in the user's chosen `LyricsStyle`
/// (Focus / Karaoke / Spotlight). Synced lyrics highlight and auto-scroll;
/// plain lyrics scroll freely.
struct LyricsView: View {
    @Bindable var state: AppState

    @State private var lyrics: Lyrics?
    @State private var loading = true
    @State private var basePosition: TimeInterval = 0
    @State private var baseDate = Date()

    private var track: TrackMetadata? { state.currentTrack }

    var body: some View {
        Group {
            if loading {
                ProgressView().controlSize(.large)
            } else if let lyrics, !lyrics.lines.isEmpty {
                content(lyrics)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "quote.bubble").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Lyrics unavailable").foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: track?.signature) { await load() }
        .onChange(of: track?.playbackPosition ?? 0) { _, pos in
            basePosition = pos; baseDate = Date()
        }
    }

    @ViewBuilder private func content(_ lyrics: Lyrics) -> some View {
        if lyrics.isSynced {
            switch state.lyricsStyle {
            case .focus:     listView(lyrics, karaoke: false)
            case .karaoke:   listView(lyrics, karaoke: true)
            case .spotlight: spotlightView(lyrics)
            }
        } else {
            plainView(lyrics)
        }
    }

    // MARK: Focus / Karaoke (scrolling list)

    private func listView(_ lyrics: Lyrics, karaoke: Bool) -> some View {
        TimelineView(.animation(minimumInterval: karaoke ? 0.03 : 0.1)) { ctx in
            let now = estimatedTime(at: ctx.date)
            let active = lyrics.lines.lastIndex { ($0.time ?? .infinity) <= now } ?? 0
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { i, item in
                            lineRow(text: item.text, active: i == active,
                                    karaoke: karaoke,
                                    progress: karaoke && i == active ? progress(lyrics, i, now) : 0)
                                .id(i)
                        }
                    }
                    .padding(.vertical, 130).padding(.horizontal, 6)
                }
                .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                     startPoint: .top, endPoint: .bottom))
                .onChange(of: active) { _, idx in
                    withAnimation(.smooth(duration: 0.55)) { proxy.scrollTo(idx, anchor: .center) }
                }
                .onAppear { proxy.scrollTo(active, anchor: .center) }
            }
        }
    }

    private func lineRow(text: String, active: Bool, karaoke: Bool, progress: Double) -> some View {
        Group {
            if active && karaoke {
                Text(karaokeAttributed(text, progress: progress))
                    .font(.system(size: 30, weight: .heavy))
            } else {
                Text(text.isEmpty ? "♪" : text)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(active ? .white : .white.opacity(0.26))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(active ? 1.0 : 0.85, anchor: .leading)
        .padding(.vertical, 10)
        .animation(.smooth(duration: 0.35), value: active)
    }

    // MARK: Spotlight (single centered line)

    private func spotlightView(_ lyrics: Lyrics) -> some View {
        TimelineView(.animation(minimumInterval: 0.05)) { ctx in
            let now = estimatedTime(at: ctx.date)
            let active = lyrics.lines.lastIndex { ($0.time ?? .infinity) <= now } ?? 0
            VStack(spacing: 26) {
                Spacer()
                if active - 1 >= 0 { faint(lyrics.lines[active - 1].text) }
                Text(lyrics.lines[active].text.isEmpty ? "♪" : lyrics.lines[active].text)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .id(active)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
                if active + 1 < lyrics.lines.count { faint(lyrics.lines[active + 1].text) }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .animation(.smooth(duration: 0.45), value: active)
        }
    }

    private func faint(_ text: String) -> some View {
        Text(text.isEmpty ? "♪" : text)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white.opacity(0.22))
            .multilineTextAlignment(.center)
            .lineLimit(1)
    }

    private func plainView(_ lyrics: Lyrics) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(lyrics.lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
    }

    // MARK: Helpers

    /// Per-character fill for the active karaoke line, approximating word timing
    /// from the line's duration (lrclib provides line-level timings).
    private func karaokeAttributed(_ text: String, progress: Double) -> AttributedString {
        var a = AttributedString(text)
        let n = max(0, min(text.count, Int((Double(text.count) * progress).rounded())))
        let mid = a.index(a.startIndex, offsetByCharacters: n)
        a[a.startIndex..<mid].foregroundColor = .white
        a[mid..<a.endIndex].foregroundColor = .white.opacity(0.3)
        return a
    }

    /// Fraction 0…1 through the active line, based on the gap to the next line.
    private func progress(_ lyrics: Lyrics, _ i: Int, _ now: TimeInterval) -> Double {
        guard let start = lyrics.lines[i].time else { return 0 }
        let end = (i + 1 < lyrics.lines.count ? lyrics.lines[i + 1].time : nil) ?? (start + 4)
        guard end > start else { return 1 }
        return min(1, max(0, (now - start) / (end - start)))
    }

    private func estimatedTime(at date: Date) -> TimeInterval {
        guard track?.playbackState == .playing else { return basePosition }
        return basePosition + date.timeIntervalSince(baseDate)
    }

    private func load() async {
        guard let track else { loading = false; lyrics = nil; return }
        loading = true; lyrics = nil
        basePosition = track.playbackPosition; baseDate = Date()
        lyrics = await LyricsProvider.fetch(title: track.title, artist: track.artist,
                                            album: track.album, duration: track.duration)
        loading = false
    }
}
