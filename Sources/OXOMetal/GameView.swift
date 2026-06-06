import AppKit
import Metal
import MetalKit

final class GameView: MTKView {

    let gameState = GameState()
    private(set) var renderer: Renderer!

    required init(coder: NSCoder) { fatalError() }

    init(frame: NSRect, device: MTLDevice) {
        super.init(frame: frame, device: device)
        colorPixelFormat         = .bgra8Unorm
        clearColor               = MTLClearColor(red: 0.09, green: 0.10, blue: 0.07, alpha: 1)
        preferredFramesPerSecond = 60
        isPaused                 = false
        enableSetNeedsDisplay    = false
        layer?.isOpaque          = true

        do {
            renderer = try Renderer(device: device, pixelFormat: colorPixelFormat)
        } catch {
            fatalError("Renderer init failed: \(error)")
        }
        renderer.gameState    = gameState
        renderer.onTitleChange = { [weak self] t in self?.window?.title = t }
        self.delegate          = renderer
    }

    // MARK: Input

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let gx = Float(pt.x)
        let gy = Float(frame.height - pt.y)   // flip Y: AppKit is bottom-up
        if let cell = cellAt(gx: gx, gy: gy) {
            gameState.playerMove(cell: cell)
        } else {
            gameState.pressSpace()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        switch event.keyCode {
        case 49: gameState.pressSpace()
        // Numpad layout mirrors the grid (7=top-left … 3=bottom-right)
        case 89: gameState.playerMove(cell: 0)   // numpad 7
        case 91: gameState.playerMove(cell: 1)   // numpad 8
        case 92: gameState.playerMove(cell: 2)   // numpad 9
        case 86: gameState.playerMove(cell: 3)   // numpad 4
        case 87: gameState.playerMove(cell: 4)   // numpad 5
        case 88: gameState.playerMove(cell: 5)   // numpad 6
        case 83: gameState.playerMove(cell: 6)   // numpad 1
        case 84: gameState.playerMove(cell: 7)   // numpad 2
        case 85: gameState.playerMove(cell: 8)   // numpad 3
        default:
            if let ch = event.charactersIgnoringModifiers?.first,
               let d = ch.wholeNumberValue, (1...9).contains(d) {
                let map = [7:0, 8:1, 9:2, 4:3, 5:4, 6:5, 1:6, 2:7, 3:8]
                if let cell = map[d] { gameState.playerMove(cell: cell) }
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: Hit testing

    // Grid spans (170,170)–(530,530) in game coordinates; cells are 120×120.
    private let gridX:  Float = 170
    private let gridY:  Float = 170
    private let cellSz: Float = 120

    private func cellAt(gx: Float, gy: Float) -> Int? {
        let col = Int((gx - gridX) / cellSz)
        let row = Int((gy - gridY) / cellSz)
        guard (0..<3).contains(col) && (0..<3).contains(row) else { return nil }
        return row * 3 + col
    }
}
