import Foundation

/// The snake challenge: the longest snake of visited tiles, a path from tile to tile that only
/// goes horizontally and vertically and visits no tile twice.
///
/// Finding the longest path in a grid is NP-hard, so for many tiles no one can be sure of the
/// best snake. `SnakeFinder` searches small groups of tiles completely and grows long snakes in
/// big ones (then extends their ends and folds in detours until nothing helps). It also knows an
/// upper bound per group: when the snake reaches it, it is the longest possible.
struct Snake: Sendable, Equatable {
    /// The tiles in order, from one end to the other (`TileGrid.key`).
    var tiles: [Int64] = []
    /// No snake can be longer than this.
    var bound = 0

    var isLongestPossible: Bool { !tiles.isEmpty && tiles.count >= bound }
}

enum SnakeFinder {
    /// Groups of up to this many tiles are searched completely (when the search fits `exactSteps`).
    static let exactSize = 48
    static let exactSteps = 3_000_000
    /// Work limit for a big group: a count of steps, not a time, so the same tiles always give
    /// the same snake (on every device). Debug builds run the search about 50 times slower, so
    /// they search less.
    #if DEBUG
    static let steps = 20_000_000
    #else
    static let steps = 200_000_000
    #endif

    static func longest(_ visited: Set<Int64>) -> Snake {
        let groups = components(visited).sorted { $0.size > $1.size || $0.size == $1.size && $0.cells[0] < $1.cells[0] }
        var best = [Int64](), bound = 0
        for group in groups {
            guard group.size > best.count else { break } // sorted: the rest is smaller still
            let graph = Graph(group.cells)
            let (blockBound, chainNodes) = graph.blockBound()
            let upper = min(graph.upperBound, blockBound)
            guard upper > best.count else {
                bound = max(bound, upper)
                continue
            }
            // The snake runs through one chain of blocks; the heaviest chain is the place to look.
            let chain = chainNodes.count < graph.count ? Graph(chainNodes.map { graph.keys[Int($0)] }) : graph
            var found: [Int64]
            var exact = false
            if graph.count <= exactSize, let path = graph.exactLongest(maxSteps: exactSteps) {
                found = path.map { graph.keys[Int($0)] }
                exact = true
            } else if chain.count <= exactSize, let path = chain.exactLongest(maxSteps: exactSteps) {
                found = path.map { chain.keys[Int($0)] } // the best there, not proven best in the group
            } else {
                found = chain.heuristicLongest(maxSteps: chain === graph ? steps : steps * 2 / 3, upper: upper).map { chain.keys[Int($0)] }
                if chain !== graph, found.count < upper {
                    let whole = graph.heuristicLongest(maxSteps: steps / 3, upper: upper)
                    if whole.count > found.count { found = whole.map { graph.keys[Int($0)] } }
                }
            }
            bound = max(bound, exact ? found.count : upper)
            if found.count > best.count { best = found }
        }
        return Snake(tiles: best, bound: max(bound, best.count))
    }

    /// The 4-connected groups of tiles, each with its cells sorted (row by row).
    static func components(_ visited: Set<Int64>) -> [(size: Int, cells: [Int64])] {
        var seen = Set<Int64>(), result = [(size: Int, cells: [Int64])]()
        for start in visited.sorted() where !seen.contains(start) {
            var stack = [start], cells = [Int64]()
            seen.insert(start)
            while let k = stack.popLast() {
                cells.append(k)
                let (x, y) = TileGrid.cell(of: k)
                for n in [TileGrid.key(x: x + 1, y: y), TileGrid.key(x: x - 1, y: y), TileGrid.key(x: x, y: y + 1), TileGrid.key(x: x, y: y - 1)]
                where visited.contains(n) && seen.insert(n).inserted {
                    stack.append(n)
                }
            }
            result.append((cells.count, cells.sorted()))
        }
        return result
    }

    /// One group of tiles as a graph: nodes 0..<count, up to four neighbours each.
    final class Graph {
        let keys: [Int64]
        let xs: [Int], ys: [Int]
        /// Per node: right, down, left, up (-1: none), four entries each (flat: fast in Debug builds too).
        let links: [Int32]
        let count: Int
        /// Scratch for `detour`: per node, the node before it, valid when `mark` is `generation`.
        private var previous: [Int32], mark: [Int32], generation: Int32 = 0

