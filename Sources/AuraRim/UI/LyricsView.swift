import SwiftUI

/// Displays lyrics inside the player in the user's chosen `LyricsStyle`.
/// Synced lyrics highlight and auto-scroll; when the source provides real
/// per-word (YRC) timing, words light exactly as they're sung — matching Verci.
///
/// Smoothness: continuous styles tick at the display refresh rate (uncapped
/// `.animation`), each line is an `Equatable` subview so only the active line
/// recomputes per frame, and transitions use interruptible springs.
struct LyricsView: View {
    @Bindable var state: AppState

    @State private var lyrics: Lyrics?
    @State private var loading = true
    @State private var clock = PlaybackClock()

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
        .onChange(of: track?.playbackPosition ?? 0) { _, _ in syncClock() }
        .onChange(of: track?.playbackState) { _, _ in syncClock() }
    }

    private func syncClock() {
        guard let t = track else { return }
        clock.update(position: t.playbackPosition, playing: t.playbackState == .playing,
                     signature: t.signature)
    }

    @ViewBuilder private func content(_ lyrics: Lyrics) -> some View {
        if lyrics.isSynced {
            switch state.lyricsStyle {
            case .focus:     listView(lyrics, karaoke: false)
            case .karaoke:   listView(lyrics, karaoke: true)
            case .spotlight: spotlightView(lyrics)
            case .ship:      shipView(lyrics)
            case .fisheye:   fisheyeView(lyrics)
            case .visual:    visualView(lyrics)
            }
        } else {
            plainView(lyrics)
        }
    }

    // MARK: Focus / Karaoke (scrolling list)

    private func listView(_ lyrics: Lyrics, karaoke: Bool) -> some View {
        // Karaoke needs per-frame word fill → uncapped (vsync). Focus only needs
        // to notice line changes → a light cadence; the move itself is a spring.
        TimelineView(.animation(minimumInterval: karaoke ? 1.0 / 60.0 : 0.06)) { ctx in
            let now = estimatedTime(at: ctx.date)
            let active = activeIndex(lyrics, now)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { i, item in
                            LyricRow(text: item.text,
                                     attributed: (karaoke && i == active) ? karaokeAttributed(item, now: now) : nil,
                                     isActive: i == active)
                                .equatable()
                                .id(i)
                        }
                    }
                    .padding(.vertical, 130).padding(.horizontal, 6)
                }
                .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                     startPoint: .top, endPoint: .bottom))
                .onChange(of: active) { _, idx in
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
                        proxy.scrollTo(idx, anchor: UnitPoint(x: 0.5, y: 0.4))
                    }
                }
                .onAppear { proxy.scrollTo(active, anchor: UnitPoint(x: 0.5, y: 0.4)) }
            }
        }
    }

    // MARK: Spotlight (single centered line)

    private func spotlightView(_ lyrics: Lyrics) -> some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0)) { ctx in
            let now = estimatedTime(at: ctx.date)
            let active = activeIndex(lyrics, now)
            VStack(spacing: 26) {
                Spacer()
                if active - 1 >= 0 { faint(lyrics.lines[active - 1].text) }
                Text(karaokeAttributed(lyrics.lines[active], now: now))
                    .font(.system(size: 38, weight: .bold))
                    .multilineTextAlignment(.center)
                    .id(active)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
                if active + 1 < lyrics.lines.count { faint(lyrics.lines[active + 1].text) }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .animation(.spring(response: 0.5, dampingFraction: 0.9), value: active)
        }
    }

    private func faint(_ text: String) -> some View {
        Text(text.isEmpty ? "♪" : text)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white.opacity(0.22))
            .multilineTextAlignment(.center)
            .lineLimit(1)
    }

    // MARK: Ship (3D drifting wall of words — Verci "Ship")

    private func shipView(_ lyrics: Lyrics) -> some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0)) { ctx in
            let now = estimatedTime(at: ctx.date)
            let active = activeIndex(lyrics, now)
            let t = ctx.date.timeIntervalSinceReferenceDate
            let range = window(around: active, radius: 4, count: lyrics.lines.count)
            VStack(spacing: 18) {
                ForEach(range, id: \.self) { i in
                    let d = i - active
                    let drift = sin(t * 0.6 + Double(i)) * 8
                    let text = lyrics.lines[i].text
                    Group {
                        if i == active {
                            Text(karaokeAttributed(lyrics.lines[i], now: now))
                                .font(.system(size: 34, weight: .heavy))
                        } else {
                            Text(text.isEmpty ? "♪" : text)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white.opacity(max(0.12, 0.6 - Double(abs(d)) * 0.14)))
                        }
                    }
                    .multilineTextAlignment(.center)
                    .offset(x: drift)
                    .rotation3DEffect(.degrees(Double(d) * 9),
                                      axis: (x: 1, y: 0.15, z: 0), perspective: 0.6)
                    .scaleEffect(i == active ? 1.0 : max(0.6, 1 - Double(abs(d)) * 0.12))
                    .blur(radius: i == active ? 0 : Double(abs(d)) * 0.7)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: active)
        }
    }

    // MARK: Fisheye (convex lens stack — Verci "Fisheye")

    private func fisheyeView(_ lyrics: Lyrics) -> some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0)) { ctx in
            let now = estimatedTime(at: ctx.date)
            let active = activeIndex(lyrics, now)
            let range = window(around: active, radius: 4, count: lyrics.lines.count)
            ZStack {
                VStack(spacing: 10) {
                    ForEach(range, id: \.self) { i in
                        let d = Double(i - active)
                        let lens = 1.0 / (1.0 + 0.16 * d * d)
                        let text = lyrics.lines[i].text
                        Group {
                            if i == active {
                                Text(karaokeAttributed(lyrics.lines[i], now: now))
                                    .font(.system(size: 40, weight: .heavy))
                            } else {
                                Text(text.isEmpty ? "♪" : text)
                                    .font(.system(size: 40, weight: .heavy))
                                    .foregroundStyle(.white.opacity(0.28 * lens + 0.06))
                            }
                        }
                        .multilineTextAlignment(.center)
                        .scaleEffect(lens, anchor: .center)
                        .offset(y: d * 6 * lens)
                        .blur(radius: (1 - lens) * 3)
                    }
                }
                .frame(maxWidth: .infinity)
                RadialGradient(colors: [.white.opacity(0.10), .clear],
                               center: .center, startRadius: 4, endRadius: 240)
                    .allowsHitTesting(false)
                    .blendMode(.plusLighter)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.5, dampingFraction: 0.9), value: active)
        }
    }

    // MARK: Visual (each word paired with an SF Symbol — Verci "Visual")

    private func visualView(_ lyrics: Lyrics) -> some View {
        TimelineView(.animation(minimumInterval: 0.05)) { ctx in
            let now = estimatedTime(at: ctx.date)
            let active = activeIndex(lyrics, now)
            let line = lyrics.lines[active]
            let words = line.words ?? line.text.split(separator: " ").map {
                LyricWord(time: line.time ?? 0, duration: 0, text: String($0))
            }
            VStack(spacing: 22) {
                Spacer()
                FlowLayout(spacing: 16, lineSpacing: 22) {
                    ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                        let lit = now >= w.time
                        VStack(spacing: 6) {
                            if let sym = LyricSymbolMap.symbol(for: w.text) {
                                Image(systemName: sym)
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(lit ? Color.accentColor : .white.opacity(0.25))
                                    .scaleEffect(lit ? 1 : 0.6)
                                    .opacity(lit ? 1 : 0.4)
                            }
                            Text(w.text.trimmingCharacters(in: .whitespaces))
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(lit ? .white : .white.opacity(0.3))
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: lit)
                    }
                }
                if active + 1 < lyrics.lines.count { faint(lyrics.lines[active + 1].text) }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .animation(.spring(response: 0.5, dampingFraction: 0.88), value: active)
        }
    }

    // MARK: Plain (unsynced)

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

    private func activeIndex(_ lyrics: Lyrics, _ now: TimeInterval) -> Int {
        lyrics.lines.lastIndex { ($0.time ?? .infinity) <= now } ?? 0
    }

    private func window(around active: Int, radius: Int, count: Int) -> [Int] {
        let lo = max(0, active - radius)
        let hi = min(count - 1, active + radius)
        return lo <= hi ? Array(lo...hi) : []
    }

    /// Highlighted text for a line. Uses real per-word (YRC) timing when present;
    /// otherwise approximates by filling characters across the line's duration.
    /// Each word eases dim→bright over a short window so lighting glides.
    private func karaokeAttributed(_ line: LyricLine, now: TimeInterval) -> AttributedString {
        if let words = line.words, !words.isEmpty {
            var a = AttributedString()
            for w in words {
                var seg = AttributedString(w.text)
                let lit = smoothstep(w.time - 0.06, w.time + 0.14, now)
                seg.foregroundColor = .white.opacity(0.28 + 0.72 * lit)
                a += seg
            }
            return a
        }
        let p = lineProgress(line, now: now)
        return partialFill(line.text.isEmpty ? "♪" : line.text, progress: p)
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private func partialFill(_ text: String, progress: Double) -> AttributedString {
        var a = AttributedString(text)
        let n = max(0, min(text.count, Int((Double(text.count) * progress).rounded())))
        let mid = a.index(a.startIndex, offsetByCharacters: n)
        a[a.startIndex..<mid].foregroundColor = .white
        a[mid..<a.endIndex].foregroundColor = .white.opacity(0.3)
        return a
    }

    private func lineProgress(_ line: LyricLine, now: TimeInterval) -> Double {
        guard let l = lyrics, let start = line.time,
              let i = l.lines.firstIndex(where: { $0.id == line.id }) else { return 0 }
        let end = (i + 1 < l.lines.count ? l.lines[i + 1].time : nil) ?? (start + 4)
        guard end > start else { return 1 }
        return min(1, max(0, (now - start) / (end - start)))
    }

    private func estimatedTime(at date: Date) -> TimeInterval { clock.currentTime }

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

/// One lyric line. `Equatable` so SwiftUI skips re-rendering unchanged lines on
/// every animation frame — only the active line (whose `attributed` fill or
/// `isActive` flag changes) is recomputed.
private struct LyricRow: View, Equatable {
    let text: String
    let attributed: AttributedString?   // non-nil only for the active karaoke line
    let isActive: Bool

    nonisolated static func == (l: LyricRow, r: LyricRow) -> Bool {
        l.isActive == r.isActive && l.text == r.text && l.attributed == r.attributed
    }

    var body: some View {
        Group {
            if let attributed {
                Text(attributed).font(.system(size: 30, weight: .bold))
            } else {
                Text(text.isEmpty ? "♪" : text)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(isActive ? 1.0 : 0.96, anchor: .leading)
        .padding(.vertical, 13)
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: isActive)
    }
}

/// Minimal wrapping flow layout (words wrap to new rows). Used by the Visual and
/// Ambient styles; macOS 14 `Layout` protocol, no third-party dependency.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for item in row.items {
                let size = subviews[item].sizeThatFits(.unspecified)
                subviews[item].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                     proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func layout(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let add = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty, add > maxWidth {
                rows.append(row); row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
