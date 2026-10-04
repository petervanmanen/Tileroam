// Renders the badge icons (SVG, with text) to PNG with WebKit, which draws SVG text the way a
// browser does. The app shows the PNGs (Tileroam/Resources/Badges/badge-<id>.png); see
// Tileroam/Model/Badges.swift.
//
//   swift Tools/render_badges.swift <folder with <id>.svg> [size in pixels, default 192]
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: swift Tools/render_badges.swift <svg folder> [size]\n".utf8))
    exit(1)
}
let source = URL(fileURLWithPath: args[1], isDirectory: true)
let size = args.count > 2 ? Double(args[2]) ?? 192 : 192
let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Tileroam/Resources/Badges", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

@MainActor
final class Renderer: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: size, height: size))
    var queue: [URL]
    var current: URL?

    init(files: [URL]) {
        queue = files
        super.init()
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground") // transparent around the round badge
    }

    func next() {
        guard !queue.isEmpty else { exit(0) }
        let file = queue.removeFirst()
        current = file
        let svg = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let html = """
        <html><body style="margin:0;background:transparent">
        <div style="width:\(Int(size))px;height:\(Int(size))px">\(svg.replacingOccurrences(of: #"width="256" height="256""#, with: #"width="100%" height="100%""#))</div>
        </body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = NSNumber(value: size / (NSScreen.main?.backingScaleFactor ?? 2))
            view.takeSnapshot(with: config) { image, error in
                MainActor.assumeIsolated {
                    guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]), let file = self.current else {
                        FileHandle.standardError.write(Data("failed: \(self.current?.lastPathComponent ?? "?") \(String(describing: error))\n".utf8))
                        exit(1)
                    }
                    let name = "badge-" + file.deletingPathExtension().lastPathComponent + ".png"
                    try? png.write(to: out.appending(path: name))
                    print("\(name)  \(rep.pixelsWide)×\(rep.pixelsHigh)")
                    self.next()
                }
            }
        }
    }
}

let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "svg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
let app = NSApplication.shared
let renderer = MainActor.assumeIsolated { Renderer(files: files) }
MainActor.assumeIsolated { renderer.next() }
app.run()