        @inline(__always) func neighbour(_ n: Int32, _ d: Int) -> Int32 { links[Int(n) &* 4 &+ d] }
        func neighbours(_ n: Int32) -> [Int32] { (0..<4).map { neighbour(n, $0) } }

        init(_ cells: [Int64]) {
            keys = cells
            let index = Dictionary(uniqueKeysWithValues: cells.enumerated().map { ($0.element, Int32($0.offset)) })
            let points = cells.map(TileGrid.cell(of:))
            xs = points.map(\.x)
            ys = points.map(\.y)
            links = points.flatMap { p in
                [(1, 0), (0, 1), (-1, 0), (0, -1)].map { index[TileGrid.key(x: p.x + $0.0, y: p.y + $0.1)] ?? -1 }
            }
            count = cells.count
            previous = [Int32](repeating: -1, count: cells.count)
            mark = [Int32](repeating: 0, count: cells.count)
        }

        func degree(_ n: Int32) -> Int { (0..<4).count { neighbour(n, $0) >= 0 } }

        /// No path is longer: the tiles alternate colours like a chessboard (at most one more of
        /// one colour than the other), and a tile with one neighbour can only be an end.
        var upperBound: Int {
            let black = (0..<count).count { (xs[$0] + ys[$0]) & 1 == 0 }
            let leaves = (0..<count).count { degree(Int32($0)) <= 1 }
            return min(count, 2 * min(black, count - black) + 1, count - max(0, leaves - 2))
        }

        /// The biconnected blocks (no tile whose removal splits them), as lists of nodes; tiles
        /// in several blocks are the cut tiles between them. Tarjan's algorithm, without recursion.
        func blocks() -> [[Int32]] {
            var index = [Int32](repeating: -1, count: count), low = [Int32](repeating: 0, count: count)
            var result = [[Int32]](), edges = [(Int32, Int32)](), counter: Int32 = 0
            for root in 0..<Int32(count) where index[Int(root)] < 0 {
                if degree(root) == 0 { result.append([root]); index[Int(root)] = counter; counter += 1; continue }
                index[Int(root)] = counter; low[Int(root)] = counter; counter += 1
                var stack: [(node: Int32, parent: Int32, next: Int)] = [(root, -1, 0)]
                while !stack.isEmpty {
                    let top = stack.count - 1
                    let (n, parent, k) = stack[top]
                    if k < 4 {
                        stack[top].next = k + 1
                        let q = neighbour(n, k)
                        guard q >= 0, q != parent else { continue }
                        if index[Int(q)] < 0 {
                            edges.append((n, q))
                            index[Int(q)] = counter; low[Int(q)] = counter; counter += 1
                            stack.append((q, n, 0))
                        } else if index[Int(q)] < index[Int(n)] {
                            edges.append((n, q))
                            low[Int(n)] = min(low[Int(n)], index[Int(q)])
                        }
                    } else {
                        stack.removeLast()
                        guard parent >= 0 else { continue }
                        low[Int(parent)] = min(low[Int(parent)], low[Int(n)])
                        if low[Int(n)] >= index[Int(parent)] {
                            // parent separates n's subtree: the edges since (parent, n) are a block.
                            var nodes = Set<Int32>()
                            while let e = edges.popLast() {
                                nodes.insert(e.0); nodes.insert(e.1)
                                if e.0 == parent && e.1 == n { break }
                            }
                            result.append(nodes.sorted())
                        }
                    }
                }
            }
            return result
        }

