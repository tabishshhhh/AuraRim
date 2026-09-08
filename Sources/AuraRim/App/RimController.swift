import AppKit
import Observation

/// The conductor: turns user-facing `AppState` into live overlays, colors, audio
/// and now-playing behavior, and keeps them all reconciled (spec §62, §63).
/// Nothing high-frequency runs through here — only structural/settings changes.
@MainActor
final class RimController {
    let appState: AppState
    private let displayManager = DisplayManager()
    private let overlays: DisplayOverlayController
    private let colorEngine: ColorTransitionEngine
    private let audio = AudioEngine()
    private let nowPlaying = NowPlayingManager()
    private let engine: MetalRenderer

    private var lastAudioDesired = false

    init?(appState: AppState) {
        self.appState = appState
        guard let engine = MetalRenderer() else { return nil }
        self.engine = engine
        self.overlays = DisplayOverlayController(engine: engine, audioBus: audio.bus)
        let colors = appState.targetColors
        self.colorEngine = ColorTransitionEngine(primary: colors.primary, secondary: colors.secondary)

        configureCallbacks()
        appState.displays = displayManager.displays
        ensureDefaultSelection()
        observe()
        nowPlaying.start()
        audio.refreshPermission()
    }

    // MARK: Wiring

    private func configureCallbacks() {
        colorEngine.onUpdate = { [weak self] in self?.rebuild() }

        displayManager.onChange = { [weak self] displays in
            guard let self else { return }
            self.appState.displays = displays
            self.ensureDefaultSelection()
            self.rebuild()
        }

        audio.onPermissionChange = { [weak self] state in
            self?.appState.audioPermission = state
        }

        nowPlaying.onTrack = { [weak self] track in
            self?.appState.currentTrack = track
        }
        nowPlaying.onColors = { [weak self] colors in
            guard let self else { return }
            self.appState.albumColors = colors
            if !self.appState.overrideAlbumColor {
                self.colorEngine.transition(to: colors.primary, secondary: colors.secondary, duration: 0.7)
            }
        }

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(willSleep),
                             name: NSWorkspace.willSleepNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(didWake),
                             name: NSWorkspace.didWakeNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(willSleep),
                             name: NSWorkspace.screensDidSleepNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(didWake),
                             name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    /// If nothing is selected yet, light up the built-in (or first) display.
    private func ensureDefaultSelection() {
        let available = Set(appState.displays.map(\.uuid))
        let current = appState.selectedDisplayUUIDs.intersection(available)
        if current.isEmpty, let first = appState.displays.first(where: \.isBuiltIn) ?? appState.displays.first {
            appState.selectedDisplayUUIDs = [first.uuid]
        }
    }

    // MARK: Observation → rebuild

    private func observe() {
        withObservationTracking {
            _ = (appState.rimEnabled, appState.animationMode, appState.gradientMode, appState.thickness,
                 appState.glow, appState.brightness, appState.colorBalance,
                 appState.overrideAlbumColor, appState.primaryColor, appState.secondaryColor,
                 appState.notchEnabled, appState.showOverFullscreen, appState.selectedDisplayUUIDs)
            rebuild()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    /// Push current settings + colors into overlays and reconcile audio.
    private func rebuild() {
        // Resolve desired colors and glide toward them.
        let target = appState.targetColors
        colorEngine.transition(to: target.primary, secondary: target.secondary, duration: 0.6)

        overlays.sync(displays: appState.displays,
                      selectedUUIDs: appState.selectedDisplayUUIDs,
                      rimEnabled: appState.rimEnabled,
                      showOverFullscreen: appState.showOverFullscreen,
                      config: { [colorEngine, appState] display in
            RimConfig(
                enabled: appState.rimEnabled,
                thicknessPoints: appState.thickness,
                glow: appState.glow,
                brightness: appState.brightness,
                colorBalance: appState.colorBalance,
                primary: colorEngine.currentPrimary,
                secondary: colorEngine.currentSecondary,
                animationMode: appState.animationMode,
                notchEnabled: appState.notchEnabled,
                notch: display.notch,
                scale: display.scale,
                cornerRadiusPoints: display.isBuiltIn ? 12 : 4)
        })

        reconcileAudio()
    }

    /// Start capture only when Music Sync actually needs it (spec §39).
    private func reconcileAudio() {
        let desired = appState.rimEnabled && appState.animationMode == .musicSync
        guard desired != lastAudioDesired else { return }
        lastAudioDesired = desired
        // Music Sync needs system audio: prompt once when the user selects it.
        // With stable code signing the grant persists, so this asks at most once.
        Task { desired ? await audio.start(promptIfNeeded: true) : await audio.stop() }
    }

    // MARK: Sleep / wake

    @objc private func willSleep() {
        overlays.setPaused(true)
        Task { await audio.stop() }
    }

    @objc private func didWake() {
        overlays.setPaused(false)
        rebuild()
    }

    // MARK: Lifecycle

    func requestAudioPermissionFlow() {
        Task {
            await audio.start(promptIfNeeded: true)   // explicit user action → prompt once
            // If macOS won't show the dialog (already denied), guide to Settings.
            if appState.audioPermission == .denied { SystemSettingsPane.openScreenRecording() }
        }
    }

    func teardown() {
        nowPlaying.stop()
        overlays.teardown()
        Task { await audio.stop() }
    }
}
