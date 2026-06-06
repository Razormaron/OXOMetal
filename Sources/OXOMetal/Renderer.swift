import Metal
import MetalKit
import simd

// MARK: - Vertex types

struct Vertex    { var position: SIMD2<Float>; var color: SIMD4<Float> }
struct CRTVertex { var position: SIMD2<Float>; var uv:    SIMD2<Float> }

// MARK: - Renderer

final class Renderer: NSObject, MTKViewDelegate {

    let device:       MTLDevice
    let commandQueue: MTLCommandQueue
    let geomPipeline: MTLRenderPipelineState
    let crtPipeline:  MTLRenderPipelineState
    let sampler:      MTLSamplerState

    weak var gameState: GameState?
    var onTitleChange: ((String) -> Void)?
    private var lastTitle = ""
    private let audio     = AudioManager()

    private let geomBuffer: MTLBuffer   // game geometry, written each frame
    private let crtBuffer:  MTLBuffer   // constant fullscreen quad
    private var offscreen:  MTLTexture? // recreated on resize

    // Canvas size (matches window, used for NDC conversion)
    private let W: Float = 700
    private let H: Float = 700

    // Grid geometry constants (all in game-pixel coordinates, origin top-left)
    private let gridX:  Float = 170   // left edge of grid
    private let gridY:  Float = 170   // top  edge of grid
    private let cellSz: Float = 120   // size of each cell
    private let markR:  Float =  46   // half-span for X / radius for O

    // Glow layers: drawn back-to-front with additive blending.
    // Each tuple: (line-width multiplier, fragment alpha).
    private let layers: [(wm: Float, alpha: Float)] = [
        (5.0, 0.04),   // outermost bloom
        (2.8, 0.14),   // inner glow
        (1.0, 0.88),   // bright phosphor core
    ]

    // Phosphor colours (pre-multiplied by alpha happens in the blend equation)
    private let pCore  = SIMD4<Float>(0.30, 1.00, 0.42, 1)   // bright green
    private let pGlow1 = SIMD4<Float>(0.04, 0.55, 0.10, 1)   // dim outer
    private let pGlow2 = SIMD4<Float>(0.08, 0.80, 0.18, 1)   // mid glow
    private let pWin   = SIMD4<Float>(1.00, 0.96, 0.30, 1)   // yellow win highlight

    // MARK: Init

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device       = device
        self.commandQueue = device.makeCommandQueue()!

        let lib = try device.makeLibrary(source: metalShaderSource, options: nil)

        // ── Geometry pipeline (additive blending) ──────────────────────────
        let geomVD = MTLVertexDescriptor()
        geomVD.attributes[0].format      = .float2
        geomVD.attributes[0].offset      = 0
        geomVD.attributes[0].bufferIndex = 0
        geomVD.attributes[1].format      = .float4
        geomVD.attributes[1].offset      = MemoryLayout<Vertex>.offset(of: \.color)!
        geomVD.attributes[1].bufferIndex = 0
        geomVD.layouts[0].stride         = MemoryLayout<Vertex>.stride

        let geomPD = MTLRenderPipelineDescriptor()
        geomPD.vertexFunction   = lib.makeFunction(name: "vertex_main")!
        geomPD.fragmentFunction = lib.makeFunction(name: "fragment_main")!
        geomPD.vertexDescriptor = geomVD
        geomPD.colorAttachments[0].pixelFormat              = pixelFormat
        geomPD.colorAttachments[0].isBlendingEnabled        = true
        geomPD.colorAttachments[0].rgbBlendOperation        = .add
        geomPD.colorAttachments[0].alphaBlendOperation      = .add
        geomPD.colorAttachments[0].sourceRGBBlendFactor     = .sourceAlpha
        geomPD.colorAttachments[0].destinationRGBBlendFactor = .one
        geomPD.colorAttachments[0].sourceAlphaBlendFactor   = .sourceAlpha
        geomPD.colorAttachments[0].destinationAlphaBlendFactor = .one
        self.geomPipeline = try device.makeRenderPipelineState(descriptor: geomPD)

        // ── CRT pipeline (textured fullscreen quad, no blending) ───────────
        let crtVD = MTLVertexDescriptor()
        crtVD.attributes[0].format      = .float2
        crtVD.attributes[0].offset      = 0
        crtVD.attributes[0].bufferIndex = 0
        crtVD.attributes[1].format      = .float2
        crtVD.attributes[1].offset      = MemoryLayout<CRTVertex>.offset(of: \.uv)!
        crtVD.attributes[1].bufferIndex = 0
        crtVD.layouts[0].stride         = MemoryLayout<CRTVertex>.stride

