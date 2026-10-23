import CoreGraphics
import Metal
import MetalKit
import simd

// Uniform layouts; must match the structs in Shaders.swift.
struct FrameU {
    var view = matrix_identity_float4x4
    var proj = matrix_identity_float4x4
    var viewProj = matrix_identity_float4x4
    var time: Float = 0
    var starTime: Float = 0
    var pixelRatio: Float = 1
    var pad: Float = 0
}

struct Particle {
    var posPhase: SIMD4<Float>   // xyz, twinkle/bob phase
    var sizeSpeed: SIMD4<Float>  // size, drift speed, unused, unused
}

struct CardU {
    var model = matrix_identity_float4x4
    var size = SIMD2<Float>(1, 1)
    var opacity: Float = 1
    var glow: Float = 0
    var radius: Float = 0.06
    var refl: Float = 0
    var dim: Float = 1
    var pad: Float = 0
}

struct CardDraw {
    var u: CardU
    var texture: MTLTexture?
}

/// Draws one frame: background, water, stars, card reflections, cards (back to front), dust. No depth buffer:
/// everything is ordered by hand, so the reflections draw over the water instead of hiding under it.
final class Renderer {
    static let waterY: Float = -1.45

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let bgPipe, waterPipe, cardPipe, starPipe, dustPipe: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let stars, dust: MTLBuffer
    private let starCount = 2600, dustCount = 180
    private let blank: MTLTexture
    private let waterModel: float4x4

    init(pixelFormat: MTLPixelFormat) {
        let device = MTLCreateSystemDefaultDevice()!
        self.device = device
        queue = device.makeCommandQueue()!
        let lib = try! device.makeLibrary(source: shaderSource, options: nil)

        func pipe(_ v: String, _ f: String, blend: (MTLBlendFactor, MTLBlendFactor)?) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: v)
            d.fragmentFunction = lib.makeFunction(name: f)
            let a = d.colorAttachments[0]!
            a.pixelFormat = pixelFormat
            if let (src, dst) = blend {
                a.isBlendingEnabled = true
                a.sourceRGBBlendFactor = src; a.destinationRGBBlendFactor = dst
                a.sourceAlphaBlendFactor = .one; a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try! device.makeRenderPipelineState(descriptor: d)
        }
        bgPipe = pipe("bg_vertex", "bg_fragment", blend: nil)
        waterPipe = pipe("mesh_vertex", "water_fragment", blend: nil)
        cardPipe = pipe("mesh_vertex", "card_fragment", blend: (.sourceAlpha, .oneMinusSourceAlpha))
        starPipe = pipe("star_vertex", "star_fragment", blend: (.sourceAlpha, .one))
        dustPipe = pipe("dust_vertex", "dust_fragment", blend: (.sourceAlpha, .one))

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sd)!

        let wy = Renderer.waterY
        var s = (0..<starCount).map { _ in
            Particle(posPhase: [Float.random(in: -0.5..<0.5) * 320, wy + 1 + pow(Float.random(in: 0..<1), 0.7) * 90, -70 - Float.random(in: 0..<1) * 90, Float.random(in: 0..<(2 * .pi))],
                     sizeSpeed: [0.6 + pow(Float.random(in: 0..<1), 3) * 2.4, 0, 0, 0])
        }
        stars = device.makeBuffer(bytes: &s, length: MemoryLayout<Particle>.stride * s.count)!
        var d = (0..<dustCount).map { _ in
            Particle(posPhase: [Float.random(in: -0.5..<0.5) * 70, -1.2 + Float.random(in: 0..<9), -14 + Float.random(in: 0..<20), Float.random(in: 0..<(2 * .pi))],
                     sizeSpeed: [6 + Float.random(in: 0..<16), 0.08 + Float.random(in: 0..<0.25), 0, 0])
        }
        dust = device.makeBuffer(bytes: &d, length: MemoryLayout<Particle>.stride * d.count)!

        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        blank = device.makeTexture(descriptor: td)!
        var px: [UInt8] = [0x38, 0x22, 0x1a, 0xff]  // #1a2238, BGRA: the card color while its image loads
        blank.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)

        waterModel = .translation(0, wy, -80) * .rotationX(-.pi / 2) * .scale(600, 240, 1)
    }

    /// Uploads a Painter context (BGRA, top row first) as a texture. Safe to call off the main thread.
    func texture(from c: CGContext) -> MTLTexture? {
        guard let data = c.data else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: c.width, height: c.height, mipmapped: false)
        d.usage = .shaderRead
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        t.replace(region: MTLRegionMake2D(0, 0, c.width, c.height), mipmapLevel: 0, withBytes: data, bytesPerRow: c.bytesPerRow)
        return t
    }

    func draw(in view: MTKView, frame: FrameU, reflections: [CardDraw], cards: [CardDraw]) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        var f = frame
        let fLen = MemoryLayout<FrameU>.stride, uLen = MemoryLayout<CardU>.stride

        enc.setRenderPipelineState(bgPipe)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        enc.setRenderPipelineState(waterPipe)
        enc.setVertexBytes(&f, length: fLen, index: 1)
        enc.setFragmentBytes(&f, length: fLen, index: 0)
        var wm = waterModel
        enc.setVertexBytes(&wm, length: MemoryLayout<float4x4>.stride, index: 2)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        enc.setRenderPipelineState(starPipe)
        enc.setVertexBuffer(stars, offset: 0, index: 0)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: starCount)

        enc.setRenderPipelineState(cardPipe)
        enc.setFragmentSamplerState(sampler, index: 0)
        for c in reflections + cards {
            var u = c.u
            enc.setVertexBytes(&u, length: uLen, index: 2)
            enc.setFragmentBytes(&u, length: uLen, index: 0)
            enc.setFragmentTexture(c.texture ?? blank, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        enc.setRenderPipelineState(dustPipe)
        enc.setVertexBuffer(dust, offset: 0, index: 0)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: dustCount)

        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}