        /// No path is longer: a path runs through a chain of blocks of the block-cut tree, without
        /// coming back to a block, and within each block it is a path too (at most the block's
        /// colour bound, see `upperBound`). The best chain is a heaviest path in that tree. Also
        /// returns that chain's tiles, where the snake must be.
        func blockBound() -> (bound: Int, tiles: [Int32]) {
            let blocks = blocks()
            func weight(_ b: [Int32]) -> Int {
                let black = b.count { (xs[Int($0)] + ys[Int($0)]) & 1 == 0 }
                return min(b.count, 2 * min(black, b.count - black) + 1)
            }
            // The tree: block nodes 0..<blocks.count, then one node per cut tile (weight -1: it is
            // counted in both blocks next to it).
            var cutNode = [Int32: Int](), membership = [Int32: Int]()
            for b in blocks { for n in b { membership[n, default: 0] += 1 } }
            var adjacency = [[Int]](repeating: [], count: blocks.count), weights = blocks.map(weight)
            for (i, b) in blocks.enumerated() {
                for n in b where membership[n, default: 0] > 1 {
                    let c: Int
                    if let existing = cutNode[n] { c = existing } else {
                        c = weights.count
                        cutNode[n] = c
                        weights.append(-1)
                        adjacency.append([])
                    }
                    adjacency[i].append(c)
                    adjacency[c].append(i)
                }
            }
            // Heaviest path: for every node, the best downward chain; the best path joins two.
            var best = (weight: Int.min, top: -1, a: -1, b: -1)
            var down = [Int](repeating: 0, count: weights.count), downChild = [Int](repeating: -1, count: weights.count)
            var seen = [Bool](repeating: false, count: weights.count)
            for root in 0..<weights.count where !seen[root] {
                var order = [Int](), parent = [Int: Int](), stack = [root]
                seen[root] = true
                while let v = stack.popLast() {
                    order.append(v)
                    for w in adjacency[v] where !seen[w] { seen[w] = true; parent[w] = v; stack.append(w) }
                }
                for v in order.reversed() {
                    var first = (0, -1), second = (0, -1)
                    for w in adjacency[v] where parent[w] == v && down[w] > 0 {
                        if down[w] > first.0 { second = first; first = (down[w], w) } else if down[w] > second.0 { second = (down[w], w) }
                    }
                    down[v] = weights[v] + first.0
                    downChild[v] = first.1
                    let through = weights[v] + first.0 + second.0
                    if through > best.weight { best = (through, v, first.1, second.1) }
                }
            }
            guard best.top >= 0 else { return (0, []) }
            var chain = Set<Int32>()
            func follow(_ start: Int) {
                var v = start
                while v >= 0 {
                    if v < blocks.count { chain.formUnion(blocks[v]) }
                    v = downChild[v]
                }
            }
            if best.top < blocks.count { chain.formUnion(blocks[best.top]) }
            follow(best.a)
            follow(best.b)
            return (max(best.weight, 1), chain.sorted())
        }

        // MARK: Complete search (small groups)

        /// The longest path, or nil when the search needs more than `maxSteps` steps.
        func exactLongest(maxSteps: Int) -> [Int32]? {
            var best = [Int32](), path = [Int32](), on = [Bool](repeating: false, count: count)
            var steps = 0, aborted = false
            let upper = upperBound

            /// The tiles still reachable from `n` without crossing the path: the path can't get longer than that.
            func reachable(from n: Int32) -> Int {
                var seen = on, stack = [n], size = 0
                seen[Int(n)] = true
                while let m = stack.popLast() {
                    size += 1
                    for d in 0..<4 {
                        let q = neighbour(m, d)
                        guard q >= 0, !seen[Int(q)] else { continue }
                        seen[Int(q)] = true
                        stack.append(q)
                    }
                }
                return size
            }

            func extend(_ n: Int32) {
                guard !aborted, best.count < upper else { return }
                steps += 1
                if steps > maxSteps { aborted = true; return }
                path.append(n)
                on[Int(n)] = true
                if path.count > best.count { best = path }
                for d in 0..<4 {
                    let q = neighbour(n, d)
                    if q >= 0, !on[Int(q)], path.count + reachable(from: q) > best.count { extend(q) }
                }
                on[Int(n)] = false
                path.removeLast()
            }

            // Leaves first: a long path often ends at one, which makes the bound bite early.
            let order = (0..<Int32(count)).sorted { (degree($0), $0) < (degree($1), $1) }
            for start in order {
                extend(start)
                if aborted { return nil }
            }
            return best
        }

        // MARK: Heuristic (big groups)

        /// A long path: grown from several starting tiles (the ends of the group first, then random
        /// ones), each improved (`improve`); the longest wins. The randomness is seeded by the group,
        /// so the same tiles give the same snake.
        func heuristicLongest(maxSteps: Int, upper: Int) -> [Int32] {
            var random = SplitMix(seed: UInt64(bitPattern: keys[0]))
            let ends = starts(), rounds = 8
            var best = [Int32]()
            for round in 0..<rounds {
                guard best.count < upper else { break }
                var budget = Budget(left: maxSteps / rounds)
                let start = round < ends.count ? ends[round] : Int32(random.next() % UInt64(count))
                var path = walk(from: start, budget: &budget)
                improve(&path, budget: &budget, upper: upper, random: &random)
                if path.count > best.count { best = path }
            }
            return best
        }

