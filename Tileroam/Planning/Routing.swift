import Foundation

/// The cycling router behind route planning (Valhalla on the device, see `ValhallaRouter`).
protocol CyclingRouter: Sendable {
    /// Visiting order for a round trip starting at `points[0]`: indices into `points`, starting with 0.
    func tripOrder(_ points: [GeoPoint]) async throws -> [Int]
    /// The cycling route through `points` in this order.
    func route(_ points: [GeoPoint]) async throws -> RoutedPath
}

struct RoutedPath: Sendable {
    var coordinates: [GeoPoint]
    /// Meters.
    var distance: Double
    /// Seconds.
    var duration: Double
    /// Input points snapped to the road network, in input order.
    var snapped: [GeoPoint]
}

enum RoutingError: LocalizedError, Equatable {
    /// A point lies outside the countries the routing data covers.
    case outsideRegion
    /// The routing data couldn't be downloaded or opened.
    case dataUnavailable(String)
    /// The routing engine couldn't find a route.
    case engine(String)
    /// The map data to download is large and the device isn't on Wi-Fi.
    case waitingForWiFi(bytes: Int)

    var errorDescription: String? {
        switch self {
        case .outsideRegion:
            String(localized: "Route planning is available in the Netherlands, Belgium, Luxembourg and Germany. The starting point and all selected items must be there.")
        case .dataUnavailable(let message):
            String(localized: "The route planning data couldn't be loaded: \(message)")
        case .engine(let message):
            String(localized: "Route planning failed: \(message)")
        case .waitingForWiFi(let bytes):
            String(localized: "Map data for this area (\(MapDataDownloads.format(bytes))) downloads on Wi-Fi.")
        }
    }
}

/// Orders the stops of a round trip from a cost matrix (distances between all points):
/// nearest neighbour, then 2-opt and relocating single stops until nothing improves.
enum TripSolver {
    /// `cost[i][j]` is the cost from point i to point j; point 0 is the start and end.
    /// Returns the visiting order, starting with 0 (the return to 0 is implied).
    static func roundTrip(_ cost: [[Double]]) -> [Int] {
        let n = cost.count
        guard n > 2 else { return Array(0..<n) }

        // Nearest neighbour from the start.
        var order = [0]
        var left = Set(1..<n)
        while !left.isEmpty {
            let last = order[order.count - 1]
            let next = left.min { cost[last][$0] < cost[last][$1] || (cost[last][$0] == cost[last][$1] && $0 < $1) }!
            order.append(next)
            left.remove(next)
        }

        func total(_ o: [Int]) -> Double {
            zip(o, o.dropFirst() + [0]).reduce(0) { $0 + cost[$1.0][$1.1] }
        }

        var best = total(order)
        var improved = true
        var rounds = 0
        while improved && rounds < 100 {
            improved = false
            rounds += 1
            // 2-opt: reverse a section (costs may be asymmetric, so compare whole tours).
            for i in 1..<(n - 1) {
                for j in (i + 1)..<n {
                    var candidate = order
                    candidate[i...j].reverse()
                    let c = total(candidate)
                    if c < best - 1e-9 {
                        order = candidate
                        best = c
                        improved = true
                    }
                }
            }
            // Relocate one stop to another position.
            for i in 1..<n {
                for j in 1..<n where j != i {
                    var candidate = order
                    let stop = candidate.remove(at: i)
                    candidate.insert(stop, at: j)
                    let c = total(candidate)
                    if c < best - 1e-9 {
                        order = candidate
                        best = c
                        improved = true
                    }
                }
            }
        }
        return order
    }
}
