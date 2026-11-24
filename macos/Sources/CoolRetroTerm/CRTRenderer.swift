import CoreGraphics
import Foundation
import Metal
import QuartzCore

/// Uniforms shared by every CRT pass. Must match `CRTUniforms` in
/// Shaders/CRT.metal field for field (Swift SIMD types use the same size and
/// alignment as their Metal counterparts).
struct CRTUniforms {
    var fontColor = SIMD4<Float>(1, 1, 1, 1)
    var backgroundColor = SIMD4<Float>(0, 0, 0, 1)
    var frameColor = SIMD4<Float>(0, 0, 0, 1)
    var contentRect = SIMD4<Float>(0, 0, 1, 1)
    var viewportSize = SIMD2<Float>(1, 1)
    var virtualResolution = SIMD2<Float>(1, 1)
    var jitterDisplacement = SIMD2<Float>(0, 0)
    var noiseScale = SIMD2<Float>(1, 1)
    var time: Float = 0
    var staticNoise: Float = 0
    var glowingLine: Float = 0
    var chromaColor: Float = 0
    var jitter: Float = 0
    var horizontalSync: Float = 0
    var horizontalSyncStrength: Float = 0
    var flickering: Float = 0
    var burnIn: Float = 0
    var burnInTime: Float = 1
    var burnInLastUpdate: Float = 0
    var burnInPrevUpdate: Float = 0
    var rasterization: Float = 0
    var rasterizationIntensity: Float = 0
    var screenCurvature: Float = 0
    var rgbShift: Float = 0
    var bloom: Float = 0
    var brightness: Float = 1
    var frameSize: Float = 0
    var frameShininess: Float = 0
    var screenRadius: Float = 0
    var ambientLight: Float = 0
    var pixelated: Float = 0
}

enum CRTRendererError: Error {
    case setupFailed(String)
}