// ---------- matrices (right-handed, Metal clip depth 0...1) ----------

extension float4x4 {
    static func translation(_ x: Float, _ y: Float, _ z: Float) -> float4x4 {
        float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [x, y, z, 1]))
    }
    static func scale(_ x: Float, _ y: Float, _ z: Float) -> float4x4 {
        float4x4(diagonal: [x, y, z, 1])
    }
    static func rotationX(_ a: Float) -> float4x4 {
        let c = cos(a), s = sin(a)
        return float4x4(columns: ([1, 0, 0, 0], [0, c, s, 0], [0, -s, c, 0], [0, 0, 0, 1]))
    }
    static func rotationY(_ a: Float) -> float4x4 {
        let c = cos(a), s = sin(a)
        return float4x4(columns: ([c, 0, -s, 0], [0, 1, 0, 0], [s, 0, c, 0], [0, 0, 0, 1]))
    }
    static func rotationZ(_ a: Float) -> float4x4 {
        let c = cos(a), s = sin(a)
        return float4x4(columns: ([c, s, 0, 0], [-s, c, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]))
    }
    /// Euler angles applied in three.js "XYZ" order.
    static func rotation(_ x: Float, _ y: Float, _ z: Float) -> float4x4 { rotationX(x) * rotationY(y) * rotationZ(z) }

    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let ys = 1 / tan(fovY / 2), xs = ys / aspect, zs = far / (near - far)
        return float4x4(columns: ([xs, 0, 0, 0], [0, ys, 0, 0], [0, 0, zs, -1], [0, 0, zs * near, 0]))
    }
    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) -> float4x4 {
        let z = normalize(eye - target), x = normalize(cross(up, z)), y = cross(z, x)
        return float4x4(columns: ([x.x, y.x, z.x, 0], [x.y, y.y, z.y, 0], [x.z, y.z, z.z, 0], [-dot(x, eye), -dot(y, eye), -dot(z, eye), 1]))
    }
}
