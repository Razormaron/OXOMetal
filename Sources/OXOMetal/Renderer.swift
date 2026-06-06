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

    private let geomBuffer: MTLBuffer
    private let crtBuffer:  MTLBuffer
    private var offscreen:  MTLTexture?

    private let W: Float = 700
    private let H: Float = 700

    // ── EDSAC Williams tube display: 35×16 dot matrix ────────────────────────
    // The real display was ~35 cols × 16 rows (landscape). We center this grid
    // in the 700×700 canvas: 35×14 = 490 px wide, 16×14 = 224 px tall,
    // origin at (105, 238) — all dots fit comfortably inside the 294 px circle.
    static let gridCols  = 11
    static let gridRows  = 11
    static let dotSp: Float = 34.0   // larger dots fill the CRT circle nicely
    static let dotR:  Float =  9.0
    static let bx:    Float = 180.0  // (700 - 10*34) / 2
    static let by:    Float = 180.0
    static let boardDC = 0
    static let boardDR = 0
    static let cellOffsets = [0, 4, 8]

    // 3×3 X — crude diagonal cross (period-faithful)
    static let xDots: [(Int, Int)] = [
        (0,0),(0,2), (1,1), (2,0),(2,2)
    ]

    // 3×3 O — hollow square (period-faithful)
    static let oDots: [(Int, Int)] = [
        (0,0),(0,1),(0,2),
        (1,0),      (1,2),
        (2,0),(2,1),(2,2)
    ]

    // ── Phosphor colours per mark type ───────────────────────────────────────
    // Grid dividers: very dim blue-grey — easy to see structure without clutter
    private let cDivBright = SIMD4<Float>(0.30, 0.45, 0.70, 1)
    private let cDivMid    = SIMD4<Float>(0.08, 0.18, 0.40, 1)
    private let cDivDim    = SIMD4<Float>(0.02, 0.05, 0.18, 1)
    // X mark: bright blue-white (cold cathode glow)
    private let cXBright   = SIMD4<Float>(0.70, 0.88, 1.00, 1)
    private let cXMid      = SIMD4<Float>(0.22, 0.50, 0.90, 1)
    private let cXDim      = SIMD4<Float>(0.05, 0.14, 0.50, 1)
    // O mark: warm amber (visually opposite to X — impossible to confuse)
    private let cOBright   = SIMD4<Float>(1.00, 0.72, 0.12, 1)
    private let cOMid      = SIMD4<Float>(0.80, 0.40, 0.04, 1)
    private let cODim      = SIMD4<Float>(0.30, 0.12, 0.01, 1)
    // Win highlight: bright warm white
    private let cWBright   = SIMD4<Float>(1.00, 0.97, 0.80, 1)
    private let cWMid      = SIMD4<Float>(0.70, 0.60, 0.20, 1)
    private let cWDim      = SIMD4<Float>(0.22, 0.16, 0.04, 1)

    // ── Phosphor persistence buffers ──────────────────────────────────────────
    // brightness: 0-1, decays each frame.  markType: colour category, persists.
    // type 0=none, 1=divider, 2=X, 3=O, 4=win
    private var brightness = [Float](repeating: 0, count: 11 * 11)
    private var markType   = [UInt8](repeating: 0, count: 11 * 11)
    private let decayRate: Float = 0.88

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
        geomPD.colorAttachments[0].pixelFormat               = pixelFormat
        geomPD.colorAttachments[0].isBlendingEnabled         = true
        geomPD.colorAttachments[0].rgbBlendOperation         = .add
        geomPD.colorAttachments[0].alphaBlendOperation       = .add
        geomPD.colorAttachments[0].sourceRGBBlendFactor      = .sourceAlpha
        geomPD.colorAttachments[0].destinationRGBBlendFactor = .one
        geomPD.colorAttachments[0].sourceAlphaBlendFactor    = .sourceAlpha
        geomPD.colorAttachments[0].destinationAlphaBlendFactor = .one
        self.geomPipeline = try device.makeRenderPipelineState(descriptor: geomPD)

        // ── CRT pipeline (textured fullscreen quad) ────────────────────────
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
        self.geomBuffer = device.makeBuffer(
            length: 12288 * MemoryLayout<Vertex>.stride,
            options: .storageModeShared)!

        let crtVerts: [CRTVertex] = [
            CRTVertex(position: [-1,  1], uv: [0, 0]),
            CRTVertex(position: [ 1,  1], uv: [1, 0]),
            CRTVertex(position: [-1, -1], uv: [0, 1]),
            CRTVertex(position: [ 1,  1], uv: [1, 0]),
            CRTVertex(position: [ 1, -1], uv: [1, 1]),
            CRTVertex(position: [-1, -1], uv: [0, 1]),
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

        // Phosphor persistence: decay brightness, then re-light active elements
        for i in 0..<brightness.count { brightness[i] *= decayRate }
        lightDots(gs)

        if offscreen == nil { makeOffscreen(size: view.drawableSize, fmt: view.colorPixelFormat) }
        guard let tex    = offscreen,
              let rpd2   = view.currentRenderPassDescriptor,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let draw   = view.currentDrawable
        else { return }

        // Pass 1: render phosphor geometry to offscreen texture
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

        // Pass 2: CRT post-process to drawable
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

    // MARK: Phosphor update

    private func lightDots(_ gs: GameState) {
        // Grid dividers — dim, type 1
        for i in 0...10 {
            light(row: i, col: 3, type: 1); light(row: i, col: 7, type: 1)
            light(row: 3, col: i, type: 1); light(row: 7, col: i, type: 1)
        }

        // Board marks — X=2 (blue-white), O=3 (amber), win=4 (warm white)
        let winSet = Set(gs.winLine ?? [])
        for i in 0..<9 where gs.board[i] != .empty {
            let isX     = gs.board[i] == .x
            let type: UInt8 = winSet.contains(i) ? 4 : (isX ? 2 : 3)
            let pattern = isX ? Renderer.xDots : Renderer.oDots
            let dc = Renderer.cellOffsets[i % 3]
            let dr = Renderer.cellOffsets[i / 3]
            for (r, c) in pattern { light(row: dr + r, col: dc + c, type: type) }
        }
    }

    private func light(row: Int, col: Int, type: UInt8) {
        let idx = row * Renderer.gridCols + col
        brightness[idx] = 1.0
        markType[idx]   = type
    }

    // MARK: Geometry

    private func buildGeometry(_ gs: GameState,
                               into v: inout UnsafeMutableBufferPointer<Vertex>,
                               n: inout Int) {
        let gc = Renderer.gridCols
        for row in 0..<Renderer.gridRows {
            for col in 0..<Renderer.gridCols {
                let b = brightness[row * gc + col]
                guard b > 0.01 else { continue }
                let px = Renderer.bx + Float(col) * Renderer.dotSp
                let py = Renderer.by + Float(row) * Renderer.dotSp
                litDot(&v, n: &n, x: px, y: py, brightness: b, type: markType[row * gc + col])
            }
        }
    }

    // Single phosphor dot rendered as three additive layers: bloom · glow · core.
    private func litDot(_ v: inout UnsafeMutableBufferPointer<Vertex>, n: inout Int,
                        x: Float, y: Float, brightness b: Float, type: UInt8) {
        let r = Renderer.dotR
        let (bright, mid, dim): (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
        switch type {
        case 1:  (bright, mid, dim) = (cDivBright, cDivMid, cDivDim)   // divider
        case 3:  (bright, mid, dim) = (cOBright,   cOMid,   cODim)     // O
        case 4:  (bright, mid, dim) = (cWBright,   cWMid,   cWDim)     // win
        default: (bright, mid, dim) = (cXBright,   cXMid,   cXDim)     // X
        }
        // dividers rendered at 30% max brightness so marks dominate visually
        let scale: Float = (type == 1) ? 0.30 : 1.0
        let s = b * scale
        dot(&v, n: &n, x: x, y: y, r: r * 3.2,
            color: SIMD4<Float>(dim.x,    dim.y,    dim.z,    0.07 * s))
        dot(&v, n: &n, x: x, y: y, r: r * 1.7,
            color: SIMD4<Float>(mid.x,    mid.y,    mid.z,    0.18 * s))
        dot(&v, n: &n, x: x, y: y, r: r,
            color: SIMD4<Float>(bright.x, bright.y, bright.z, 0.90 * s))
    }

    // Axis-aligned quad (6 vertices).
    private func dot(_ v: inout UnsafeMutableBufferPointer<Vertex>, n: inout Int,
                     x: Float, y: Float, r: Float, color: SIMD4<Float>) {
        guard n + 6 <= 12288 else { return }
        let p00 = ndcv(x - r, y - r), p10 = ndcv(x + r, y - r)
        let p01 = ndcv(x - r, y + r), p11 = ndcv(x + r, y + r)
        v[n] = Vertex(position: p00, color: color); n += 1
        v[n] = Vertex(position: p10, color: color); n += 1
        v[n] = Vertex(position: p01, color: color); n += 1
        v[n] = Vertex(position: p10, color: color); n += 1
        v[n] = Vertex(position: p11, color: color); n += 1
        v[n] = Vertex(position: p01, color: color); n += 1
    }

    @inline(__always)
    private func ndcv(_ gx: Float, _ gy: Float) -> SIMD2<Float> {
        SIMD2<Float>((gx / W) * 2 - 1,  1 - (gy / H) * 2)
    }
}
