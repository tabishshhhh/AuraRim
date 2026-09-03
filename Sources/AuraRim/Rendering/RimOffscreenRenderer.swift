import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

/// Renders a single rim frame to a PNG offscreen — no window required. Used by
/// the `--render-test` debug flag for deterministic visual QA (spec §56), and
/// handy for verifying the shader without an unlocked display.
enum RimOffscreenRenderer {
    /// Render the rim over an opaque dark background so the glow and the
    /// transparent interior are both visible in the output image.
    static func renderPNG(to path: String, width: Int, height: Int,
                          config: RimConfig, notch: NotchGeometry) -> Bool {
        guard let engine = MetalRenderer() else {
            FileHandle.standardError.write(Data("Metal unavailable\n".utf8)); return false
        }
        let device = engine.device

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalRenderer.pixelFormat, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: texDesc),
              let cmd = engine.commandQueue.makeCommandBuffer() else { return false }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        var u = uniforms(width: width, height: height, config: config, notch: notch)
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return false }
        enc.setRenderPipelineState(engine.pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<RimUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        return writePNG(texture: texture, width: width, height: height, path: path)
    }

    private static func uniforms(width: Int, height: Int,
                                 config c: RimConfig, notch: NotchGeometry) -> RimUniforms {
        let scale = Float(c.scale)
        var u = RimUniforms()
        u.resolution = SIMD2(Float(width), Float(height))
        u.rimThickness = Float(c.thicknessPoints) * scale
        u.glowRadius = (3 + Float(c.glow) / 100 * 90) * scale
        u.brightness = 0.2 + Float(c.brightness) / 100 * 1.4
        u.opacity = 1
        u.gradientMix = Float(c.colorBalance) / 100
        u.cornerRadius = Float(c.cornerRadiusPoints) * scale
        u.primaryColor = c.primary.simd
        u.secondaryColor = c.secondary.simd
        u.animationMode = 2      // static, deterministic
        if notch.hasNotch {
            u.notchEnabled = 1
            u.notchCenterX = Float(notch.centerX) * scale
            u.notchWidth = Float(notch.width) * scale
            u.notchHeight = Float(notch.height) * scale
        }
        return u
    }

    /// Composite the premultiplied result over dark grey, into an opaque PNG.
    private static func writePNG(texture: MTLTexture, width: Int, height: Int, path: String) -> Bool {
        let rowBytes = width * 4
        var raw = [UInt8](repeating: 0, count: rowBytes * height)
        texture.getBytes(&raw, bytesPerRow: rowBytes,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        // Texture is BGRA premultiplied. Composite over 0.08 grey → RGBA8 opaque.
        let bg: Float = 0.08 * 255
        var out = [UInt8](repeating: 0, count: rowBytes * height)
        for i in stride(from: 0, to: raw.count, by: 4) {
            let b = Float(raw[i]), g = Float(raw[i+1]), r = Float(raw[i+2]), a = Float(raw[i+3]) / 255
            out[i]   = UInt8(min(255, r + bg * (1 - a)))   // R
            out[i+1] = UInt8(min(255, g + bg * (1 - a)))   // G
            out[i+2] = UInt8(min(255, b + bg * (1 - a)))   // B
            out[i+3] = 255
        }

        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return false }

        let url = URL(fileURLWithPath: path) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest)
    }
}
