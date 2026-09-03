import SwiftUI

/// Floating now-playing player (spec §23). Compact by default; tap the artwork
/// to expand it to fill the screen with a large cover + blurred backdrop.
struct NowPlayingPlayerView: View {
    @Bindable var state: AppState
    var isExpanded: Bool
    var onToggleExpand: () -> Void
    var onClose: () -> Void
    var onPlayPause: () -> Void
    var onNext: () -> Void
    var onPrev: () -> Void

    private var track: TrackMetadata? { state.currentTrack }

    var body: some View {
        ZStack {
            backdrop
            content
            closeButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 0 : 18, style: .continuous))
    }

    @ViewBuilder private var backdrop: some View {
        if let img = artworkImage {
            Image(nsImage: img)
                .resizable().aspectRatio(contentMode: .fill)
                .blur(radius: 60).opacity(0.55)
                .overlay(Color.black.opacity(isExpanded ? 0.35 : 0.2))
                .ignoresSafeArea()
        }
    }

    private var content: some View {
        VStack(spacing: isExpanded ? 28 : 16) {
            Spacer(minLength: 0)
            artwork
                .frame(width: artSize, height: artSize)
                .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 20 : 12, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleExpand)
                .help(isExpanded ? "Shrink" : "Fill screen")

            VStack(spacing: 4) {
                Text(track?.title ?? "Nothing playing")
                    .font(isExpanded ? .largeTitle.bold() : .headline)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(track?.artist ?? "")
                    .font(isExpanded ? .title3 : .subheadline)
                    .foregroundStyle(.secondary).lineLimit(1)
                if let track, !track.album.isEmpty {
                    Text(track.album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)

            controls
            Spacer(minLength: 0)
        }
        .padding(isExpanded ? 40 : 20)
        .foregroundStyle(.primary)
    }

    private var controls: some View {
        HStack(spacing: isExpanded ? 40 : 26) {
            transport("backward.fill", action: onPrev)
            transport(track?.playbackState == .playing ? "pause.fill" : "play.fill",
                      big: true, action: onPlayPause)
            transport("forward.fill", action: onNext)
        }
    }

    private func transport(_ symbol: String, big: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: big ? (isExpanded ? 46 : 30) : (isExpanded ? 30 : 20),
                              weight: .medium))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).padding(12)
            }
            Spacer()
        }
    }

    @ViewBuilder private var artwork: some View {
        if let img = artworkImage {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                .overlay(Image(systemName: "music.note").font(.system(size: artSize * 0.3))
                    .foregroundStyle(.secondary))
        }
    }

    private var artworkImage: NSImage? {
        guard let data = track?.artworkData else { return nil }
        return NSImage(data: data)
    }

    private var artSize: CGFloat {
        isExpanded ? min(460, NSScreen.main.map { $0.frame.height * 0.42 } ?? 420) : 240
    }
}
