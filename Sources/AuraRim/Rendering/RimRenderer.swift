import MetalKit
import QuartzCore

/// Per-display `MTKViewDelegate`. Runs on the view's draw callback, reads a
/// lock-protected `RimConfig` and the audio bus, builds uniforms and draws the
/// rim. Never touches main-actor/UI state, so it's safe off the main actor.
final class RimRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let engine: MetalRenderer
    private let configBox: Locked<RimConfig>
    private let audioBus: AnimationStateBus
    private let startTime = CACurrentMediaTime()

    init(engine: MetalRenderer, config: RimConfig, audioBus: AnimationStateBus) {
        self.engine = engine
        self.configBox = Locked(config)
        self.audioBus = audioBus
    }

    func update(config: RimConfig) { configBox.value = config }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let cmd = engine.commandQueue.makeCommandBuffer() else { return }

        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].loadAction = .clear

        var u = uniforms(drawableSize: view.drawableSize)
        if let enc = cmd.makeRenderCommandEncoder(descriptor: pass) {
            enc.setRenderPipelineState(engine.pipeline)
            enc.setFragmentBytes(&u, length: MemoryLayout<RimUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Audio/config → uniforms (spec §37 mapping)

    private func uniforms(drawableSize: CGSize) -> RimUniforms {
        let c = configBox.value
        let a = audioBus.load()
        let scale = Float(c.scale)
        let elapsed = Float(CACurrentMediaTime() - startTime)

        var u = RimUniforms()
        u.resolution = SIMD2(Float(drawableSize.width), Float(drawableSize.height))
        u.time = elapsed
        u.rimThickness = Float(c.thicknessPoints) * scale
        let glowPoints = 3 + Float(c.glow) / 100 * 90
        u.glowRadius = glowPoints * scale
        u.brightness = 0.2 + Float(c.brightness) / 100 * 1.4
        u.opacity = 1
        u.gradientMix = Float(c.colorBalance) / 100
        u.cornerRadius = Float(c.cornerRadiusPoints) * scale
        u.gradientRotation = elapsed * 0.01
        u.idlePhase = elapsed * 0.9

        // Resolved, mid-transition colors come straight from the config.
        u.primaryColor = c.primary.simd
        u.secondaryColor = c.secondary.simd

        u.animationMode = Int32(c.animationMode.rawValue)
        if c.animationMode == .musicSync {
            // Weight the transient beat harder than the smoothed amplitude so the
            // rim snaps on the beat rather than trailing the volume envelope.
            u.pulseStrength = min(1, a.beat * 1.05 + a.amplitude * 0.22)
            u.silence = a.silence
        }

        if c.notchEnabled && c.notch.hasNotch {
            u.notchEnabled = 1
            u.notchCenterX = Float(c.notch.centerX) * scale
            u.notchWidth = Float(c.notch.width) * scale
            u.notchHeight = Float(c.notch.height) * scale
        }
        return u
    }
}
