// Copies a movie and sets a 90° clockwise track matrix, as on an iPhone or GoPro portrait clip.
// ffmpeg `-metadata rotate=90` wrote no matrix, so portrait_audio.mov had an identity transform (13 Nov 2026).
// Usage: swift scripts/rotate_fixture.swift <in.mov> <out.mov>
import AVFoundation

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: rotate_fixture.swift <in> <out>"); exit(2) }
let source = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let output = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: output)

func run() async throws {
    let composition = AVMutableComposition()
    let duration = try await source.load(.duration)
    let range = CMTimeRange(start: .zero, duration: duration)
    for track in try await source.loadTracks(withMediaType: .video) + source.loadTracks(withMediaType: .audio) {
        guard let copy = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CocoaError(.fileWriteUnknown) }
        try copy.insertTimeRange(range, of: track, at: .zero)
        if track.mediaType == .video {
            let height = try await track.load(.naturalSize).height
            copy.preferredTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
        }
    }
    guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
    else { throw CocoaError(.fileWriteUnknown) }
    try await session.export(to: output, as: .mov)
}

let done = DispatchSemaphore(value: 0)
var failure: (any Error)?
Task { do { try await run() } catch { failure = error }; done.signal() }
done.wait()
if let failure { print(failure); exit(1) }