        /// A small seeded random number generator (SplitMix64).
        struct SplitMix {
            var state: UInt64
            init(seed: UInt64) { state = seed }
            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }

        struct Budget {
            var left: Int
            mutating func spend(_ n: Int = 1) -> Bool {
                left -= n
                return left > 0
            }
        }

        /// Where to start: the ends of the group (tiles with one neighbour, and the tiles farthest
        /// apart), at most six.
        func starts() -> [Int32] {
            func farthest(from s: Int32) -> Int32 {
                var dist = [Int](repeating: -1, count: count), queue = [s], head = 0, last = s
                dist[Int(s)] = 0
                while head < queue.count {
                    let n = queue[head]
                    head += 1
                    last = n
                    for q in neighbours(n) where q >= 0 && dist[Int(q)] < 0 {
                        dist[Int(q)] = dist[Int(n)] + 1
                        queue.append(q)
                    }
                }
                return last
            }
            let a = farthest(from: 0), b = farthest(from: a)
            var result = [a, b]
            for leaf in (0..<Int32(count)) where degree(leaf) <= 1 && !result.contains(leaf) {
                result.append(leaf)
                if result.count >= 6 { break }
            }
            return result
        }

        /// Walks from `start` while it can (`continueWalk`).
        func walk(from start: Int32, budget: inout Budget) -> [Int32] {
            var on = [Bool](repeating: false, count: count)
            var path = [start]
            on[Int(start)] = true
            continueWalk(&path, on: &on, budget: &budget)
            return path
        }

        private func free(_ n: Int32, _ on: [Bool]) -> Int {
            var free = 0
            for d in 0..<4 {
                let q = neighbour(n, d)
                if q >= 0, !on[Int(q)] { free += 1 }
            }
            return free
        }

        /// Extends the path at its last tile while it can, each time to the free neighbour with the
        /// fewest free neighbours of its own (Warnsdorff's rule: tiles that would be cut off
        /// first), keeping straight on a tie. A dead end (no free neighbour after it) only as the
        /// last step. With `random`, ties are broken at random instead.
        private func continueWalk(_ path: inout [Int32], on: inout [Bool], budget: inout Budget, random: UnsafeMutablePointer<SplitMix>? = nil) {
            var direction = -1
            if path.count >= 2 {
                direction = neighbours(path[path.count - 2]).firstIndex(of: path[path.count - 1]) ?? -1
            }
            while budget.spend() {
                let n = path[path.count - 1]
                var choice: (node: Int32, direction: Int, score: Int)?
                for d in 0..<4 {
                    let q = neighbour(n, d)
                    guard q >= 0, !on[Int(q)] else { continue }
                    let onward = free(q, on) - 1 // without n, which is taken
                    var score = onward <= 0 ? 100 : onward * 4
                    if let random { score += Int(random.pointee.next() % 4) } else if d != direction { score += 1 }
                    if choice == nil || score < choice!.score { choice = (q, d, score) }
                }
                guard let c = choice else { return }
                path.append(c.node)
                on[Int(c.node)] = true
                direction = c.direction
            }
        }

        /// Makes the path longer until the budget runs out or it reaches `upper`: first the local
        /// moves (`localImprove`); then, while stuck, cuts a random piece off an end, grows it
        /// again with some randomness, and keeps the result when it is at least as long.
        func improve(_ path: inout [Int32], budget: inout Budget, upper: Int, random: inout SplitMix) {
            var on = [Bool](repeating: false, count: count)
            for n in path { on[Int(n)] = true }
            localImprove(&path, on: &on, budget: &budget, upper: upper, random: &random)
            var best = path
            while budget.left > 0, best.count < upper, best.count >= 4 {
                var trial = random.next() % 2 == 0 ? best : best.reversed()
                let cut = 1 + Int(random.next() % UInt64(min(64, trial.count / 3)))
                trial.removeLast(cut)
                var trialOn = [Bool](repeating: false, count: count)
                for n in trial { trialOn[Int(n)] = true }
                guard budget.spend(count / 2 + trial.count) else { break } // what the copies cost
                withUnsafeMutablePointer(to: &random) { continueWalk(&trial, on: &trialOn, budget: &budget, random: $0) }
                localImprove(&trial, on: &trialOn, budget: &budget, upper: upper, random: &random)
                if trial.count >= best.count { best = trial }
            }
            path = best
        }