        let crtPD = MTLRenderPipelineDescriptor()
        crtPD.vertexFunction   = lib.makeFunction(name: "vertex_crt")!
        crtPD.fragmentFunction = lib.makeFunction(name: "fragment_crt")!
        crtPD.vertexDescriptor = crtVD
        crtPD.colorAttachments[0].pixelFormat = pixelFormat
        self.crtPipeline = try device.makeRenderPipelineState(descriptor: crtPD)

        // ── Sampler ────────────────────────────────────────────────────────
        let sd = MTLSamplerDescriptor()
        sd.minFilter    = .linear
        sd.magFilter    = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        self.sampler = device.makeSamplerState(descriptor: sd)!

        // ── Buffers ────────────────────────────────────────────────────────
        // Geometry: up to 12 288 vertices (board marks + dial)
        self.geomBuffer = device.makeBuffer(
            length: 12288 * MemoryLayout<Vertex>.stride,
            options: .storageModeShared)!

        // CRT quad: two triangles covering the full NDC clip space
        // UV (0,0) = top-left, matching Metal texture coordinates.
        let crtVerts: [CRTVertex] = [
            CRTVertex(position: [-1,  1], uv: [0, 0]),  // top-left
            CRTVertex(position: [ 1,  1], uv: [1, 0]),  // top-right
            CRTVertex(position: [-1, -1], uv: [0, 1]),  // bottom-left
            CRTVertex(position: [ 1,  1], uv: [1, 0]),  // top-right
            CRTVertex(position: [ 1, -1], uv: [1, 1]),  // bottom-right
            CRTVertex(position: [-1, -1], uv: [0, 1]),  // bottom-left
        ]
        self.crtBuffer = device.makeBuffer(
            bytes: crtVerts,
            length: crtVerts.count * MemoryLayout<CRTVertex>.stride,
            options: .storageModeShared)!

