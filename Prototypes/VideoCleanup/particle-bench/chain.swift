// Stage D2 (docs/RestorationExperiments.md): the particle filter in the full chain, scored after colour.
// Build: build_chain.sh (it compiles the app's colour sources too). Usage: chain <tag> <clip> <start> <seconds>
// Colour is the app's video path: VideoRestorationAnalyzer on the whole clip, then RestorationEngine.combined(moment:)
// with Natural Dive at 0.8, as the exporter renders a frame. Variants, each scored after ONE render into 420v:
//   a colour            the reference for b and c
//   b particle>colour   the planned order
//   c colour>particle   the other order
//   d original          the reference for e (the prototype's own numbers)
//   e particle
// Motion comes from the original frames for every variant: colour does not move pixels.
import AVFoundation
import CoreImage
import Foundation

let chainNames = ["a colour", "b particle>colour", "c colour>particle", "d original", "e particle"]
let chainRef = [0, 0, 0, 3, 3]

struct ChainSums {
    var drift = 0, refDrift = 0, removed = 0, frames = 0, bright = 0
    var subj = 0.0, subjRef = 0.0, darkSmall = 0.0, darkSmallRef = 0.0
    var changed = 0.0
}

func runChain(_ tag: String, _ clip: String, _ start: Double, _ seconds: Double) async throws {
    let path = fixtures + clipFiles[clip]!
    let url = URL(fileURLWithPath: path)
    let metadata = try await MediaInspector().inspect(url)
    let analysis = try await VideoRestorationAnalyzer().analyze(url: url, metadata: metadata)
    print("analysis: scenes \(analysis.scenes.count)")
    let engine = FilterEngine(), restoration = RestorationEngine()
    let settings = FilterSettings(preset: .natural, intensity: 0.8, analysis: analysis.legacyAnalysis)
    func colour(_ image: CIImage, _ time: CMTime) -> CIImage {
        guard let moment = analysis.moment(at: time.seconds),
              let out = try? restoration.combined(image, moment: moment, settings: settings, filter: engine) else { return image }
        return out.cropped(to: image.extent)
    }

    let reader = try await Reader(path, format: TemporalDenoiser.sourcePixelFormat(hdr: false), start: start, seconds: seconds)
    let ctx = engine.context
    let r = Renderer(ctx)
    let m = MetricSettings()
    let V = chainNames.count
    var luma: Luma?
    var w = 0, h = 0
    let pfB = ParticleFilter(context: ctx)!, pfC = ParticleFilter(context: ctx)!, pfE = ParticleFilter(context: ctx)!
    var sources: [CMTime: (Int, CVPixelBuffer)] = [:]
    var lumas = [[Int: [Float]]](repeating: [:], count: V)
    var fmaps = [[Int: FrameMaps]](repeating: [:], count: V)
    var sums = [ChainSums](repeating: ChainSums(), count: V)
    var outCount = [Int](repeating: 0, count: V)
    var total = 0, processed = 1
    var cropIndex = -1
    var crops = [RGBA?](repeating: nil, count: V)

    func accept(_ v: Int, _ image: CIImage, _ time: CMTime) throws {
        guard let (i, src) = sources[time] else { fatalError("unknown time") }
        let scored = r.render(image, like: src)
        lumas[v][i] = try luma!.read(scored)
        outCount[v] += 1
        if i == cropIndex { crops[v] = renderRGBA(CIImage(cvPixelBuffer: scored), ctx) }
    }
    func mapsFor(_ v: Int, _ i: Int) -> FrameMaps {
        if let f = fmaps[v][i] { return f }
        let f = maps(lumas[v][i]!, w, h, m); fmaps[v][i] = f; return f
    }
    func process(_ k: Int) {
        let yo = lumas[3][k]!
        let mp = motion(yo, lumas[3][k - 1]!, w, h), mn = motion(yo, lumas[3][k + 2]!, w, h)
        var refCounts: [Int: SpeckCount] = [:]
        for ref in Set(chainRef) {
            refCounts[ref] = specks(mapsFor(ref, k), prev: (mapsFor(ref, k - 1), mp), next2: (mapsFor(ref, k + 2), mn), m)
        }
        for v in 0..<V {
            let ref = chainRef[v], fr = mapsFor(ref, k), f = mapsFor(v, k)
            let c = v == ref ? refCounts[ref]! : specks(f, prev: (mapsFor(v, k - 1), mp), next2: (mapsFor(v, k + 2), mn), m)
            let rc = refCounts[ref]!
            sums[v].frames += 1; sums[v].drift += c.drifting; sums[v].refDrift += rc.drifting; sums[v].bright += c.brightSpots
            for b in rc.driftingBlobs {
                let x = Int(b.cx.rounded()), y = Int(b.cy.rounded())
                var best: Float = -99
                for dy in -1...1 { for dx in -1...1 { let xx = x + dx, yy = y + dy
                    if xx >= 0, yy >= 0, xx < w, yy < h { best = max(best, f.residual[yy * w + xx]) } } }
                if best < 0.5 * b.peak { sums[v].removed += 1 }
            }
            for i in subjectMask(fr, m) { sums[v].subj += Double(abs(f.residual[i])); sums[v].subjRef += Double(abs(fr.residual[i])) }
            for i in darkSmallMask(fr, m) { sums[v].darkSmall += Double(abs(f.residual[i])); sums[v].darkSmallRef += Double(abs(fr.residual[i])) }
            let yv = lumas[v][k]!, yr = lumas[ref][k]!
            var ch = 0
            for i in 0..<(w * h) where abs(yv[i] - yr[i]) > 2 { ch += 1 }
            sums[v].changed += Double(ch) / Double(w * h)
        }
        for v in 0..<V { fmaps[v][k - 1] = nil; lumas[v][k - 1] = nil }
    }
    func drain() {
        while lumas.allSatisfy({ $0[processed + 2] != nil && $0[processed - 1] != nil && $0[processed] != nil }) {
            process(processed); processed += 1
        }
    }

    while let (buffer, time) = reader.next() {
        try autoreleasepool {
            if luma == nil {
                w = CVPixelBufferGetWidth(buffer); h = CVPixelBufferGetHeight(buffer)
                luma = Luma(width: w, height: h)
                cropIndex = Int(seconds * 59.94 / 2)
            }
            sources[time] = (total, buffer)
            total += 1
            let src = CIImage(cvPixelBuffer: buffer)
            let coloured = colour(src, time)
            try accept(0, coloured, time)
            try accept(3, src, time)
            if let o = pfB.push(src, at: time) { try accept(1, colour(o.image, o.time), o.time) }
            if let o = pfC.push(coloured, at: time) { try accept(2, o.image, o.time) }
            if let o = pfE.push(src, at: time) { try accept(4, o.image, o.time) }
        }
        drain()
        for (t, v) in sources where v.0 < total - 8 && v.0 != cropIndex { sources[t] = nil }
    }
    for o in pfB.finish() { try accept(1, colour(o.image, o.time), o.time) }
    for o in pfC.finish() { try accept(2, o.image, o.time) }
    for o in pfE.finish() { try accept(4, o.image, o.time) }
    drain()

    print("== \(tag) \(clip) \(start)-\(start + seconds) s: frames \(total), out \(outCount), scored \(sums[0].frames)")
    for (v, s) in sums.enumerated() {
        let n = Double(max(1, s.frames))
        print(String(format: "   %-18@ vs %@: drift/frame %6.2f (ref %6.2f) removed %5.1f%% bright/frame %5.2f subj %6.1f%% darkSmall %6.1f%% changed>2 %6.3f%%",
                     chainNames[v] as NSString, String(chainNames[chainRef[v]].prefix(1)) as NSString,
                     Double(s.drift) / n, Double(s.refDrift) / n,
                     v == chainRef[v] ? 0 : 100 * Double(s.removed) / Double(max(1, s.refDrift)),
                     Double(s.bright) / n, 100 * s.subj / max(1e-9, s.subjRef), 100 * s.darkSmall / max(1e-9, s.darkSmallRef),
                     100 * s.changed / n))
    }
    if crops.allSatisfy({ $0 != nil }) {
        let all = crops.map { $0! }
        savePNG(grid([[all[3], all[4]], [all[0], all[1], all[2]]]), "\(root)/chain/\(tag)_frame.png")
        print("   frame: \(root)/chain/\(tag)_frame.png (row 1: d e, row 2: a b c)")
    }
}
