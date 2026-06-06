import Foundation

enum Cell { case empty, x, o }
enum Phase { case waiting, playerTurn, aiThinking, over }
enum Outcome { case none, playerWins, aiWins, draw }

final class GameState {

    var board   = Array(repeating: Cell.empty, count: 9)
    var phase:   Phase   = .waiting
    var outcome: Outcome = .none
    var winLine: [Int]?  = nil

    private var aiThinkTimer = 0
    private static let aiDelay = 42    // ~0.7 s at 60 fps

    var playerScore = 0
    var aiScore     = 0

    var soundMove = false
    var soundWin  = false
    var soundDraw = false

    // MARK: Window title

    var windowTitle: String {
        let score = "You \(playerScore) – \(aiScore) EDSAC"
        switch phase {
        case .waiting:
            return "OXO  ·  \(score)  ·  Space to start"
        case .playerTurn:
            return "OXO  ·  \(score)  ·  Your move (O)"
        case .aiThinking:
            return "OXO  ·  \(score)  ·  Thinking…"
        case .over:
            switch outcome {
            case .playerWins: return "OXO  ·  \(score)  ·  YOU WIN!  Space to play again"
            case .aiWins:     return "OXO  ·  \(score)  ·  EDSAC WINS!  Space to play again"
            case .draw:       return "OXO  ·  \(score)  ·  DRAW  ·  Space to play again"
            case .none:       return "OXO"
            }
        }
    }

    // MARK: Public interface

    func pressSpace() {
        if phase == .waiting || phase == .over { startGame() }
    }

    func playerMove(cell: Int) {
        guard phase == .playerTurn, board[cell] == .empty else { return }
        board[cell] = .o
        soundMove   = true
        if let result = checkResult() {
            endGame(result)
        } else {
            phase         = .aiThinking
            aiThinkTimer  = GameState.aiDelay
        }
    }

    func update() {
        guard phase == .aiThinking else { return }
        aiThinkTimer -= 1
        if aiThinkTimer <= 0 { performAIMove() }
    }

    // MARK: Private

    private func startGame() {
        board       = Array(repeating: .empty, count: 9)
        winLine     = nil
        outcome     = .none
        phase       = .playerTurn
    }

    private func performAIMove() {
        guard let move = bestMove() else { return }
        board[move] = .x
        soundMove   = true
        if let result = checkResult() {
            endGame(result)
        } else {
            phase = .playerTurn
        }
    }

    private func endGame(_ result: Outcome) {
        outcome = result
        phase   = .over
        if result == .playerWins || result == .aiWins {
            winLine  = findWinLine(in: board)
            soundWin = true
            if result == .playerWins { playerScore += 1 } else { aiScore += 1 }
        } else {
            soundDraw = true
        }
    }

    private func checkResult() -> Outcome? {
        if let line = findWinLine(in: board) {
            return board[line[0]] == .o ? .playerWins : .aiWins
        }
        if board.allSatisfy({ $0 != .empty }) { return .draw }
        return nil
    }

    // MARK: Minimax AI

    private func bestMove() -> Int? {
        var bestScore = Int.min
        var bestIdx   = -1
        for i in 0..<9 where board[i] == .empty {
            var b = board; b[i] = .x
            let score = minimax(board: b, depth: 1, isMaximizing: false)
            if score > bestScore { bestScore = score; bestIdx = i }
        }
        return bestIdx >= 0 ? bestIdx : nil
    }

    private func minimax(board: [Cell], depth: Int, isMaximizing: Bool) -> Int {
        if let line = findWinLine(in: board) {
            return board[line[0]] == .x ? (10 - depth) : (depth - 10)
        }
        if board.allSatisfy({ $0 != .empty }) { return 0 }

        if isMaximizing {
            var best = Int.min
            for i in 0..<9 where board[i] == .empty {
                var b = board; b[i] = .x
                best = max(best, minimax(board: b, depth: depth + 1, isMaximizing: false))
            }
            return best
        } else {
            var best = Int.max
            for i in 0..<9 where board[i] == .empty {
                var b = board; b[i] = .o
                best = min(best, minimax(board: b, depth: depth + 1, isMaximizing: true))
            }
            return best
        }
    }

    private static let winPatterns: [[Int]] = [
        [0,1,2], [3,4,5], [6,7,8],   // rows
        [0,3,6], [1,4,7], [2,5,8],   // cols
        [0,4,8], [2,4,6]              // diagonals
    ]

    private func findWinLine(in board: [Cell]) -> [Int]? {
        for p in GameState.winPatterns {
            let a = board[p[0]], b = board[p[1]], c = board[p[2]]
            if a != .empty && a == b && b == c { return p }
        }
        return nil
    }
}
