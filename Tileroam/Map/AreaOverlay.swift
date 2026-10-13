import MapKit
import UIKit

/// Area outlines converted to map points once, shared between overlays. Compact: the municipalities
/// of seven countries are some 5 million points, so each area keeps its points in one Float32
/// array, relative to its own corner (exact to a fraction of a map point), instead of an array of
/// MKMapPoints (two Doubles) per ring: half the memory.
final class AreaGeometry: @unchecked Sendable {
    struct Shape {
        let code: String
        let bounds: MKMapRect
        /// x and y of every point of every ring (outer + holes, per polygon), in map points from
        /// `bounds.origin`.
        let points: [Float]
        /// Per ring, the index of the point after its last (points counted in pairs).
        let ringEnds: [Int32]

        /// The point at `index` (counted in pairs) as a map point.
        @inline(__always) func point(_ index: Int) -> MKMapPoint {
            MKMapPoint(x: bounds.origin.x + Double(points[2 &* index]), y: bounds.origin.y + Double(points[2 &* index &+ 1]))
        }
    }

    let shapes: [Shape]
    let bounds: MKMapRect

    init(_ areas: [Area]) {
        var all = MKMapRect.null
        shapes = areas.map { area in
            let rings = area.polygons.flatMap(\.rings).map { ring in
                ring.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)) }
            }
            var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
            for ring in rings {
                for p in ring { minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y) }
            }
            let rect = minX <= maxX ? MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY) : .null
            var points = [Float](), ends = [Int32]()
            points.reserveCapacity(rings.reduce(0) { $0 + $1.count } * 2)
            for ring in rings {
                for p in ring {
                    points.append(Float(p.x - minX))
                    points.append(Float(p.y - minY))
                }
                ends.append(Int32(points.count / 2))
            }
            all = all.union(rect)
            return Shape(code: area.code, bounds: rect, points: points, ringEnds: ends)
        }
        bounds = all
    }
}

/// Draws an area challenge (municipalities, postcodes): visited areas filled, others outlined.
/// Only the areas intersecting each tile are drawn, which keeps thousands of areas fast.
final class AreaOverlay: NSObject, MKOverlay, @unchecked Sendable {
    let geometry: AreaGeometry
    let visited: Set<String>
    /// Route planning: areas selected to visit, and new areas the route passes.
    let selected: Set<String>
    let highlight: Set<String>
    var boundingMapRect: MKMapRect { geometry.bounds }
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: geometry.bounds.midX, y: geometry.bounds.midY).coordinate }

    init(geometry: AreaGeometry, visited: Set<String>, selected: Set<String> = [], highlight: Set<String> = []) {
        self.geometry = geometry
        self.visited = visited
        self.selected = selected
        self.highlight = highlight
    }

    /// Draws exactly what `other` draws, so the map can keep this one (no redraw).
    func shows(sameAs other: AreaOverlay) -> Bool {
        geometry === other.geometry && visited == other.visited && selected == other.selected && highlight == other.highlight
    }
}

final class AreaRenderer: MKOverlayRenderer {
    private let visitedFill = UIColor.systemGreen.withAlphaComponent(0.4).cgColor
    private let visitedStroke = UIColor.systemGreen.withAlphaComponent(0.9).cgColor
    private let unvisitedFill = UIColor.systemGray.withAlphaComponent(0.10).cgColor
    private let unvisitedStroke = UIColor.systemGray.withAlphaComponent(0.55).cgColor
    private let selectedFill = UIColor.systemOrange.withAlphaComponent(0.5).cgColor
    private let highlightFill = UIColor.systemOrange.withAlphaComponent(0.2).cgColor
    private let highlightStroke = UIColor.systemOrange.cgColor

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let o = overlay as? AreaOverlay else { return }
        // Tiles overlap a little so outlines at tile edges are complete.
        let rect = mapRect.insetBy(dx: -mapRect.width * 0.05, dy: -mapRect.height * 0.05)
        let visited = CGMutablePath()
        let unvisited = CGMutablePath()
        let selected = CGMutablePath()
        let highlight = CGMutablePath()
        // Zoomed far out over thousands of areas: skip unvisited areas smaller than ~2 points.
        let minSize = 2 / zoomScale
        let minStep = 1.5 / zoomScale
        for shape in o.geometry.shapes where shape.bounds.intersects(rect) {
            let isUnvisited = !o.visited.contains(shape.code) && !o.selected.contains(shape.code) && !o.highlight.contains(shape.code)
            if isUnvisited, max(shape.bounds.width, shape.bounds.height) < minSize { continue }
            let path = o.selected.contains(shape.code) ? selected
                : o.highlight.contains(shape.code) ? highlight
                : o.visited.contains(shape.code) ? visited : unvisited
            var start = 0
            for end in shape.ringEnds.lazy.map(Int.init) {
                defer { start = end }
                guard end - start > 2 else { continue }
                // Points closer than 1.5 screen points to the last one drawn add nothing visible:
                // zoomed out over seven countries (5 million points) that's most of them.
                var last = shape.point(start)
                path.move(to: point(for: last))
                for i in (start + 1)..<end {
                    let p = shape.point(i)
                    guard abs(p.x - last.x) + abs(p.y - last.y) >= minStep else { continue }
                    path.addLine(to: point(for: p))
                    last = p
                }
                path.closeSubpath()
            }
        }
        let lineWidth = 1 / zoomScale
        // Outlines of unvisited areas only once they're large enough on screen.
        let detailed = zoomScale > 1 / 400

        context.addPath(unvisited)
        context.setFillColor(unvisitedFill)
        context.fillPath(using: .evenOdd)
        if detailed {
            context.addPath(unvisited)
            context.setStrokeColor(unvisitedStroke)
            context.setLineWidth(lineWidth)
            context.strokePath()
        }
        context.addPath(visited)
        context.setFillColor(visitedFill)
        context.fillPath(using: .evenOdd)
        context.addPath(visited)
        context.setStrokeColor(visitedStroke)
        context.setLineWidth(lineWidth * (detailed ? 1.5 : 0.75))
        context.strokePath()

        context.addPath(highlight)
        context.setFillColor(highlightFill)
        context.fillPath(using: .evenOdd)
        context.addPath(highlight)
        context.addPath(selected)
        context.setStrokeColor(highlightStroke)
        context.setLineWidth(lineWidth * 2)
        context.strokePath()
        context.addPath(selected)
        context.setFillColor(selectedFill)
        context.fillPath(using: .evenOdd)
    }
}
