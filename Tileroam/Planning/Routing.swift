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

/// Why downloading map data failed.
enum DownloadProblem: Error, Equatable, Sendable {
    case offline
    case timedOut
    case connection(String)
    case server(Int)
    case damaged

    /// Worth trying again right away.
    var isTransient: Bool {
        switch self {
        case .timedOut, .connection, .damaged: true
        case .server(let status): status >= 500 || status == 429
        case .offline: false
        }
    }

    var description: String {
        switch self {
        case .offline:
            String(localized: "There's no internet connection, and map data for this area still has to be downloaded. Try again when you're online.")
        case .timedOut:
            String(localized: "Downloading the map data timed out. Check your connection and try again; what was downloaded is kept.")
        case .connection(let message):
            String(localized: "The map data couldn't be downloaded (\(message)). Try again; what was downloaded is kept.")
        case .server(404):
            String(localized: "Map data for this area isn't available yet. Please try again later.")
        case .server(let status):
            String(localized: "The map data server had a problem (\(status)). Try again later; what was downloaded is kept.")
        case .damaged:
            String(localized: "Map data arrived damaged several times. Try again; what was downloaded is kept.")
        }
    }
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
    /// Downloading map data failed (after retries).
    case download(DownloadProblem)
    /// The stops are too far apart to plan one round trip (straight-line kilometers).
    case tooLong(km: Int)

    var errorDescription: String? {
        switch self {
        case .outsideRegion:
            String(localized: "Route planning is available in the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria. The starting point and all selected items must be there.")
        case .dataUnavailable(let message):
            String(localized: "The route planning data couldn't be loaded: \(message)")
        case .engine(let message):
            Self.explain(message)
        case .download(let problem):
            problem.description
        case .tooLong(let km):
            String(localized: "These items are too far apart for one round trip (about \(km) km as the crow flies; up to \(RoutePlanner.maxLoopKilometers) km is possible). Select fewer or closer items.")
        case .waitingForWiFi(let bytes):
            String(localized: "Map data for this area (\(MapDataDownloads.format(bytes))) downloads on Wi-Fi.")
        }
    }

    /// Whether a wider corridor of map data could help: only when no path was found (the route
    /// may need a detour outside it), not for distance limits or points away from any road.
    var widerAreaMayHelp: Bool {
        guard case .engine(let message) = self else { return false }
        let m = message.lowercased()
        return !m.contains("exceeds the max distance") && !m.contains("no suitable edges")
    }

    /// Valhalla's messages in words a cyclist understands, for the ones that come up.
    static func explain(_ message: String) -> String {
        let m = message.lowercased()
        if m.contains("exceeds the max distance") {
            return String(localized: "These items are too far apart for one round trip. Select fewer or closer items.")
        }
        if m.contains("no path could be found") || m.contains("no route") {
            return String(localized: "No cycling route was found between some of the stops, for example across water without a bridge or ferry. Try other items or another starting point.")
        }
        if m.contains("no suitable edges") {
            return String(localized: "The starting point or a selected item isn't near a road or path that can be cycled. Choose another one.")
        }
        return String(localized: "Route planning failed: \(message)")
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