        /// Extends both ends, folds in detours, and rotates (`rotate`) until none of these helps.
        private func localImprove(_ path: inout [Int32], on: inout [Bool], budget: inout Budget, upper: Int, random: inout SplitMix) {
            var changed = true
            while changed, budget.left > 0, path.count < upper {
                changed = false
                for _ in 0..<2 {
                    let before = path.count
                    continueWalk(&path, on: &on, budget: &budget)
                    if path.count > before { changed = true }
                    path.reverse()
                }
                if insertDetours(&path, on: &on, budget: &budget) { changed = true }
                if !changed, rotate(&path, on: &on, budget: &budget, random: &random) { changed = true }
            }
        }

        /// Replaces path steps a→b by a→(free tiles)→b where such a detour exists; the shortest
        /// detour each time (it can grow again later). Returns whether the path got longer.
        private func insertDetours(_ path: inout [Int32], on: inout [Bool], budget: inout Budget) -> Bool {
            var grew = false
            var i = 0
            while i < path.count - 1, budget.left > 0 {
                let a = path[i], b = path[i + 1]
                if let detour = detour(from: a, to: b, on: on, budget: &budget) {
                    path.insert(contentsOf: detour, at: i + 1)
                    for n in detour { on[Int(n)] = true }
                    grew = true
                    // Stay on a: the new step a→(first tile of the detour) may take another.
                } else {
                    i += 1
                }
            }
            return grew
        }

        /// The shortest run of free tiles from a neighbour of `a` to a neighbour of `b` (searching
        /// at most 400 tiles).
        private func detour(from a: Int32, to b: Int32, on: [Bool], budget: inout Budget) -> [Int32]? {
            guard free(a, on) > 0, free(b, on) > 0 else { return nil }
            generation &+= 1
            var queue = [Int32]()
            for d in 0..<4 {
                let s = neighbour(a, d)
                if s >= 0, !on[Int(s)] { queue.append(s); mark[Int(s)] = generation; previous[Int(s)] = -1 }
            }
            var head = 0
            while head < queue.count, head < 400 {
                guard budget.spend() else { return nil }
                let n = queue[head]
                head += 1
                if (0..<4).contains(where: { neighbour(n, $0) == b }) {
                    var run = [n], m = previous[Int(n)]
                    while m >= 0 { run.append(m); m = previous[Int(m)] }
                    return run.reversed()
                }
                for d in 0..<4 {
                    let q = neighbour(n, d)
                    guard q >= 0, !on[Int(q)], mark[Int(q)] != generation else { continue }
                    mark[Int(q)] = generation
                    previous[Int(q)] = n
                    queue.append(q)
                }
            }
            return nil
        }

        /// Pósa rotations: when the end tile has a neighbour p[j] on the path, p[0…j] +
        /// reversed(p[j+1…]) is a path as long, ending at p[j+1]. Rotates at random (now and then
        /// switching ends) until an end has a free neighbour, then extends it. Returns whether the
        /// path got longer.
        private func rotate(_ path: inout [Int32], on: inout [Bool], budget: inout Budget, random: inout SplitMix) -> Bool {
            guard path.count >= 3 else { return false }
            var position = [Int](repeating: -1, count: count)
            for (i, n) in path.enumerated() { position[Int(n)] = i }
            let tries = min(4 * path.count, 20_000)
            for _ in 0..<tries {
                let last = path.count - 1
                let choices = neighbours(path[last]).filter { $0 >= 0 && position[Int($0)] >= 0 && position[Int($0)] < last - 1 }
                if choices.isEmpty || random.next() % 8 == 0 {
                    // Nothing to rotate with here, or now and then: work on the other end.
                    path.reverse()
                    for (i, n) in path.enumerated() { position[Int(n)] = i }
                    guard budget.spend(path.count + 1) else { return false }
                    continue
                }
                let j = position[Int(choices[Int(random.next() % UInt64(choices.count))])]
                guard budget.spend(last - j + 1) else { return false }
                path[(j + 1)...].reverse()
                for i in (j + 1)...last { position[Int(path[i])] = i }
                if free(path[last], on) > 0 {
                    let before = path.count
                    continueWalk(&path, on: &on, budget: &budget)
                    return path.count > before
                }
            }
            return false
        }
    }
}
