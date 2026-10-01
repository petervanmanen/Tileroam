import Foundation

enum Geo {
    /// Approximate distance in meters (equirectangular; fine for short distances).
    static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let meanLat = (a.lat + b.lat) / 2 * .pi / 180
        let dx = (b.lon - a.lon) * cos(meanLat) * 111_320
        let dy = (b.lat - a.lat) * 110_574
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Points along the track with at most `spacing` meters between them.
    /// Segments longer than `maxGap` (e.g. GPS dropouts, transport) are not interpolated.
    static func densified(_ points: [GeoPoint], spacing: Double, maxGap: Double = 2_000) -> [GeoPoint] {
        guard var previous = points.first else { return [] }
        var result = [previous]
        for p in points.dropFirst() {
            let d = distance(previous, p)
            if d > spacing, d <= maxGap {
                let steps = Int((d / spacing).rounded(.up))
                for s in 1..<steps {
                    let t = Double(s) / Double(steps)
                    result.append(GeoPoint(lat: previous.lat + (p.lat - previous.lat) * t,
                                           lon: previous.lon + (p.lon - previous.lon) * t))
                }
            }
            result.append(p)
            previous = p
        }
        return result
    }

    /// Douglas-Peucker simplification with a tolerance in meters.
    static func simplify(_ points: [GeoPoint], tolerance: Double) -> [GeoPoint] {
        guard points.count > 2 else { return points }
        let refLat = points[0].lat * .pi / 180
        let kx = cos(refLat) * 111_320
        let ky = 110_574.0
        let xs = points.map { $0.lon * kx }
        let ys = points.map { $0.lat * ky }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        let tol2 = tolerance * tolerance

        while let (first, last) = stack.popLast() {
            guard last > first + 1 else { continue }
            let ax = xs[first], ay = ys[first]
            let dx = xs[last] - ax, dy = ys[last] - ay
            let len2 = dx * dx + dy * dy
            var maxDist2 = 0.0
            var index = first
            for i in (first + 1)..<last {
                var px = xs[i] - ax, py = ys[i] - ay
                if len2 > 0 {
                    let t = max(0, min(1, (px * dx + py * dy) / len2))
                    px -= t * dx
                    py -= t * dy
                }
                let d2 = px * px + py * py
                if d2 > maxDist2 {
                    maxDist2 = d2
                    index = i
                }
            }
            if maxDist2 > tol2 {
                keep[index] = true
                stack.append((first, index))
                stack.append((index, last))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }
}
