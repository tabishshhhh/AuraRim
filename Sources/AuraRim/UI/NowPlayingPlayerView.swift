import SwiftUI

/// Actions for the now-playing window's controls.
struct PlayerActions {
    var playPause: () -> Void = {}
    var next: () -> Void = {}
    var prev: () -> Void = {}
    var seekBack: () -> Void = {}
    var seekForward: () -> Void = {}
    var toggleExpand: () -> Void = {}
    var close: () -> Void = {}
    // Bottom toolbar
    var toggleAlbumColors: () -> Void = {}
    var cycleAnimation: () -> Void = {}
    var toggleRim: () -> Void = {}
    var openSettings: () -> Void = {}
}

/// The rich floating now-playing window (spec §23), matched to the reference:
/// large rounded artwork on an album-tinted backdrop, five transport controls,
/// a Lyrics pill, and a bottom toolbar of quick actions.
struct NowPlayingPlayerView: View {
    @Bindable var state: AppState
    var isExpanded: Bool
    var actions: PlayerActions

    @State private var hovering = false
    private var track: TrackMetadata? { state.currentTrack }
    private var isPlaying: Bool { track?.playbackState == .playing }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                Spacer(minLength: isExpanded ? 40 : 24)
                artwork
                Spacer().frame(height: 22)
                titleBlock
                Spacer().frame(height: 22)
                transport
                Spacer().frame(height: 18)
                lyricsButton
                Spacer(minLength: isExpanded ? 40 : 24)
                toolbar
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
            closeButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 0 : 16, style: .continuous))
    }

    // Album-tinted radial backdrop (like the reference's colored glow).
    private var backdrop: some View {
        let tint = (state.albumColors?.primary ?? state.primaryColor).color
        return RadialGradient(colors: [tint.opacity(0.35), .black],
                              center: .center, startRadius: 40, endRadius: 520)
            .ignoresSafeArea()
    }

    private var artSize: CGFloat {
        isExpanded ? min(460, (NSScreen.main?.frame.height ?? 900) * 0.4) : 300
    }

    private var artwork: some View {
        ZStack {
            if let data = track?.artworkData, let img = NSImage(data: data) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "music.note")
                        .font(.system(size: artSize * 0.28)).foregroundStyle(.secondary))
            }
            if hovering {
                Color.black.opacity(0.25)
                Button(action: actions.playPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 74, height: 74)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
                }.buttonStyle(.plain)
            }
        }
        .frame(width: artSize, height: artSize)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        .onHover { hovering = $0 }
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text(track?.title ?? "Nothing playing")
                .font(.system(size: isExpanded ? 34 : 26, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(track?.artist ?? "")
                .font(.system(size: isExpanded ? 20 : 16))
                .foregroundStyle(.secondary).lineLimit(1)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
    }

    private var transport: some View {
        HStack(spacing: isExpanded ? 34 : 26) {
            circleButton("gobackward.15", size: 20, action: actions.seekBack)
            circleButton("backward.fill", size: 22, action: actions.prev)
            circleButton(isPlaying ? "pause.fill" : "play.fill", size: 28, big: true, action: actions.playPause)
            circleButton("forward.fill", size: 22, action: actions.next)
            circleButton("goforward.15", size: 20, action: actions.seekForward)
        }
    }

    private var lyricsButton: some View {
        Button(action: {}) {
            Label("Lyrics", systemImage: "quote.bubble")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        }
        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.9))
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            toolButton("paintpalette", on: !state.overrideAlbumColor, action: actions.toggleAlbumColors)
            toolButton("waveform", on: state.animationMode == .musicSync, action: actions.cycleAnimation)
            toolButton("lightbulb", on: state.rimEnabled, action: actions.toggleRim)
            Button(action: actions.openSettings) {
                Text("Settings").font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.white.opacity(0.08), in: Capsule())
            }.buttonStyle(.plain).foregroundStyle(.white)
            toolButton("display", on: false, action: actions.toggleExpand)
        }
        .foregroundStyle(.white)
    }

    // MARK: pieces

    private func circleButton(_ symbol: String, size: CGFloat, big: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: big ? 62 : 48, height: big ? 62 : 48)
                .background(.white.opacity(big ? 0.14 : 0.08), in: Circle())
        }.buttonStyle(.plain)
    }

    private func toolButton(_ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(on ? Color.accentColor : .white.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.08), in: Circle())
        }.buttonStyle(.plain)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: actions.close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.white.opacity(0.6))
                }.buttonStyle(.plain).padding(14)
            }
            Spacer()
        }
    }
}
