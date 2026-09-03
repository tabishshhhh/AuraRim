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
    private var compactFrame = CGRect(x: 0, y: 0, width: 300, height: 430)
    private let frameKey = "playerWindowFrameCompact"

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
        NowPlayingPlayerView(
            state: appState,
            isExpanded: isExpanded,
            onToggleExpand: { [weak self] in self?.toggleExpand() },
            onClose: { [weak self] in self?.hide() },
            onPlayPause: { [weak self] in self?.transport(.playPause) },
            onNext: { [weak self] in self?.transport(.next) },
            onPrev: { [weak self] in self?.transport(.previous) })
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
        // Default: upper-right of the main screen.
        if let vf = NSScreen.main?.visibleFrame {
            compactFrame = CGRect(x: vf.maxX - 320, y: vf.maxY - 450, width: 300, height: 430)
        }
    }
}
