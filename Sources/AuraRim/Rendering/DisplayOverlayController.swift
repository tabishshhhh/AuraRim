import AppKit
import MetalKit

/// Owns one overlay window + renderer per selected display and keeps them in
/// sync with display topology and settings (spec §7, §20, §40). All UI/window
/// work stays on the main actor.
@MainActor
final class DisplayOverlayController {
    private let engine: MetalRenderer
    private let audioBus: AnimationStateBus

    private struct Overlay {
        let window: OverlayWindow
        let view: MTKView
        let renderer: RimRenderer
    }
    private var overlays: [String: Overlay] = [:]   // keyed by display UUID
    private var showOverFullscreen = false

    init(engine: MetalRenderer, audioBus: AnimationStateBus) {
        self.engine = engine
        self.audioBus = audioBus
    }

    /// Reconcile live overlays against the desired set. `config(for:)` builds the
    /// appearance snapshot for a display. Creating/destroying is incremental so a
    /// single display disappearing only tears down its own renderer (spec §46).
    func sync(displays: [DisplayInfo],
              selectedUUIDs: Set<String>,
              rimEnabled: Bool,
              showOverFullscreen: Bool,
              config: (DisplayInfo) -> RimConfig) {
        self.showOverFullscreen = showOverFullscreen
        let wanted: [DisplayInfo] = rimEnabled
            ? displays.filter { selectedUUIDs.contains($0.uuid) }
            : []
        let wantedUUIDs = Set(wanted.map(\.uuid))

        // Remove overlays no longer wanted or whose display vanished.
        for (uuid, overlay) in overlays where !wantedUUIDs.contains(uuid) {
            overlay.window.orderOut(nil)
            overlay.window.close()
            overlays[uuid] = nil
        }

        // Add / update the rest.
        for display in wanted {
            let cfg = config(display)
            if let existing = overlays[display.uuid] {
                existing.window.setFrame(display.frame, display: true)
                existing.renderer.update(config: cfg)
            } else {
                let window = OverlayWindow(display: display, showOverFullscreen: showOverFullscreen)
                let view = window.makeMetalView(device: engine.device, refreshRate: display.refreshRate)
                let renderer = RimRenderer(engine: engine, config: cfg, audioBus: audioBus)
                view.delegate = renderer
                window.orderFrontRegardless()
                overlays[display.uuid] = Overlay(window: window, view: view, renderer: renderer)
                Log.rendering.info("Created overlay for display \(display.name, privacy: .public)")
            }
        }
    }

    /// Push updated appearance to every live overlay without rebuilding windows.
    func updateConfigs(config: (String) -> RimConfig?) {
        for (uuid, overlay) in overlays {
            if let cfg = config(uuid) { overlay.renderer.update(config: cfg) }
        }
    }

    func setPaused(_ paused: Bool) {
        for overlay in overlays.values { overlay.view.isPaused = paused }
    }

    func teardown() {
        for overlay in overlays.values {
            overlay.window.orderOut(nil)
            overlay.window.close()
        }
        overlays.removeAll()
    }

    var activeDisplayUUIDs: Set<String> { Set(overlays.keys) }
}
