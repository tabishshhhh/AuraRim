import AppKit
import SwiftUI

/// Owns the optional floating now-playing window (spec §23): draggable,
/// translucent, remembers its position, and expands to fill the screen when the
/// artwork is tapped.
@MainActor
final class NowPlayingController {
    private let appState: AppState
    private var panel: NSPanel?
    private var hosting: NSHostingController<NowPlayingPlayerView>?
    private var isExpanded = false
    private var compactFrame = CGRect(x: 0, y: 0, width: 720, height: 600)
    private let frameKey = "playerWindowFrameCompact"

    /// Set by AppDelegate to open the Settings window from the player toolbar.
    var onOpenSettings: () -> Void = {}

    init(appState: AppState) { self.appState = appState }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        if panel == nil { build() }
        panel?.setFrame(isExpanded ? expandedFrame() : compactFrame, display: true)
        panel?.orderFrontRegardless()
    }

    func hide() {
        if let panel, !isExpanded { compactFrame = panel.frame; saveFrame() }
        panel?.orderOut(nil)
    }

    // MARK: Build

    private func build() {
        restoreFrame()
        let panel = NSPanel(contentRect: compactFrame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingController(rootView: makeView())
        panel.contentViewController = hosting
        self.panel = panel
        self.hosting = hosting

        NotificationCenter.default.addObserver(
            self, selector: #selector(didMove), name: NSWindow.didMoveNotification, object: panel)
    }

    private func makeView() -> NowPlayingPlayerView {
        var a = PlayerActions()
        a.playPause = { [weak self] in self?.transport(.playPause) }
        a.next = { [weak self] in self?.transport(.next) }
        a.prev = { [weak self] in self?.transport(.previous) }
        a.seekBack = { [weak self] in self?.seek(-15) }
        a.seekForward = { [weak self] in self?.seek(15) }
        a.toggleExpand = { [weak self] in self?.toggleExpand() }
        a.close = { [weak self] in self?.hide() }
        a.toggleAlbumColors = { [weak self] in self?.appState.overrideAlbumColor.toggle() }
        a.cycleAnimation = { [weak self] in self?.cycleAnimation() }
        a.toggleRim = { [weak self] in self?.appState.rimEnabled.toggle() }
        a.openSettings = { [weak self] in self?.onOpenSettings() }
        return NowPlayingPlayerView(state: appState, isExpanded: isExpanded, actions: a)
    }

    private func seek(_ seconds: Int) {
        guard let id = appState.currentTrack?.bundleIdentifier else { return }
        Task { await MusicControl.seek(by: seconds, bundleIdentifier: id) }
    }

    private func cycleAnimation() {
        let all = AnimationMode.allCases
        if let i = all.firstIndex(of: appState.animationMode) {
            appState.animationMode = all[(i + 1) % all.count]
        }
    }

    private func toggleExpand() {
        guard let panel else { return }
        if !isExpanded { compactFrame = panel.frame; saveFrame() }
        isExpanded.toggle()
        hosting?.rootView = makeView()
        panel.setFrame(isExpanded ? expandedFrame() : compactFrame, display: true, animate: true)
    }

    private func expandedFrame() -> CGRect {
        (panel?.screen ?? NSScreen.main)?.visibleFrame ?? compactFrame
    }

    private func transport(_ c: MusicControl.Command) {
        guard let id = appState.currentTrack?.bundleIdentifier else { return }
        Task { await MusicControl.send(c, bundleIdentifier: id) }
    }

    // MARK: Frame persistence

    @objc private func didMove() {
        guard let panel, !isExpanded else { return }
        compactFrame = panel.frame
        saveFrame()
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(compactFrame), forKey: frameKey)
    }

    private func restoreFrame() {
        if let s = UserDefaults.standard.string(forKey: frameKey) {
            let r = NSRectFromString(s)
            if r.width > 100 && r.height > 100 { compactFrame = r; return }
        }
        // Default: centered on the main screen.
        if let vf = NSScreen.main?.visibleFrame {
            let w: CGFloat = 720, h: CGFloat = 600
            compactFrame = CGRect(x: vf.midX - w / 2, y: vf.midY - h / 2, width: w, height: h)
        }
    }
}
