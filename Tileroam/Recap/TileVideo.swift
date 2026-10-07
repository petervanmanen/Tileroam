import AVFoundation
import CoreVideo
import MapKit
import UIKit

/// Renders the tile history as a video (issue #59): the map of the country with the largest
/// cluster, the tiles appearing in the order they were first visited (new ones orange, then
/// green), with the date and the count, ending on the max square. 1080 × 1920, 30 fps, H.264.
enum TileVideo {
    static let size = CGSize(width: 1080, height: 1920)
    static let fps: Int32 = 30
    /// Seconds of tiles appearing, then the end held.
    static let growSeconds = 20.0
    static let holdSeconds = 3.0
    /// Frames a new tile stays orange.
    static let highlightFrames = 12

    enum RenderError: LocalizedError {
        case noTiles, writer(String)
        var errorDescription: String? {
            switch self {
            case .noTiles: String(localized: "There are no tiles yet to make a video of.")
            case .writer(let message): String(localized: "The video couldn't be made: \(message)")
            }
        }
    }

    /// Makes the video in a temporary file and returns its URL. `progress` gets 0…1.
    static func render(_ history: TileHistory, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let focus = history.focusRegion(aspect: size.width / size.height) else { throw RenderError.noTiles }
        let map = try await TileMapImage.make(region: focus.region, size: size)
        let url = FileManager.default.temporaryDirectory.appending(path: "Tileroam-tiles-\(Int(Date.now.timeIntervalSince1970)).mp4")
        try await Task.detached(priority: .userInitiated) {
            try write(history, map: map, country: focus.country, to: url, progress: progress)
        }.value
        return url
    }

    private static func write(_ history: TileHistory, map: TileMapImage, country: String?, to url: URL,
                              progress: @Sendable (Double) -> Void) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        guard writer.startWriting() else { throw RenderError.writer(writer.error?.localizedDescription ?? "") }
        writer.startSession(atSourceTime: .zero)

        let entries = history.entries
        let growFrames = Int(growSeconds * Double(fps)), holdFrames = Int(holdSeconds * Double(fps))
        let total = growFrames + holdFrames
        // The tiles drawn so far, kept in their own layer so each frame only adds the new ones.
        let space = CGColorSpaceCreateDeviceRGB()
        guard let layer = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                    bytesPerRow: 0, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw RenderError.writer("context") }
        flipped(layer)
        let base = map.base.cgImage
        var drawn = 0
        var recent = [(rect: CGRect, frame: Int)]()
        let finalStats = SquareStats(visited: history.keys)

        for frame in 0..<total {
            // Tiles appear evenly over the growing part (by count, not by date: no long pauses).
            let upTo = frame >= growFrames ? entries.count : Int(Double(entries.count) * Double(frame + 1) / Double(growFrames))
            while drawn < upTo {
                map.draw(entries[drawn].key, in: layer, fill: TileMapImage.tileFill, edge: TileMapImage.tileEdge)
                recent.append((map.rect(entries[drawn].key), frame))
                drawn += 1
            }
            recent.removeAll { frame - $0.frame > highlightFrames }

            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            guard let pool = adaptor.pixelBufferPool else { throw RenderError.writer("pixel buffer pool") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw RenderError.writer("pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                       bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                if let base { context.draw(base, in: CGRect(origin: .zero, size: size)) }
                if let tiles = layer.makeImage() { context.draw(tiles, in: CGRect(origin: .zero, size: size)) }
                flipped(context)
                for (rect, born) in recent {
                    let fade = 1 - Double(frame - born) / Double(highlightFrames)
                    context.setFillColor(TileMapImage.newFill.withAlphaComponent(0.95 * fade).cgColor)
                    context.fill(rect.insetBy(dx: 0.5, dy: 0.5))
                }
                if frame >= growFrames, let origin = finalStats.maxSquareOrigin, finalStats.maxSquare > 0 {
                    let a = map.rect(TileGrid.key(x: origin.x, y: origin.y))
                    let b = map.rect(TileGrid.key(x: origin.x + finalStats.maxSquare - 1, y: origin.y + finalStats.maxSquare - 1))
                    context.setStrokeColor(TileMapImage.squareStroke.cgColor)
                    context.setLineWidth(8)
                    context.stroke(a.union(b))
                }
                let date = drawn > 0 ? entries[drawn - 1].date : (entries.first?.date ?? .now)
                caption(context, date: date, tiles: drawn, maxSquare: frame >= growFrames ? finalStats.maxSquare : nil, country: country)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
            if frame % 15 == 0 { progress(Double(frame) / Double(total)) }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw RenderError.writer(writer.error?.localizedDescription ?? "") }
        progress(1)
    }

    /// Origin top left, like UIKit.
    private static func flipped(_ context: CGContext) {
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
    }

    /// The date, the tile count and the app's name, on a light band at the top.
    private static func caption(_ context: CGContext, date: Date, tiles: Int, maxSquare: Int?, country: String?) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        let band = CGRect(x: 0, y: 0, width: size.width, height: 300)
        UIColor.white.withAlphaComponent(0.85).setFill()
        UIRectFill(band)
        let month = date.formatted(.dateTime.month(.wide).year())
        let title = [String(localized: "Tileroam"), country.flatMap { Country.named($0)?.name ?? Locale.current.localizedString(forRegionCode: $0) }]
            .compactMap { $0 }.joined(separator: " · ")
        draw(title, at: 70, size: 40, weight: .semibold, color: .secondaryLabel)
        draw(month, at: 120, size: 64, weight: .bold, color: .black)
        var line = String(localized: "\(tiles) tiles")
        if let maxSquare { line += " · " + String(localized: "max square \(maxSquare)×\(maxSquare)") }
        draw(line, at: 205, size: 52, weight: .semibold, color: TileMapImage.tileEdge)
    }

    private static func draw(_ text: String, at y: CGFloat, size points: CGFloat, weight: UIFont.Weight, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: points, weight: weight),
                                                         .foregroundColor: color]
        let s = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: (size.width - s.width) / 2, y: y), withAttributes: attributes)
    }
}
