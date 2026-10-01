import MapKit
import UIKit

/// Area outlines converted to map points once, shared between overlays.
final class AreaGeometry: @unchecked Sendable {
    struct Shape {
        let code: String
        let bounds: MKMapRect
        /// Rings (outer + holes) per polygon, in map points.
        let rings: [[MKMapPoint]]
    }

    let shapes: [Shape]
    let bounds: MKMapRect

    init(_ areas: [Area]) {
        var all = MKMapRect.null
        shapes = areas.map { area in
            var rect = MKMapRect.null
            let rings = area.polygons.flatMap(\.rings).map { ring in
                ring.map { p -> MKMapPoint in
                    let mp = MKMapPoint(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon))
                    rect = rect.union(MKMapRect(origin: mp, size: MKMapSize(width: 0, height: 0)))
                    return mp
                }
            }
            all = all.union(rect)
            return Shape(code: area.code, bounds: rect, rings: rings)
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
        for shape in o.geometry.shapes where shape.bounds.intersects(rect) {
            let isUnvisited = !o.visited.contains(shape.code) && !o.selected.contains(shape.code) && !o.highlight.contains(shape.code)
            if isUnvisited, max(shape.bounds.width, shape.bounds.height) < minSize { continue }
            let path = o.selected.contains(shape.code) ? selected
                : o.highlight.contains(shape.code) ? highlight
                : o.visited.contains(shape.code) ? visited : unvisited
            for ring in shape.rings where ring.count > 2 {
                path.move(to: point(for: ring[0]))
                for p in ring.dropFirst() { path.addLine(to: point(for: p)) }
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
