// Prints an app preview video's size, frame rate, codec, length and audio tracks, and writes a
// contact sheet of 8 frames for a visual check:
//   swift Tools/check_app_preview.swift <video.mov> <sheet.png>
import AVFoundation
import AppKit
let url = URL(filePath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)
let track = try await asset.loadTracks(withMediaType: .video).first!
let (size, fps, formats) = try await track.load(.naturalSize, .nominalFrameRate, .formatDescriptions)
let codec = formats.first.map { CMFormatDescriptionGetMediaSubType($0) }.map { String(format: "%c%c%c%c", ($0 >> 24) & 255, ($0 >> 16) & 255, ($0 >> 8) & 255, $0 & 255) } ?? "?"
let audio = try await asset.loadTracks(withMediaType: .audio).count
print("size \(size) fps \(fps) codec \(codec) duration \(try await asset.load(.duration).seconds) audio tracks \(audio)")
// Contact sheet of frames
let dur = try await asset.load(.duration).seconds; let times: [Double] = (0..<8).map { 0.5 + Double($0) * (dur - 1) / 7 }
let gen = AVAssetImageGenerator(asset: asset); gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
let th = 480, tw = Int(480 * size.width / size.height)
let ctx = CGContext(data: nil, width: tw * 4, height: th * 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
for (i, t) in times.enumerated() {
    let (img, _) = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600))
    ctx.draw(img, in: CGRect(x: (i % 4) * tw, y: (1 - i / 4) * th, width: tw, height: th))
}
try NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(filePath: CommandLine.arguments[2]))
