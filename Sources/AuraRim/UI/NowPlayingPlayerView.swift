import SwiftUI
import AppKit

/// Actions for the now-playing window's controls.
struct PlayerActions {
    var playPause: () -> Void = {}
    var next: () -> Void = {}
    var prev: () -> Void = {}
    var seekBack: () -> Void = {}
    var seekForward: () -> Void = {}
    var toggleExpand: () -> Void = {}
    var close: () -> Void = {}
    var toggleAlbumColors: () -> Void = {}
    var cycleAnimation: () -> Void = {}
    var toggleRim: () -> Void = {}
    var openSettings: () -> Void = {}
}

/// The rich floating now-playing window (spec §23). Tap the cover to enlarge it
/// over the transport controls; toggle Lyrics for a side-by-side view; controls
/// expand into labeled pills on hover. Everything animates with springs.
struct NowPlayingPlayerView: View {
    @Bindable var state: AppState
    var isExpanded: Bool
    var actions: PlayerActions

    @State private var coverEnlarged = false

    private var showLyrics: Bool { state.playerShowLyrics }
    private var track: TrackMetadata? { state.currentTrack }
    private var isPlaying: Bool { track?.playbackState == .playing }
    private let contentSpring = Animation.spring(response: 0.45, dampingFraction: 0.82)

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                Group {
                    if showLyrics { lyricsLayout } else { centeredLayout }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                toolbar.padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
            closeButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 0 : 26, style: .continuous))
        .animation(contentSpring, value: showLyrics)
        .animation(contentSpring, value: coverEnlarged)
    }

    // MARK: Layouts

    private var centeredLayout: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            artwork
            if !coverEnlarged {
                titleBlock.transition(.opacity)
                transport.transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            lyricsButton
            Spacer(minLength: 12)
        }
    }

    private var lyricsLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                artwork
                if !coverEnlarged {
                    titleBlock.transition(.opacity)
                    transport.transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                lyricsButton
            }
            .frame(width: state.lyricsLeftWidth)
            resizeDivider
            LyricsView(state: state)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard(cornerRadius: 22)
                .overlay(alignment: .topTrailing) { styleMenu.padding(12) }
                .transition(.opacity)
        }
        .padding(.vertical, 18)
    }

    /// Drag to rebalance the player/lyrics split (spec §21: user's choice).
    /// Uses an AppKit-backed handle so it resizes instead of moving the window.
    private var resizeDivider: some View {
        ZStack {
            Capsule().fill(.white.opacity(0.18)).frame(width: 4, height: 48)
            ResizeHandle { dx in
                state.lyricsLeftWidth = min(360, max(150, state.lyricsLeftWidth + dx))
            }
        }
        .frame(width: 22)
    }

    /// Verci-inspired lyrics style switcher (Focus / Karaoke / Spotlight).
    private var styleMenu: some View {
        Menu {
            ForEach(LyricsStyle.allCases, id: \.self) { style in
                Button {
                    withAnimation(.smooth) { state.lyricsStyle = style }
                } label: {
                    Label(style.title, systemImage: style.symbol)
                }
            }
        } label: {
            Image(systemName: state.lyricsStyle.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.12), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Artwork (tap to enlarge over the controls)

    private var artSize: CGFloat {
        if showLyrics {
            return coverEnlarged ? state.lyricsLeftWidth : min(200, state.lyricsLeftWidth - 24)
        }
        if coverEnlarged { return isExpanded ? 520 : 430 }
        return isExpanded ? 360 : 300
    }

    private var artwork: some View {
        Group {
            if let data = track?.artworkData, let img = NSImage(data: data) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "music.note")
                        .font(.system(size: artSize * 0.28)).foregroundStyle(.secondary))
            }
        }
        .frame(width: artSize, height: artSize)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        .contentShape(Rectangle())
        .onTapGesture { coverEnlarged.toggle() }
        .help(coverEnlarged ? "Shrink" : "Enlarge")
    }

    private var titleBlock: some View {
        VStack(spacing: 5) {
            Text(track?.title ?? "Nothing playing")
                .font(.system(size: showLyrics ? 20 : 26, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(track?.artist ?? "")
                .font(.system(size: showLyrics ? 15 : 16))
                .foregroundStyle(.secondary).lineLimit(1)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
    }

    private var transport: some View {
        HStack(spacing: showLyrics ? 10 : 14) {
            if !showLyrics {
                HoverExpandButton(icon: "gobackward.15", label: "Back 15", action: actions.seekBack)
            }
            HoverExpandButton(icon: "backward.fill", label: "Previous", action: actions.prev)
            HoverExpandButton(icon: isPlaying ? "pause.fill" : "play.fill",
                              label: isPlaying ? "Pause" : "Play", prominent: true, action: actions.playPause)
            HoverExpandButton(icon: "forward.fill", label: "Next", action: actions.next)
            if !showLyrics {
                HoverExpandButton(icon: "goforward.15", label: "Forward 15", action: actions.seekForward)
            }
        }
    }

    private var lyricsButton: some View {
        Button { state.playerShowLyrics.toggle() } label: {
            Label(showLyrics ? "Hide Lyrics" : "Lyrics", systemImage: "quote.bubble")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background((showLyrics ? Color.accentColor.opacity(0.25) : .white.opacity(0.08)), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(showLyrics ? Color.accentColor : .white.opacity(0.9))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HoverExpandButton(icon: "paintpalette", label: "Colors",
                              active: !state.overrideAlbumColor, action: actions.toggleAlbumColors)
            HoverExpandButton(icon: "waveform", label: "Sync",
                              active: state.animationMode == .musicSync, action: actions.cycleAnimation)
            HoverExpandButton(icon: "lightbulb", label: "Rim",
                              active: state.rimEnabled, action: actions.toggleRim)
            HoverExpandButton(icon: "gearshape", label: "Settings", action: actions.openSettings)
            HoverExpandButton(icon: "arrow.up.left.and.arrow.down.right", label: "Full Screen",
                              action: actions.toggleExpand)
        }
    }

    private var backdrop: some View {
        let tint = (state.albumColors?.primary ?? state.primaryColor).color
        return RadialGradient(colors: [tint.opacity(0.35), .black],
                              center: .center, startRadius: 40, endRadius: 560)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: track?.signature)
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
