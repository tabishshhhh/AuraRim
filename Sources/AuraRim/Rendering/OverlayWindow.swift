import AppKit
import MetalKit

/// A borderless, transparent, click-through overlay panel that covers one
/// display (spec §7). Implemented as a non-activating `NSPanel` so it never
/// becomes key/main and never steals focus.
final class OverlayWindow: NSPanel {
    init(display: DisplayInfo, showOverFullscreen: Bool) {
        super.init(contentRect: display.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true          // click-through (spec §7)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        level = showOverFullscreen
            ? NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            : .screenSaver

        // Stay attached to the display across Spaces without acting like a
        // normal window (spec §42).
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
        setFrame(display.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func makeMetalView(device: MTLDevice, refreshRate: Double) -> MTKView {
        let view = TransparentMTKView(frame: CGRect(origin: .zero, size: frame.size), device: device)
        view.colorPixelFormat = MetalRenderer.pixelFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.autoResizeDrawable = true
        view.preferredFramesPerSecond = min(Int(refreshRate.rounded()), 120)
        view.wantsLayer = true
        view.layer?.isOpaque = false
        if let metalLayer = view.layer as? CAMetalLayer {
            metalLayer.isOpaque = false
            metalLayer.backgroundColor = NSColor.clear.cgColor
        }
        contentView = view
        return view
    }
}

/// MTKView reports itself opaque to AppKit by default, which makes the window
/// server composite it opaquely and ignore the alpha channel — blacking out the
/// display. Overriding `isOpaque` lets the transparent rim composite correctly.
final class TransparentMTKView: MTKView {
    override var isOpaque: Bool { false }
}
