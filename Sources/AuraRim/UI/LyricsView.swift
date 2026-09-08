import SwiftUI

/// Displays lyrics inside the player. Synced lyrics highlight and auto-scroll to
/// the current line; plain lyrics scroll freely.
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
            TimelineView(.animation(minimumInterval: 0.15)) { ctx in
                let now = estimatedTime(at: ctx.date)
                let activeIndex = lyrics.lines.lastIndex { ($0.time ?? .infinity) <= now }
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { i, line in
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.system(size: 21, weight: i == activeIndex ? .bold : .semibold))
                                    .foregroundStyle(i == activeIndex ? .white : .white.opacity(0.32))
                                    .blur(radius: i == activeIndex ? 0 : 0.3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .animation(.easeInOut(duration: 0.3), value: activeIndex)
                                    .id(i)
                            }
                        }
                        .padding(.vertical, 90).padding(.horizontal, 4)
                    }
                    .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .onChange(of: activeIndex) { _, idx in
                        if let idx { withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                            proxy.scrollTo(idx, anchor: .center)
                        } }
                    }
                }
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(lyrics.lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
            }
        }
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
