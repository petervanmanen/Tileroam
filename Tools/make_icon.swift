// Generates the app icon: swift Tools/make_icon.swift <out.png> [light|dark|tinted]
import AppKit
import CoreGraphics

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
// Mode: "light" (default), "dark" (transparent background, iOS adds a dark backdrop),
// "tinted" (grayscale on transparent; iOS applies the user's tint by luminance).
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "light"
let opaque = mode == "light"
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1) // top-left origin
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    guard mode == "tinted" else { return CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a) }
    let l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    return CGColor(srgbRed: l, green: l, blue: l, alpha: a)
}
// Colors per mode
let tileColor = mode == "tinted" ? CGColor(gray: 0.62, alpha: 1) : mode == "dark" ? c(52, 199, 112, 0.9) : c(62, 214, 128, 0.85)
let gridColor = mode == "tinted" ? CGColor(gray: 1, alpha: 0.14) : c(255, 255, 255, mode == "dark" ? 0.12 : 0.16)
let routeColor = mode == "tinted" ? CGColor(gray: 1, alpha: 1) : mode == "dark" ? c(255, 140, 60) : c(255, 122, 40)
let casingColor = mode == "light" ? c(255, 255, 255) : CGColor(gray: 0, alpha: 0)

// Background: deep blue-green gradient
if opaque {
    let bg = CGGradient(colorsSpace: cs, colors: [c(14, 52, 74), c(9, 94, 95)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])
}

// Grid of squares, slightly rotated like a map
ctx.saveGState()
ctx.translateBy(x: 512, y: 512); ctx.rotate(by: -0.12); ctx.translateBy(x: -512, y: -512)
let cell: CGFloat = 128, origin: CGFloat = -128
let visited: Set<[Int]> = [[2,3],[3,3],[4,3],[2,4],[3,4],[4,4],[5,4],[3,5],[4,5],[5,5],[4,6],[5,6],[6,6],[1,4],[5,3],[6,5],[3,2]]
for x in 0..<11 { for y in 0..<11 where visited.contains([x, y]) {
    let r = CGRect(x: origin + CGFloat(x) * cell, y: origin + CGFloat(y) * cell, width: cell, height: cell).insetBy(dx: 5, dy: 5)
    ctx.setFillColor(tileColor)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil)); ctx.fillPath()
}}
ctx.setStrokeColor(gridColor); ctx.setLineWidth(4)
for i in 0...11 {
    let p = origin + CGFloat(i) * cell
    ctx.move(to: CGPoint(x: p, y: origin)); ctx.addLine(to: CGPoint(x: p, y: origin + 11 * cell))
    ctx.move(to: CGPoint(x: origin, y: p)); ctx.addLine(to: CGPoint(x: origin + 11 * cell, y: p))
}
ctx.strokePath()
ctx.restoreGState()

// Route line winding through the visited area
let route = CGMutablePath()
route.move(to: CGPoint(x: 90, y: 860))
route.addCurve(to: CGPoint(x: 400, y: 640), control1: CGPoint(x: 220, y: 900), control2: CGPoint(x: 250, y: 660))
route.addCurve(to: CGPoint(x: 560, y: 330), control1: CGPoint(x: 560, y: 620), control2: CGPoint(x: 380, y: 400))
route.addCurve(to: CGPoint(x: 900, y: 170), control1: CGPoint(x: 700, y: 270), control2: CGPoint(x: 760, y: 120))
// Light: white casing around an orange line. Dark/tinted: a clear gap around the line instead.
if !opaque {
    ctx.saveGState(); ctx.setBlendMode(.clear)
    ctx.addPath(route); ctx.setLineWidth(70); ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
    for p in [CGPoint(x: 90, y: 860), CGPoint(x: 900, y: 170)] { ctx.fillEllipse(in: CGRect(x: p.x - 52, y: p.y - 52, width: 104, height: 104)) }
    ctx.restoreGState()
}
for (width, color) in [(CGFloat(62), casingColor), (CGFloat(38), routeColor)] {
    ctx.addPath(route); ctx.setStrokeColor(color); ctx.setLineWidth(width)
    ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
}
// Start and end dots
for p in [CGPoint(x: 90, y: 860), CGPoint(x: 900, y: 170)] {
    ctx.setFillColor(opaque ? c(255, 255, 255) : routeColor); ctx.fillEllipse(in: CGRect(x: p.x - 44, y: p.y - 44, width: 88, height: 88))
    ctx.setFillColor(opaque ? routeColor : (mode == "tinted" ? CGColor(gray: 0.62, alpha: 1) : c(9, 94, 95)))
    ctx.fillEllipse(in: CGRect(x: p.x - 26, y: p.y - 26, width: 52, height: 52))
}

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