        super.init()
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        makeOffscreen(size: size, fmt: view.colorPixelFormat)
    }

    func draw(in view: MTKView) {
        guard let gs = gameState else { return }
        gs.update()

        if gs.soundMove { audio.playMove(); gs.soundMove = false }
        if gs.soundWin  { audio.playWin();  gs.soundWin  = false }
        if gs.soundDraw { audio.playDraw(); gs.soundDraw = false }

        let title = gs.windowTitle
        if title != lastTitle {
            lastTitle = title
            let cb = onTitleChange
            DispatchQueue.main.async { cb?(title) }
        }

        if offscreen == nil { makeOffscreen(size: view.drawableSize, fmt: view.colorPixelFormat) }
        guard let tex    = offscreen,
              let rpd2   = view.currentRenderPassDescriptor,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let draw   = view.currentDrawable
        else { return }

        // ── Pass 1: render game geometry into the offscreen texture ─────────
        let rpd1 = MTLRenderPassDescriptor()
        rpd1.colorAttachments[0].texture    = tex
        rpd1.colorAttachments[0].loadAction  = .clear
        rpd1.colorAttachments[0].storeAction = .store
        rpd1.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        var verts = UnsafeMutableBufferPointer<Vertex>(
            start: geomBuffer.contents().assumingMemoryBound(to: Vertex.self),
            count: 12288)
        var n = 0
        buildGeometry(gs, into: &verts, n: &n)

        let enc1 = cmdBuf.makeRenderCommandEncoder(descriptor: rpd1)!
        enc1.setRenderPipelineState(geomPipeline)
        enc1.setVertexBuffer(geomBuffer, offset: 0, index: 0)
        if n > 0 { enc1.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: n) }
        enc1.endEncoding()

        // ── Pass 2: CRT post-process to the drawable ────────────────────────
        let enc2 = cmdBuf.makeRenderCommandEncoder(descriptor: rpd2)!
        enc2.setRenderPipelineState(crtPipeline)
        enc2.setVertexBuffer(crtBuffer, offset: 0, index: 0)
        enc2.setFragmentTexture(tex, index: 0)
        enc2.setFragmentSamplerState(sampler, index: 0)
        enc2.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc2.endEncoding()

        cmdBuf.present(draw)
        cmdBuf.commit()
    }

    // MARK: Offscreen texture

    private func makeOffscreen(size: CGSize, fmt: MTLPixelFormat) {
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: fmt,
            width:       max(1, Int(size.width)),
            height:      max(1, Int(size.height)),
            mipmapped:   false)
        td.usage       = [.renderTarget, .shaderRead]
        td.storageMode = .private
        offscreen = device.makeTexture(descriptor: td)
    }

    // MARK: Geometry

    private func buildGeometry(_ gs: GameState,
                               into v: inout UnsafeMutableBufferPointer<Vertex>,
                               n: inout Int) {
        let winSet = Set(gs.winLine ?? [])

        // Grid lines
        let x0 = gridX, x1 = gridX + cellSz * 3
        let y0 = gridY, y1 = gridY + cellSz * 3
        for (wm, a) in layers {
            let col = glowColor(wm: wm, a: a, win: false)
            let lw  = 2.5 * wm
            line(&v, &n, gridX + cellSz,     y0, gridX + cellSz,     y1, lw, col)
            line(&v, &n, gridX + cellSz * 2, y0, gridX + cellSz * 2, y1, lw, col)
            line(&v, &n, x0, gridY + cellSz,     x1, gridY + cellSz,     lw, col)
            line(&v, &n, x0, gridY + cellSz * 2, x1, gridY + cellSz * 2, lw, col)
        }

        // Win-line highlight
        if let wl = gs.winLine, wl.count == 3 {
            let a = center(wl[0]), b = center(wl[2])
            for (wm, al) in layers {
                let col = glowColor(wm: wm, a: al, win: true)
                line(&v, &n, a.x, a.y, b.x, b.y, 7.0 * wm, col)
            }
        }

        // Board marks
        for i in 0..<9 {
            let cx = gridX + Float(i % 3) * cellSz + cellSz / 2
            let cy = gridY + Float(i / 3) * cellSz + cellSz / 2
            let hi = winSet.contains(i)
            switch gs.board[i] {
            case .x: drawX(&v, &n, cx: cx, cy: cy, highlighted: hi)
            case .o: drawO(&v, &n, cx: cx, cy: cy, highlighted: hi)
            case .empty: break
            }
        }
    }

    private func drawX(_ v: inout UnsafeMutableBufferPointer<Vertex>, _ n: inout Int,
                       cx: Float, cy: Float, highlighted: Bool) {
        for (wm, a) in layers {
            let col = glowColor(wm: wm, a: a, win: highlighted)
            let lw  = 4.5 * wm
            line(&v, &n, cx - markR, cy - markR, cx + markR, cy + markR, lw, col)
            line(&v, &n, cx + markR, cy - markR, cx - markR, cy + markR, lw, col)
        }
    }

    private func drawO(_ v: inout UnsafeMutableBufferPointer<Vertex>, _ n: inout Int,
                       cx: Float, cy: Float, highlighted: Bool) {
        let segs = 32
        for (wm, a) in layers {
            let col = glowColor(wm: wm, a: a, win: highlighted)
            let lw  = 4.5 * wm
            for i in 0..<segs {
                let a0 = Float(i)     / Float(segs) * .pi * 2
                let a1 = Float(i + 1) / Float(segs) * .pi * 2
                line(&v, &n,
                     cx + cos(a0) * markR, cy + sin(a0) * markR,
                     cx + cos(a1) * markR, cy + sin(a1) * markR,
                     lw, col)
            }
        }
    }

    // MARK: Colour helpers

    private func glowColor(wm: Float, a: Float, win: Bool) -> SIMD4<Float> {
        let base: SIMD4<Float>
        if win        { base = pWin   }
        else if wm > 3 { base = pGlow1 }
        else if wm > 1 { base = pGlow2 }
        else           { base = pCore  }
        return SIMD4<Float>(base.x, base.y, base.z, a)
    }

    private func center(_ i: Int) -> SIMD2<Float> {
        SIMD2<Float>(gridX + Float(i % 3) * cellSz + cellSz / 2,
                     gridY + Float(i / 3) * cellSz + cellSz / 2)
    }

    // MARK: Primitive: line segment → quad

    private func line(_ v: inout UnsafeMutableBufferPointer<Vertex>, _ n: inout Int,
                      _ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float,
                      _ width: Float, _ color: SIMD4<Float>) {
        let dx = x1 - x0, dy = y1 - y0
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0, n + 6 <= 12288 else { return }
        let nx = -dy / len * (width * 0.5)
        let ny =  dx / len * (width * 0.5)

        let p0 = ndcv(x0 + nx, y0 + ny)
        let p1 = ndcv(x0 - nx, y0 - ny)
        let p2 = ndcv(x1 + nx, y1 + ny)
        let p3 = ndcv(x1 - nx, y1 - ny)

        v[n] = Vertex(position: p0, color: color); n += 1
        v[n] = Vertex(position: p1, color: color); n += 1
        v[n] = Vertex(position: p2, color: color); n += 1
        v[n] = Vertex(position: p1, color: color); n += 1
        v[n] = Vertex(position: p3, color: color); n += 1
        v[n] = Vertex(position: p2, color: color); n += 1
    }

    // Game coords (top-left origin, y-down) → Metal NDC (centre origin, y-up)
    @inline(__always)
    private func ndcv(_ gx: Float, _ gy: Float) -> SIMD2<Float> {
        SIMD2<Float>((gx / W) * 2 - 1,  1 - (gy / H) * 2)
    }
}
