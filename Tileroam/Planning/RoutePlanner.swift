import Foundation

struct PlannedRoute: Sendable {
    enum Source: Sendable, Equatable {
        case planned
        case imported(name: String)
    }

    var id = UUID()
    var source: Source
    var coordinates: [GeoPoint]
    /// Meters.
    var distance: Double
    /// Seconds (planned routes only).
    var duration: Double?
    /// Waypoints in visiting order, with the target name.
    var stops: [(point: GeoPoint, name: String)]
    var coverage: RouteCoverage
    /// Selected targets the route does not pass through.
    var missed: [String]

    var name: String {
        switch source {
        case .planned: String(localized: "Tileroam route")
        case .imported(let name): name
        }
    }
}

/// Plans the shortest cycling round trip from a start point through all targets.
///
/// A target counts as visited when the route passes any point inside it, so each target
/// offers many candidate points and the planner picks the ones that keep the route short.
enum RoutePlanner {
    static let maxTargets = 50
    /// The longest round trip planned, as the crow flies along the stops. Valhalla allows more
    /// (valhalla.json: bicycle max_distance 1,000 km), so this check comes first, with a clear
    /// message.
    static let maxLoopKilometers = 500

    /// The round trip's stops in visiting order, start to start, as `plan` will order them: one
    /// point per target (the candidate nearest the start), ordered on straight-line distances.
    /// Used before routing, to know which map tiles the route will need and how long it is.
    static func approximateLoop(start: GeoPoint, targets: [TargetGeometry]) -> [GeoPoint] {
        let initial = targets.compactMap { $0.candidates().min { Geo.distance($0, start) < Geo.distance($1, start) } }
        let points = [start] + initial
        let order = points.count > 2 ? TripSolver.roundTrip(points.map { a in points.map { b in Geo.distance(a, b) } }) : Array(points.indices)
        return order.map { points[$0] } + [start]
    }

    static func length(_ path: [GeoPoint]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) }
    }

    /// Targets in visiting order, each with the point the route should pass.
    static func plan(start: GeoPoint, targets: [TargetGeometry], client: any CyclingRouter,
                     progress: @MainActor @Sendable (String) -> Void) async throws -> [(target: TargetGeometry, point: GeoPoint)] {
        let candidates = targets.map { t in
            t.candidates().sorted { Geo.distance($0, start) < Geo.distance($1, start) }
        }
        let usable = targets.indices.filter { !candidates[$0].isEmpty }

        // 1. Visiting order (see TripSolver), on straight-line distances.
        await progress(String(localized: "Finding the best order…"))
        let initial = usable.map { candidates[$0][0] }
        let order: [Int]
        if usable.count > 1 {
            order = try await client.tripOrder([start] + initial).dropFirst().map { usable[$0 - 1] }
        } else {
            order = usable
        }

        // 2. Move each waypoint to the candidate that keeps the detour smallest.
        let chosen = refine(start: start, candidates: order.map { candidates[$0] }, distance: Geo.distance)
        return zip(order, chosen).map { (targets[$0.0], candidates[$0.0][$0.1]) }
    }

    /// Chooses one candidate per target (in visiting order) minimizing distance to the neighbours.
    /// Returns the index of the chosen candidate for each target.
    static func refine(start: GeoPoint, candidates: [[GeoPoint]],
                       distance: (GeoPoint, GeoPoint) -> Double, passes: Int = 3) -> [Int] {
        var chosen = candidates.map { _ in 0 }
        guard !candidates.isEmpty else { return [] }
        func point(_ i: Int) -> GeoPoint {
            i < 0 || i >= candidates.count ? start : candidates[i][chosen[i]]
        }
        for _ in 0..<passes {
            for i in candidates.indices {
                let prev = point(i - 1), next = point(i + 1)
                var best = chosen[i]
                var bestCost = Double.infinity
                for (k, c) in candidates[i].enumerated() {
                    let cost = distance(prev, c) + distance(c, next)
                    if cost < bestCost {
                        bestCost = cost
                        best = k
                    }
                }
                chosen[i] = best
            }
        }
        return chosen
    }

    /// Full planning: order, waypoints, route, and replacing waypoints that snap outside their target.
    static func planRoute(start: GeoPoint, targets: [TargetGeometry], client: any CyclingRouter,
                          coverage: @Sendable ([GeoPoint]) -> RouteCoverage,
                          progress: @MainActor @Sendable (String) -> Void) async throws -> PlannedRoute {
        let planned = try await plan(start: start, targets: targets, client: client, progress: progress)
        let ordered = planned.map(\.target)
        var waypoints = planned.map(\.point)

        var route: RoutedPath?
        for attempt in 0..<3 {
            await progress(attempt == 0 ? String(localized: "Planning the cycling route…") : String(localized: "Improving the route…"))
            // Climbs are ridden from their bottom along points up to the top.
            var points = [start], primary = [Int]()
            for (i, target) in ordered.enumerated() {
                primary.append(points.count)
                points.append(waypoints[i])
                points += target.climbVia
            }
            let r = try await client.route(points + [start])
            route = r
            // Waypoints are snapped to the nearest cycle road; if that moved one out of its
            // target, try the candidate closest to the snapped point that is still inside.
            var changed = false
            for (i, target) in ordered.enumerated() where primary[i] < r.snapped.count && target.climb == nil {
                let snapped = r.snapped[primary[i]]
                if !target.contains(snapped) {
                    let inside = target.candidates().filter { $0 != waypoints[i] }
                    if let better = inside.min(by: { Geo.distance($0, snapped) < Geo.distance($1, snapped) }) {
                        waypoints[i] = better
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        guard let route else { throw RoutingError.engine("no route") }

        await progress(String(localized: "Checking which tiles and areas you pass…"))
        let cov = coverage(route.coordinates)
        let missed = targets.filter { !cov.contains($0.target) }.map(\.name)
        return PlannedRoute(source: .planned, coordinates: route.coordinates, distance: route.distance,
                            duration: route.duration, stops: zip(waypoints, ordered).map { ($0, $1.name) },
                            coverage: cov, missed: missed)
    }
}
