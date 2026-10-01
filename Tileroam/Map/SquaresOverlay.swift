import MapKit
import UIKit

/// World-wide overlay drawing Web Mercator tiles of one zoom level: visited tiles filled,
/// grid lines for unvisited tiles when zoomed in, the max square outline, and route
/// planning selections. Tiles are axis-aligned rectangles in MapKit's map points.
final class TilesOverlay: NSObject, MKOverlay, @unchecked Sendable {
    let zoom: TileZoom
    let visited: Set<Int64>
    /// Route planning: tiles selected to visit, and new tiles the route passes.
    let selected: Set<Int64>
    let highlight: Set<Int64>
    let maxSquareOrigin: (x: Int, y: Int)?
    let maxSquare: Int

    let boundingMapRect = MKMapRect.world
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    /// Tile edge length in map points.
    var tileSize: Double { MKMapSize.world.width / TileGrid.tilesPerSide(zoom) }

    init(zoom: TileZoom, visited: Set<Int64>, stats: SquareStats, selected: Set<Int64> = [], highlight: Set<Int64> = []) {
        self.zoom = zoom
        self.visited = visited
        self.selected = selected
        self.highlight = highlight
        self.maxSquare = stats.maxSquare
        self.maxSquareOrigin = stats.maxSquareOrigin
    }
}

final class TilesRenderer: MKOverlayRenderer {
    private let visitedFill = UIColor.systemGreen.withAlphaComponent(0.45).cgColor
    private let visitedStroke = UIColor.systemGreen.withAlphaComponent(0.8).cgColor
    private let gridStroke = UIColor.systemGray.withAlphaComponent(0.55).cgColor
    private let maxSquareStroke = UIColor.systemOrange.cgColor
    private let selectedFill = UIColor.systemOrange.withAlphaComponent(0.55).cgColor
    private let highlightFill = UIColor.systemOrange.withAlphaComponent(0.2).cgColor
    private let highlightStroke = UIColor.systemOrange.cgColor

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let o = overlay as? TilesOverlay else { return }
        let size = o.tileSize
        let maxIndex = Int(TileGrid.tilesPerSide(o.zoom)) - 1
        let x0 = max(Int((mapRect.minX / size).rounded(.down)), 0)
        let x1 = min(Int((mapRect.maxX / size).rounded(.down)), maxIndex)
        let y0 = max(Int((mapRect.minY / size).rounded(.down)), 0)
        let y1 = min(Int((mapRect.maxY / size).rounded(.down)), maxIndex)
        guard x0 <= x1, y0 <= y1 else { return }

        let tileInPoints = size * zoomScale
        let lineWidth = 1 / zoomScale

        func rect(_ x: Int, _ y: Int, _ w: Int = 1) -> CGRect {
            self.rect(for: MKMapRect(x: Double(x) * size, y: Double(y) * size, width: size * Double(w), height: size * Double(w)))
        }
        func path(_ keys: Set<Int64>) -> CGMutablePath {
            let p = CGMutablePath()
            let cellsInTile = (x1 - x0 + 1) * (y1 - y0 + 1)
            if cellsInTile < keys.count {
                for y in y0...y1 { for x in x0...x1 where keys.contains(TileGrid.key(x: x, y: y)) { p.addRect(rect(x, y)) } }
            } else {
                for key in keys {
                    let c = TileGrid.cell(of: key)
                    if (x0...x1).contains(c.x), (y0...y1).contains(c.y) { p.addRect(rect(c.x, c.y)) }
                }
            }
            return p
        }

        // Visited tiles.
        let visited = path(o.visited)
        context.addPath(visited)
        context.setFillColor(visitedFill)
        context.fillPath()
        if tileInPoints >= 4 {
            context.addPath(visited)
            context.setStrokeColor(visitedStroke)
            context.setLineWidth(lineWidth)
            context.strokePath()
        }

        // Route planning layers.
        if !o.highlight.isEmpty {
            let h = path(o.highlight)
            context.addPath(h)
            context.setFillColor(highlightFill)
            context.fillPath()
            context.addPath(h)
            context.setStrokeColor(highlightStroke)
            context.setLineWidth(2 / zoomScale)
            context.strokePath()
        }
        if !o.selected.isEmpty {
            context.addPath(path(o.selected))
            context.setFillColor(selectedFill)
            context.fillPath()
        }

        // Grid lines (unvisited tiles) when zoomed in far enough.
        if tileInPoints >= 10 {
            let grid = CGMutablePath()
            let top = rect(x0, y0).minY, bottom = rect(x0, y1).maxY
            let left = rect(x0, y0).minX, right = rect(x1, y0).maxX
            for x in x0...(x1 + 1) {
                let px = self.point(for: MKMapPoint(x: Double(x) * size, y: 0)).x
                grid.move(to: CGPoint(x: px, y: top))
                grid.addLine(to: CGPoint(x: px, y: bottom))
            }
            for y in y0...(y1 + 1) {
                let py = self.point(for: MKMapPoint(x: 0, y: Double(y) * size)).y
                grid.move(to: CGPoint(x: left, y: py))
                grid.addLine(to: CGPoint(x: right, y: py))
            }
            context.addPath(grid)
            context.setStrokeColor(gridStroke)
            context.setLineWidth(lineWidth)
            context.strokePath()
        }

        // Max square outline.
        if let origin = o.maxSquareOrigin, o.maxSquare > 1 {
            context.addRect(rect(origin.x, origin.y, o.maxSquare))
            context.setStrokeColor(maxSquareStroke)
            context.setLineWidth(3 / zoomScale)
            context.strokePath()
        }
    }
}
