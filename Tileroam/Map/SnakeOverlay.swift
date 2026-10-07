import MapKit
import UIKit

/// The snake challenge on the map, in the style of Pac-Man: a black screen, a dot on every visited
/// tile, the longest snake as a neon-blue corridor with Pac-Man at its head and a ghost at its tail.
final class SnakeOverlay: NSObject, MKOverlay, @unchecked Sendable {
    let zoom: TileZoom
    let visited: Set<Int64>
    /// The snake's tiles in order (`Snake.tiles`).
    let snake: [Int64]

    let boundingMapRect = MKMapRect.world
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    var tileSize: Double { MKMapSize.world.width / TileGrid.tilesPerSide(zoom) }

    init(zoom: TileZoom, visited: Set<Int64>, snake: [Int64]) {
        self.zoom = zoom
        self.visited = visited
        self.snake = snake
    }

    /// The centre of a tile in map points.
    func center(_ key: Int64) -> MKMapPoint {
        let c = TileGrid.cell(of: key)
        return MKMapPoint(x: (Double(c.x) + 0.5) * tileSize, y: (Double(c.y) + 0.5) * tileSize)
    }

    /// The snake's extent, to show it whole.
    var snakeRect: MKMapRect? {
        guard let first = snake.first else { return nil }
        var rect = MKMapRect(origin: center(first), size: MKMapSize(width: 0, height: 0))
        for key in snake.dropFirst() { rect = rect.union(MKMapRect(origin: center(key), size: MKMapSize(width: 0, height: 0))) }
        return rect.insetBy(dx: -tileSize, dy: -tileSize)
    }
}

final class SnakeRenderer: MKOverlayRenderer {
    // The arcade's colours.
    static let maze = UIColor(red: 0.13, green: 0.13, blue: 1.0, alpha: 1)
    static let dot = UIColor(red: 1.0, green: 0.72, blue: 0.68, alpha: 1)
    static let pacMan = UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1)
    static let blinky = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1)
    static let eyeBlue = UIColor(red: 0.13, green: 0.13, blue: 1.0, alpha: 1)

    /// The snake's corridor in map points, made once.
    private lazy var corridor: CGPath? = {
        guard let o = overlay as? SnakeOverlay, o.snake.count >= 2 else { return nil }
        let path = CGMutablePath()
        path.addLines(between: o.snake.map { point(for: o.center($0)) })
        return path
    }()

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let o = overlay as? SnakeOverlay else { return }
        let size = o.tileSize
        let onePoint = 1 / zoomScale

        // The black screen; the map shows through a little, to know where you are.
        context.setFillColor(UIColor.black.withAlphaComponent(0.92).cgColor)
        context.fill(rect(for: mapRect))

        // The corridor: a thick neon-blue line with a black one inside, like the maze's double walls.
        if let corridor {
            let width = max(size * 0.72, 5 * onePoint)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(corridor)
            context.setStrokeColor(Self.maze.cgColor)
            context.setLineWidth(width)
            context.strokePath()
            context.addPath(corridor)
            context.setStrokeColor(UIColor.black.cgColor)
            context.setLineWidth(max(width - max(size * 0.16, 2.4 * onePoint), onePoint))
            context.strokePath()
        }

        // A dot on every visited tile in view.
        let maxIndex = Int(TileGrid.tilesPerSide(o.zoom)) - 1
        let x0 = max(Int((mapRect.minX / size).rounded(.down)) - 1, 0), x1 = min(Int((mapRect.maxX / size).rounded(.down)) + 1, maxIndex)
        let y0 = max(Int((mapRect.minY / size).rounded(.down)) - 1, 0), y1 = min(Int((mapRect.maxY / size).rounded(.down)) + 1, maxIndex)
        if x0 <= x1, y0 <= y1 {
            let r = max(size * 0.09, 1.2 * onePoint)
            let dots = CGMutablePath()
            func add(_ x: Int, _ y: Int) {
                let c = point(for: MKMapPoint(x: (Double(x) + 0.5) * size, y: (Double(y) + 0.5) * size))
                dots.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }
            if (x1 - x0 + 1) * (y1 - y0 + 1) < o.visited.count {
                for y in y0...y1 { for x in x0...x1 where o.visited.contains(TileGrid.key(x: x, y: y)) { add(x, y) } }
            } else {
                for key in o.visited {
                    let c = TileGrid.cell(of: key)
                    if (x0...x1).contains(c.x), (y0...y1).contains(c.y) { add(c.x, c.y) }
                }
            }
            context.addPath(dots)
            context.setFillColor(Self.dot.cgColor)
            context.fillPath()
        }

        // Pac-Man at the head, chasing on; a ghost at the tail, following.
        guard o.snake.count >= 1 else { return }
        let figure = max(size * 0.95, 18 * onePoint)
        let head = point(for: o.center(o.snake[o.snake.count - 1]))
        var angle = 0.0
        if o.snake.count >= 2 {
            let before = point(for: o.center(o.snake[o.snake.count - 2]))
            angle = atan2(head.y - before.y, head.x - before.x)
        }
        drawPacMan(at: head, size: figure, facing: angle, in: context)
        if o.snake.count >= 2 { drawGhost(at: point(for: o.center(o.snake[0])), size: figure, in: context) }
    }

    private func drawPacMan(at c: CGPoint, size: CGFloat, facing angle: Double, in context: CGContext) {
        let r = size / 2, mouth = Double.pi / 5
        let body = CGMutablePath()
        body.move(to: c)
        body.addArc(center: c, radius: r, startAngle: angle + mouth, endAngle: angle - mouth + 2 * .pi, clockwise: false)
        body.closeSubpath()
        context.addPath(body)
        context.setFillColor(Self.pacMan.cgColor)
        context.fillPath()
    }

    private func drawGhost(at c: CGPoint, size: CGFloat, in context: CGContext) {
        let w = size, h = size, left = c.x - w / 2, top = c.y - h / 2
        let body = CGMutablePath()
        // A round head, straight sides and three wavy feet.
        body.move(to: CGPoint(x: left, y: top + h))
        body.addLine(to: CGPoint(x: left, y: top + w / 2))
        body.addArc(center: CGPoint(x: c.x, y: top + w / 2), radius: w / 2, startAngle: .pi, endAngle: 0, clockwise: false)
        body.addLine(to: CGPoint(x: left + w, y: top + h))
        let foot = w / 6
        for i in 0..<3 {
            let x = left + w - CGFloat(i) * 2 * foot
            body.addLine(to: CGPoint(x: x - foot, y: top + h - foot))
            body.addLine(to: CGPoint(x: x - 2 * foot, y: top + h))
        }
        body.closeSubpath()
        context.addPath(body)
        context.setFillColor(Self.blinky.cgColor)
        context.fillPath()
        // Eyes: white, with blue pupils looking ahead.
        for dx in [-w * 0.2, w * 0.2] {
            let eye = CGRect(x: c.x + dx - w * 0.13, y: top + h * 0.28, width: w * 0.26, height: w * 0.3)
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: eye)
            context.setFillColor(Self.eyeBlue.cgColor)
            context.fillEllipse(in: CGRect(x: eye.midX - w * 0.02, y: eye.minY + w * 0.09, width: w * 0.12, height: w * 0.14))
        }
    }
}
