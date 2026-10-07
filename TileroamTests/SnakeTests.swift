import Foundation
import Testing
@testable import Tileroam

struct SnakeTests {
    private func tiles(_ cells: [(Int, Int)]) -> Set<Int64> {
        Set(cells.map { TileGrid.key(x: 8_000 + $0.0, y: 5_000 + $0.1) })
    }

    /// Tiles drawn as text: "#" visited.
    private func tiles(_ rows: [String]) -> Set<Int64> {
        tiles(rows.enumerated().flatMap { y, row in row.enumerated().compactMap { x, c in c == "#" ? (x, y) : nil } })
    }

    /// A snake: visited tiles, each one once, each a horizontal or vertical step from the one before.
    private func isValid(_ snake: Snake, in visited: Set<Int64>) -> Bool {
        guard Set(snake.tiles).count == snake.tiles.count, snake.tiles.allSatisfy(visited.contains) else { return false }
        return zip(snake.tiles, snake.tiles.dropFirst()).allSatisfy { a, b in
            let p = TileGrid.cell(of: a), q = TileGrid.cell(of: b)
            return abs(p.x - q.x) + abs(p.y - q.y) == 1
        }
    }

    @Test func empty() {
        let snake = SnakeFinder.longest([])
        #expect(snake.tiles.isEmpty && !snake.isLongestPossible)
    }

    @Test func line() {
        let visited = tiles(["#####"])
        let snake = SnakeFinder.longest(visited)
        #expect(snake.tiles.count == 5 && snake.isLongestPossible && isValid(snake, in: visited))
    }

    @Test func diagonalsDontConnect() {
        let visited = tiles(["#.#", ".#.", "#.#"])
        #expect(SnakeFinder.longest(visited).tiles.count == 1)
    }

    @Test func blockIsCoveredWhole() {
        let visited = tiles(["###", "###", "###"])
        let snake = SnakeFinder.longest(visited)
        #expect(snake.tiles.count == 9 && snake.isLongestPossible && isValid(snake, in: visited))
    }

    @Test func colourBound() {
        // A 2×2 block: 2 black, 2 white tiles: all 4.
        #expect(SnakeFinder.longest(tiles(["##", "##"])).tiles.count == 4)
        // A U: 3 tiles of one colour, 2 of the other, so a snake can take all 5 (one colour at both ends).
        let u = tiles(["###", "#.#"])
        #expect(SnakeFinder.longest(u).tiles.count == 5)
        // A T: 3 of one colour, 1 of the other: at most 2 × 1 + 1 = 3.
        let t = tiles(["###", ".#."])
        let snake = SnakeFinder.longest(t)
        #expect(snake.bound == 3 && snake.tiles.count == 3 && isValid(snake, in: t))
    }

    @Test func plusTakesTwoArms() {
        // A plus: four tiles with one neighbour, only two can be the ends.
        let visited = tiles([".#.", "###", ".#."])
        let snake = SnakeFinder.longest(visited)
        #expect(snake.tiles.count == 3 && snake.bound == 3 && snake.isLongestPossible)
    }

    @Test func biggestGroupWins() {
        let visited = tiles(["##..####", "........", "###....."])
        let snake = SnakeFinder.longest(visited)
        #expect(snake.tiles.count == 4 && snake.isLongestPossible)
    }

    @Test func detourThroughAPocket() {
        // The straight line along the top misses the 2×2 pocket below; the detour takes it.
        let visited = tiles(["########", "...##...", "...##..."])
        let snake = SnakeFinder.longest(visited)
        #expect(isValid(snake, in: visited))
        #expect(snake.tiles.count == 12) // down into the pocket and back up: every tile
    }

    @Test func bigBlockIsCoveredWhole() {
        // 60 × 50 tiles: a snake can cover all 3,000. Release builds find that; tests run a Debug
        // build, which searches less (`SnakeFinder.steps`), so at least 99%.
        let visited = tiles((0..<60).flatMap { x in (0..<50).map { (x, $0) } })
        let snake = SnakeFinder.longest(visited)
        #expect(snake.tiles.count >= 2_970 && snake.bound == 3_000 && isValid(snake, in: visited))
    }

    @Test func holeyAreaGetsALongSnake() {
        // 70 × 70 tiles with about 15% missing (a fixed pattern), like a well-ridden region.
        var seed: UInt64 = 42
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        let visited = tiles((0..<70).flatMap { x in (0..<70).compactMap { y in random() < 0.85 ? (x, y) : nil } })
        let start = Date()
        let snake = SnakeFinder.longest(visited)
        let seconds = Date().timeIntervalSince(start)
        #expect(isValid(snake, in: visited))
        #expect(Double(snake.tiles.count) >= 0.8 * Double(snake.bound), "\(snake.tiles.count) of at most \(snake.bound)")
        #expect(seconds < 20, "took \(seconds) s")
        print("SNAKE holey: \(snake.tiles.count) of \(visited.count) tiles, bound \(snake.bound), \(seconds) s")
        // The same tiles give the same snake.
        #expect(SnakeFinder.longest(visited) == snake)
    }
}
