import Metal
import MetalKit

/// Shared Metal engine: one device / pipeline reused across every display's view
/// (spec §9: one reusable rendering engine feeding multiple displays).
/// Objects are created once and then only read, so `@unchecked Sendable` is safe.
final class MetalRenderer: @unchecked Sendable {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            Log.rendering.error("No Metal device available")
            return nil
        }
        self.device = device
        self.commandQueue = queue
        do {
            let library = try device.makeLibrary(source: RimShaderSource.metal, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "rim_vertex")
            desc.fragmentFunction = library.makeFunction(name: "rim_fragment")
            let att = desc.colorAttachments[0]!
            att.pixelFormat = Self.pixelFormat
            // Premultiplied-alpha compositing over the transparent window.
            att.isBlendingEnabled = true
            att.rgbBlendOperation = .add
            att.alphaBlendOperation = .add
            att.sourceRGBBlendFactor = .one
            att.sourceAlphaBlendFactor = .one
            att.destinationRGBBlendFactor = .oneMinusSourceAlpha
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            Log.rendering.error("Pipeline build failed: \(error.localizedDescription)")
            return nil
        }
    }
}
