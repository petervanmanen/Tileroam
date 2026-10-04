// Puts images side by side at one height with a small gap, on white: the README's overview image.
//
//   swift Tools/compose_images.swift <out.jpg> <height> <image>…
import AppKit

let args = CommandLine.arguments
guard args.count >= 4, let height = Double(args[2]) else {
    FileHandle.standardError.write(Data("usage: swift Tools/compose_images.swift <out.jpg> <height> <image>…\n".utf8))
    exit(1)
}
let images = args[3...].compactMap { NSImage(contentsOfFile: $0) }
let gap = 20.0
let widths = images.map { height * $0.size.width / $0.size.height }
let width = widths.reduce(0, +) + gap * Double(images.count + 1)
let total = height + 2 * gap
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(total), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: width, height: total).fill()
var x = gap
for (image, w) in zip(images, widths) {
    image.draw(in: NSRect(x: x, y: gap, width: w, height: height))
    x += w + gap
}
NSGraphicsContext.restoreGraphicsState()
let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!
try jpeg.write(to: URL(fileURLWithPath: args[1]))
print("\(args[1]): \(Int(width))×\(Int(total))")
