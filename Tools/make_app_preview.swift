// Trims, scales and crops a simulator recording into an App Store app preview:
// H.264 at a constant 30 fps, no audio, exactly <width>×<height> (scaled to fill, cropped in the
// middle).
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

// Written frame by frame at exactly 30 fps: an export session leaves out the frames where the
// simulator's recording has gaps, and App Store Connect wants a constant 30 fps. A gap repeats the
// frame before it.
try? FileManager.default.removeItem(at: output)
let reader = try AVAssetReader(asset: composition)
let frames = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack],
                                                 videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
frames.videoComposition = video
reader.add(frames)
let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: Int(width),
    AVVideoHeightKey: Int(height),
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000, AVVideoExpectedSourceFrameRateKey: 30,
                                      AVVideoMaxKeyFrameIntervalKey: 30, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
])
writerInput.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: nil)
writer.add(writerInput)
guard reader.startReading(), writer.startWriting() else { print("can't convert: \(String(describing: reader.error ?? writer.error))"); exit(1) }
writer.startSession(atSourceTime: .zero)

let count = Int((range.duration.seconds * 30).rounded(.down))
var current: CVPixelBuffer?
var next = frames.copyNextSampleBuffer()
for n in 0..<count {
    let time = CMTime(value: CMTimeValue(n), timescale: 30)
    // The latest frame shown at or before this moment (half a frame of slack for rounding).
    while let sample = next, CMSampleBufferGetPresentationTimeStamp(sample).seconds <= time.seconds + 1.0 / 60 {
        current = CMSampleBufferGetImageBuffer(sample)
        next = frames.copyNextSampleBuffer()
    }
    guard let buffer = current else { continue }
    while !writerInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
    adaptor.append(buffer, withPresentationTime: time)
}
writerInput.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else { print("can't write: \(String(describing: writer.error))"); exit(1) }
print("Wrote \(output.path) (\(Int(width))×\(Int(height)), \(String(format: "%.1f", Double(count) / 30)) s)")
