// Trims, scales and crops a simulator recording into an App Store app preview:
// H.264, 30 fps, no audio, exactly <width>×<height> (scaled to fill, cropped in the middle).
//
//   swift Tools/make_app_preview.swift <in.mov> <out.mov> <start s> <end s> <width> <height>
import AVFoundation

let a = CommandLine.arguments
guard a.count == 7, let start = Double(a[3]), let end = Double(a[4]), let width = Double(a[5]), let height = Double(a[6]) else {
    print("usage: make_app_preview.swift <in> <out> <start> <end> <width> <height>"); exit(1)
}
let input = URL(filePath: a[1]), output = URL(filePath: a[2])

let asset = AVURLAsset(url: input)
guard let track = try await asset.loadTracks(withMediaType: .video).first else { print("no video track"); exit(1) }
let natural = try await track.load(.naturalSize)
let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                        end: CMTime(seconds: end, preferredTimescale: 600))

let composition = AVMutableComposition()
let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
try videoTrack.insertTimeRange(range, of: track, at: .zero)

// Fill the target size, cropping the overflow equally on both sides.
let scale = max(width / natural.width, height / natural.height)
let tx = (width - natural.width * scale) / 2, ty = (height - natural.height * scale) / 2
let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
layer.setTransform(CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: tx, y: ty)), at: .zero)
let instruction = AVMutableVideoCompositionInstruction()
instruction.timeRange = CMTimeRange(start: .zero, duration: range.duration)
instruction.layerInstructions = [layer]
let video = AVMutableVideoComposition()
video.renderSize = CGSize(width: width, height: height)
video.frameDuration = CMTime(value: 1, timescale: 30)
video.instructions = [instruction]

try? FileManager.default.removeItem(at: output)
guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { exit(1) }
export.videoComposition = video
try await export.export(to: output, as: .mov)
print("Wrote \(output.path) (\(Int(width))×\(Int(height)), \(String(format: "%.1f", range.duration.seconds)) s)")
