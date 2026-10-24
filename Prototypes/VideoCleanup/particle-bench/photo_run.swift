// Mode "photo <file>...": single-frame speck census of still images (docs/RestorationExperiments.md, Stage D1).
// Luma is 8-bit video-range BT.709 of the sRGB pixels, like the 420v frames the metric was set on.
// It counts isolated bright groups of 1...maxDotArea px at any peak, so a speck lifted past maxPeak still counts.
// HT_SPECK_MAXDIM (default 1920) scales larger files down first; the metric was set on 1080p frames.
import CoreGraphics
import Foundation
import ImageIO

func photoSpecks(_ paths: [String]) {
    let m = MetricSettings()
    let maxDim = Int(ProcessInfo.processInfo.environment["HT_SPECK_MAXDIM"] ?? "") ?? 1920
    print("file | size | isolated 1-40 px | specks 1-12 px, peak <= 30 | soft dots 13-40 px | bright spots, peak > 30 | median peak | p90 peak")
    for p in paths {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("\(p) | unreadable"); continue }
        let scale = min(1, Double(maxDim) / Double(max(cg.width, cg.height)))
        let w = Int(Double(cg.width) * scale), h = Int(Double(cg.height) * scale)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var y = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let v = 0.2126 * Float(px[4 * i]) + 0.7152 * Float(px[4 * i + 1]) + 0.0722 * Float(px[4 * i + 2])
            y[i] = (16 + 219 * v / 255).rounded()
        }
        let f = maps(y, w, h, m)
        let iso = f.bright.filter { $0.size <= m.maxDotArea && $0.isolated }
        let peaks = iso.map(\.peak).sorted()
        let specks = iso.filter { $0.size <= m.maxSpeckArea && $0.peak <= m.maxPeak }.count
        let dots = iso.filter { $0.size > m.maxSpeckArea && $0.peak <= m.maxPeak }.count
        let bright = iso.filter { $0.peak > m.maxPeak }.count
        func q(_ f: Double) -> String { peaks.isEmpty ? "n/a" : String(format: "%.1f", peaks[min(peaks.count - 1, Int(Double(peaks.count) * f))]) }
        print("\(URL(fileURLWithPath: p).lastPathComponent) | \(w)x\(h) | \(iso.count) | \(specks) | \(dots) | \(bright) | \(q(0.5)) | \(q(0.9))")
        // HT_SPECK_DUMP=<dir>: one CSV per file (centre as a fraction of the size, size, peak), to check them by eye.
        if let dir = ProcessInfo.processInfo.environment["HT_SPECK_DUMP"] {
            let rows = iso.map { String(format: "%.5f,%.5f,%d,%.1f", $0.cx / Float(w), $0.cy / Float(h), $0.size, $0.peak) }
            try? (["fx,fy,size,peak"] + rows).joined(separator: "\n")
                .write(toFile: "\(dir)/\(URL(fileURLWithPath: p).lastPathComponent).csv", atomically: true, encoding: .utf8)
        }
    }
}

/// 8-bit video-range BT.709 luma of an image file, scaled down to maxDim when larger.
func photoLuma(_ p: String, maxDim: Int) -> ([Float], Int, Int)? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let scale = min(1, Double(maxDim) / Double(max(cg.width, cg.height)))
    let w = Int(Double(cg.width) * scale), h = Int(Double(cg.height) * scale)
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var y = [Float](repeating: 0, count: w * h)
    for i in 0..<(w * h) {
        let v = 0.2126 * Float(px[4 * i]) + 0.7152 * Float(px[4 * i + 1]) + 0.0722 * Float(px[4 * i + 2])
        y[i] = (16 + 219 * v / 255).rounded()
    }
    return (y, w, h)
}

// Mode "pair <original> <variant>...": the isolated groups of the ORIGINAL (1...40 px, any peak), and their
// peak at the same place in each variant (max 3x3-minus-17x17 residual in the group's box plus 1 px).
// Ratio > 1 means the correction made those spots stand out more. The files must have the same size.
func photoPairs(_ paths: [String]) {
    let m = MetricSettings()
    guard let (yo, w, h) = photoLuma(paths[0], maxDim: .max) else { print("unreadable \(paths[0])"); return }
    let fo = maps(yo, w, h, m)
    let iso = fo.bright.filter { $0.size <= m.maxDotArea && $0.isolated }
    print("\(URL(fileURLWithPath: paths[0]).lastPathComponent): \(iso.count) isolated groups, median peak \(median(iso.map(\.peak)))")
    for p in paths.dropFirst() {
        guard let (yv, wv, hv) = photoLuma(p, maxDim: .max), wv == w, hv == h else { print("\(p) | unreadable or other size"); continue }
        let fv = maps(yv, w, h, m)
        var ratios: [Float] = [], peaks: [Float] = []
        for b in iso {
            var best = -Float.greatestFiniteMagnitude
            for yy in max(0, b.y0 - 1)...min(h - 1, b.y1 + 1) { for xx in max(0, b.x0 - 1)...min(w - 1, b.x1 + 1) { best = max(best, fv.residual[yy * w + xx]) } }
            peaks.append(best); ratios.append(best / b.peak)
        }
        let isoV = fv.bright.filter { $0.size <= m.maxDotArea && $0.isolated }.count
        print("  \(URL(fileURLWithPath: p).lastPathComponent): same groups median peak \(median(peaks)), peak ratio median \(median(ratios)) p10 \(quantile(ratios, 0.1)) p90 \(quantile(ratios, 0.9)); isolated groups found anew: \(isoV)")
    }
}
func quantile(_ v: [Float], _ q: Double) -> String { let s = v.sorted(); return s.isEmpty ? "n/a" : String(format: "%.2f", s[min(s.count - 1, Int(Double(s.count) * q))]) }
func median(_ v: [Float]) -> String { quantile(v, 0.5) }