/// Runs the CRT pipeline on a snapshot of the terminal:
///
///   terminal snapshot -> burn-in accumulation (when the text changes)
///                     -> dynamic pass (noise, jitter, sync, scanlines, colour)
///                     -> bloom blur (quarter resolution)
///                     -> final pass (curvature, bloom, bezel) -> screen
final class CRTRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let burnInPipeline: MTLRenderPipelineState
    private let dynamicPipeline: MTLRenderPipelineState
    private let blurPipeline: MTLRenderPipelineState
    private let finalPipeline: MTLRenderPipelineState
    private let noiseTexture: MTLTexture

    private var contentTexture: MTLTexture?
    private var contentChanged = false
    private var burnInTextures: [MTLTexture] = []
    private var burnInIndex = 0
    private var burnInNeedsClear = false
    private var burnInLastUpdate: Float = 0
    private var burnInPrevUpdate: Float = 0
    private var screenTexture: MTLTexture?
    private var bloomTextures: [MTLTexture] = []

    private static let workingFormat = MTLPixelFormat.rgba16Float

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw CRTRendererError.setupFailed("no command queue")
        }
        self.queue = queue

        let source = try String(contentsOf: AppResources.url("CRT.metal"), encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)

        func pipeline(_ fragment: String, _ format: MTLPixelFormat) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = format
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        burnInPipeline = try pipeline("burnin_fragment", Self.workingFormat)
        dynamicPipeline = try pipeline("dynamic_fragment", Self.workingFormat)
        blurPipeline = try pipeline("blur_fragment", Self.workingFormat)
        finalPipeline = try pipeline("final_fragment", pixelFormat)
        noiseTexture = try Self.makeNoiseTexture(device: device)
    }

    // MARK: Terminal snapshot

    /// Uploads a new terminal snapshot (RGBA, 8 bits per channel).
    func updateContent(bytes: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) {
        if contentTexture?.width != width || contentTexture?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = .shaderRead
            contentTexture = device.makeTexture(descriptor: descriptor)
            burnInTextures = (0..<2).compactMap { _ in makeRenderTarget(width: width, height: height) }
            burnInNeedsClear = true
        }
        contentTexture?.replace(region: MTLRegionMake2D(0, 0, width, height),
                                mipmapLevel: 0, withBytes: bytes, bytesPerRow: bytesPerRow)
        contentChanged = true
    }

    // MARK: Frame

    func render(to drawable: CAMetalDrawable, uniforms: CRTUniforms) {
        guard let commandBuffer = queue.makeCommandBuffer() else { return }
        encodeFrame(commandBuffer, into: drawable.texture, uniforms: uniforms)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Renders one frame offscreen and returns it as an image. Used to save
    /// screenshots for checking the effects (CRT_SNAPSHOT_PATH).
    func renderImage(width: Int, height: Int, pixelFormat: MTLPixelFormat, uniforms: CRTUniforms) -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor),
              let commandBuffer = queue.makeCommandBuffer() else { return nil }
        encodeFrame(commandBuffer, into: texture, uniforms: uniforms)
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.synchronize(resource: texture)
            blit.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                                | CGImageAlphaInfo.noneSkipFirst.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private func encodeFrame(_ commandBuffer: MTLCommandBuffer, into target: MTLTexture, uniforms: CRTUniforms) {
        guard let content = contentTexture, burnInTextures.count == 2 else {
            commandBuffer.makeRenderCommandEncoder(descriptor: pass(target, clear: true))?.endEncoding()
            return
        }

        ensureScreenTargets(width: target.width, height: target.height)
        guard let screen = screenTexture, bloomTextures.count == 2 else { return }

        if burnInNeedsClear {
            for texture in burnInTextures {
                commandBuffer.makeRenderCommandEncoder(descriptor: pass(texture, clear: true))?.endEncoding()
            }
            burnInNeedsClear = false
        }

        var u = uniforms
        if contentChanged {
            burnInPrevUpdate = burnInLastUpdate
            burnInLastUpdate = u.time
        }
        u.burnInLastUpdate = burnInLastUpdate
        u.burnInPrevUpdate = burnInPrevUpdate

        if contentChanged && u.burnIn > 0 {
            let previous = burnInTextures[burnInIndex]
            let next = burnInTextures[1 - burnInIndex]
            encode(commandBuffer, burnInPipeline, into: next, textures: [content, previous], uniforms: &u)
            burnInIndex = 1 - burnInIndex
        }
        contentChanged = false

        encode(commandBuffer, dynamicPipeline, into: screen,
               textures: [content, burnInTextures[burnInIndex], noiseTexture], uniforms: &u)

        let bloomA = bloomTextures[0], bloomB = bloomTextures[1]
        var horizontal = SIMD2<Float>(1 / Float(bloomA.width), 0)
        encodeBlur(commandBuffer, from: screen, into: bloomA, direction: &horizontal)
        var vertical = SIMD2<Float>(0, 1 / Float(bloomB.height))
        encodeBlur(commandBuffer, from: bloomA, into: bloomB, direction: &vertical)

        encode(commandBuffer, finalPipeline, into: target, textures: [screen, bloomB], uniforms: &u)
    }

    // MARK: Mouse mapping

    /// The same screen distortion the shaders apply, so that clicks land on
    /// the character drawn under the pointer. `uv` has its origin top left.
    static func distort(_ uv: SIMD2<Float>, curvature: Float, frameSize: Float) -> SIMD2<Float> {
        let padded = uv * (1 + frameSize * 2) - SIMD2(repeating: frameSize)
        let cc = padded - SIMD2(repeating: 0.5)
        let dist = (cc * cc).sum() * curvature
        return padded + cc * (1 + dist) * dist
    }

    // MARK: Helpers

    private func encode(_ commandBuffer: MTLCommandBuffer, _ pipeline: MTLRenderPipelineState,
                        into target: MTLTexture, textures: [MTLTexture], uniforms: inout CRTUniforms) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass(target, clear: false)) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CRTUniforms>.stride, index: 0)
        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func encodeBlur(_ commandBuffer: MTLCommandBuffer, from source: MTLTexture,
                            into target: MTLTexture, direction: inout SIMD2<Float>) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass(target, clear: false)) else { return }
        encoder.setRenderPipelineState(blurPipeline)
        encoder.setFragmentBytes(&direction, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func pass(_ texture: MTLTexture, clear: Bool) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = clear ? .clear : .dontCare
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        descriptor.colorAttachments[0].storeAction = .store
        return descriptor
    }

    private func makeRenderTarget(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.workingFormat, width: max(width, 1), height: max(height, 1), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private func ensureScreenTargets(width: Int, height: Int) {
        if screenTexture?.width != width || screenTexture?.height != height {
            screenTexture = makeRenderTarget(width: width, height: height)
            bloomTextures = (0..<2).compactMap { _ in
                makeRenderTarget(width: max(width / 4, 1), height: max(height / 4, 1))
            }
        }
    }

    private static func makeNoiseTexture(device: MTLDevice) throws -> MTLTexture {
        let size = 512
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw CRTRendererError.setupFailed("no noise texture")
        }
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255, using: &generator)
        }
        bytes.withUnsafeBytes { buffer in
            texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
                            withBytes: buffer.baseAddress!, bytesPerRow: size * 4)
        }
        return texture
    }
}
