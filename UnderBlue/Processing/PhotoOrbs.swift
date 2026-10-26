import Accelerate
import CoreImage
import Foundation
import Metal

/// Soft round backscatter ("orbs") in photos: out-of-focus particles that add a faint disc of light to the water.
/// Our correction lifts them (D3 in docs/RestorationExperiments.md: 1.52x on a wreck photo), so they are taken off
/// the source before colour. The prototype is `scripts/photo-orbs/orbs2.py`; this is its port.
///
/// Detection runs once per photo on the source scaled to `detectionSize`, on sRGB-encoded luma (0-255), the 8-bit
/// renders the rules were set on. Its blurs run in 32-bit float: half float steps by 0.125 levels above 128, which
/// cut the finds by up to two thirds against the 0.8-level floor. A spot is an orb when every test passes:
/// - a local maximum of a band (Gaussian s minus Gaussian 3.3 s, s in `sizes`), above max(`floor`, `k` x the band's
///   mean |value| over 64 px) and below `maxPeak` levels;
/// - in water (colour water share `share` or more), off the subject mask, and, where the depth map can be trusted,
///   where depth reads far (`far` or more). Trust here is the correlation of depth with the water share (alpha), as in
///   the prototype. The colour step's RestorationEngine.depthTrust reads the share kernel's luma instead (see there);
///   on p1 that trusts depth (0.86) where the share does not (r 0.04), and the depth gate then drops 20 of 37 orbs;
/// - not in a bubble cluster: at most `cluster` other bright maxima within 8 s;
/// - soft: the fine band (Gaussian 1 minus 3 px) at the centre is at most `soft` x the peak (a bubble has a sharp core);
/// - isolated: the band's spread on a ring at 3.3 s is below `ring` x the peak;
/// - round: its half-max region fills `round` of its box, and is at most 40 s^2 px;
/// - on a smooth background: the spread of the luma on a ring at 1.4-2.4 r is at most `flat` x the local noise + 0.5;
/// - faint: its bump is at most `defaultMaxBump` levels (small fish are brighter).
/// Removal takes off only the smooth bump: the Gaussian-s colour minus the mean of a ring at 1.3 r, above zero, over a
/// soft disc. Backscatter adds light on top of the background, so the texture under it stays. It is stored as factors
/// on the linear colour (1 = unchanged) in small patches, and applied to any size by scaling the factor image.
struct PhotoOrbs: Sendable {
    struct Patch: Sendable {
        let x: Int, y: Int, width: Int, height: Int
        /// Linear-colour factors, RGB per pixel, row 0 on top (detection coordinates).
        let factors: [Float]
    }
    /// One found orb: centre, radius and bump (luma levels above the ring around it), detection coordinates.
    struct Spot: Sendable { let x: Int, y: Int, radius: Float, bump: Float }
    /// The detection image's size; patches are in its pixel coordinates (y down).
    let width: Int
    let height: Int
    let patches: [Patch]
    let spots: [Spot]
    var count: Int { patches.count }

    static let detectionSize: CGFloat = 1920
    static let sizes: [Float] = [3, 4.5, 6.5]
    static let floor: Float = 0.8, k: Float = 2.5, maxPeak: Float = 30
    static let share: Float = 0.5, subject: Float = 0.3, ring: Float = 0.6, round: Float = 0.5, cluster = 2
    static let flat: Float = 2, soft: Float = 0.6, far: Float = 0.75
    /// The brightest bump an orb may have, in luma levels (bump: the Gaussian-s luma at the centre over the ring at
    /// 1.3 r). Small fish in open water pass every other test; they are brighter. On 4 AquaColorFix photos (26 Oct
    /// 2026, labelled by eye) fish read 8.6 / 17 / 26 (p10 / median / p90), orbs 1.2 / 2.5 / 5.6. At 8, 4 of 44 fish
    /// are still touched (dim green fish on O4, 18-51% fainter) and 41 of 44 orbs come off; the brightest real orbs
    /// stay (9 of about 50 on the Pexels test photo p2). Jake chose 8 with the removal behind a Labs switch.
    static let defaultMaxBump: Float = 8
    /// The Labs switch (Help): saved on the device, off by default.
    static let enabledKey = "photoOrbs.enabled"
    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: enabledKey) }

    /// `share` is the colour water share (FilterEngine.waterShare) of `source`; `subjects` and `depth` the plan's.
    /// `maxBump`: the brightest bump an orb may have, in luma levels (nil: no limit). Nil when nothing is found.
    static func detect(_ source: CIImage, share: CIImage?, subjects: SubjectMask?, depth: NormalizedDepthMap?,
                       context: CIContext, maxBump: Float? = defaultMaxBump) -> PhotoOrbs? {
        let small = FilterEngine.downscaled(source, maxPixel: detectionSize)
        let w = Int(small.extent.width), h = Int(small.extent.height)
        guard w >= 64, h >= 64 else { return nil }
        let origin = CGAffineTransform(translationX: -small.extent.minX, y: -small.extent.minY)
        var rgba = [Float](repeating: 0, count: w * h * 4)
        context.render(small.transformed(by: origin), toBitmap: &rgba, rowBytes: w * 16,
                       bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: FilterEngine.workingSpace)
        // g: gamma 2.2 encoding of the working space, 0-255, per channel (the removal reads it). Y: the luma of the
        // sRGB encoding, 0-255 (the rules read it).
        var g = [Float](repeating: 0, count: w * h * 3), Y = [Float](repeating: 0, count: w * h)
        func srgb(_ v: Float) -> Float {
            let c = max(0, min(1, v))
            return 255 * (c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055)
        }
        for i in 0..<(w * h) {
            let r = rgba[i * 4], gr = rgba[i * 4 + 1], b = rgba[i * 4 + 2]
            for c in 0..<3 { g[i * 3 + c] = 255 * pow(max(0, min(1, rgba[i * 4 + c])), 1 / 2.2) }
            // Linear BT.2020 to linear sRGB.
            let sr = 1.6605 * r - 0.5876 * gr - 0.0728 * b
            let sg = -0.1246 * r + 1.1329 * gr - 0.0083 * b
            let sb = -0.0182 * r - 0.1006 * gr + 1.1187 * b
            Y[i] = 0.2126 * srgb(sr) + 0.7152 * srgb(sg) + 0.0722 * srgb(sb)
        }
        rgba = []
        let blur = Blur(Y, width: w, height: h)
        // The share is the alpha channel of FilterEngine.waterShare (luma, luma, luma, share).
        let shareMap = share.map { SubjectTiers.channel($0, 3, width: w, height: h, context: context) }
        func at(_ map: [Float]?, _ mw: Int, _ mh: Int, _ x: Int, _ y: Int) -> Float? {
            guard let map, mw > 0, mh > 0 else { return nil }
            let mx = min(mw - 1, x * mw / w), my = min(mh - 1, y * mh / h)
            return map[my * mw + mx]
        }
        let useDepth: Bool
        if let depth, let share {
            let shares = SubjectTiers.channel(share, 3, width: depth.width, height: depth.height, context: context)
            useDepth = RestorationEngine.depthTrust(depth: depth.values, share: shares) >= 0.5
        } else { useDepth = false }
        let g1 = blur.gaussian(1)
        var fine = blur.gaussian(3)
        for i in fine.indices { fine[i] = g1[i] - fine[i] }
        var noise = [Float](repeating: 0, count: w * h)
        for i in noise.indices { let d = Y[i] - g1[i]; noise[i] = d * d }
        noise = boxMean(noise, w, h, radius: 16).map { $0.squareRoot() * 1.25 }

        var found: [(x: Int, y: Int, peak: Float, area: Int, s: Float, bump: Float)] = []
        for s in sizes {
            let a = blur.gaussian(s), b = blur.gaussian(3.3 * s)
            var band = [Float](repeating: 0, count: w * h)
            for i in band.indices { band[i] = a[i] - b[i] }
            let spread = boxMean(band.map(abs), w, h, radius: 32)
            let win = (Int(4 * s) | 1) / 2
            // Bright local maxima (any peak) for the cluster test, then the candidates among them.
            let top = maxFilter(band, w, h, radius: win)
            var maxima: [(Int, Int)] = []
            for y in 0..<h { for x in 0..<w {
                let i = y * w + x, v = band[i]
                if v > max(floor, k * spread[i]), v >= top[i] { maxima.append((x, y)) }
            }}
            let rr = 3.3 * s, m = Int(rr.rounded(.up)) + 2
            let clusterBox = (Int(16 * s) | 1) / 2
            for (x, y) in maxima {
                let i = y * w + x, p = band[i]
                guard p < maxPeak, y >= m, x >= m, y < h - m, x < w - m else { continue }
                if let v = at(shareMap, w, h, x, y), v < Self.share { continue }
                if let sm = subjects, let v = at(sm.values, sm.width, sm.height, x, y), v > subject { continue }
                if useDepth, let d = depth, let v = at(d.values, d.width, d.height, x, y), v < far { continue }
                let near = maxima.reduce(0) { $0 + (abs($1.0 - x) <= clusterBox && abs($1.1 - y) <= clusterBox ? 1 : 0) }
                if near - 1 > cluster { continue }
                if fine[i] > soft * p { continue }
                var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
                for n in 0..<16 {
                    let t = Float(n) * 2 * .pi / 16
                    let v = band[Int(Float(y) + rr * sin(t)) * w + Int(Float(x) + rr * cos(t))]
                    lo = min(lo, v); hi = max(hi, v)
                }
                if hi - lo > ring * p { continue }
                guard let (area, fill) = halfMaxRegion(band, w, h, x, y, radius: Int(rr.rounded(.up)), peak: p),
                      Float(area) <= 40 * s * s, fill >= Self.round else { continue }
                let r = max(2.5, 1.6 * (Float(area) / .pi).squareRoot())
                let R = Int((2.4 * r).rounded(.up))
                guard y >= R, x >= R, y < h - R, x < w - R else { continue }
                var sum: Float = 0, sum2: Float = 0, n: Float = 0
                for yy in -R...R { for xx in -R...R {
                    let d = (Float(xx * xx + yy * yy)).squareRoot()
                    guard d >= 1.4 * r, d <= 2.4 * r else { continue }
                    let v = Y[(y + yy) * w + x + xx]; sum += v; sum2 += v * v; n += 1
                }}
                let mean = sum / max(1, n), sd = max(0, sum2 / max(1, n) - mean * mean).squareRoot()
                if sd > flat * noise[i] + 0.5 { continue }
                // Bump: the smooth luma at the centre over the ring at 1.3 r (the base the removal uses).
                var base: Float = 0, nb: Float = 0
                for yy in -R...R { for xx in -R...R {
                    let d = (Float(xx * xx + yy * yy)).squareRoot()
                    guard d >= 1.3 * r, d < 1.3 * r + 3 else { continue }
                    base += Y[(y + yy) * w + x + xx]; nb += 1
                }}
                let bump = a[i] - base / max(1, nb)
                if let limit = maxBump, bump > limit { continue }
                found.append((x, y, p, area, s, bump))
            }
        }
        found.sort { $0.peak > $1.peak }
        var kept: [(x: Int, y: Int, peak: Float, area: Int, s: Float, bump: Float)] = []
        for f in found where kept.allSatisfy({ hypot(Float(f.x - $0.x), Float(f.y - $0.y)) > 2 * max(f.s, $0.s) }) { kept.append(f) }
        guard !kept.isEmpty else { return nil }

        // Patches of linear factors: the smooth bump comes off the Gaussian-s colour, at each pixel's smooth level.
        var patches: [Patch] = [], spots: [Spot] = []
        for f in kept {
            let r = max(2.5, 1.6 * (Float(f.area) / .pi).squareRoot())
            let x0 = max(0, Int(Float(f.x) - 2 * r - 4)), x1 = min(w, Int(Float(f.x) + 2 * r + 5))
            let y0 = max(0, Int(Float(f.y) - 2 * r - 4)), y1 = min(h, Int(Float(f.y) + 2 * r + 5))
            let pw = x1 - x0, ph = y1 - y0
            guard pw > 0, ph > 0 else { continue }
            var base = SIMD3<Float>(repeating: 0), n: Float = 0
            for yy in y0..<y1 { for xx in x0..<x1 {
                let d = hypot(Float(xx - f.x), Float(yy - f.y))
                guard d >= 1.3 * r, d < 1.3 * r + 3 else { continue }
                let j = (yy * w + xx) * 3; base += SIMD3(g[j], g[j + 1], g[j + 2]); n += 1
            }}
            guard n >= 8 else { continue }
            base /= n
            let smooth = localGaussian(g, w, h, x0: x0, y0: y0, width: pw, height: ph, sigma: f.s)
            var factors = [Float](repeating: 1, count: pw * ph * 3)
            for yy in 0..<ph { for xx in 0..<pw {
                let d = hypot(Float(x0 + xx - f.x), Float(y0 + yy - f.y))
                let wgt = min(1, max(0, (1.3 * r - d) / (0.5 * r)))
                guard wgt > 0 else { continue }
                for c in 0..<3 {
                    let s0 = smooth[(yy * pw + xx) * 3 + c]
                    let bump = max(0, s0 - base[c])
                    guard s0 > 0.5, bump > 0 else { continue }
                    factors[(yy * pw + xx) * 3 + c] = pow(max(0, s0 - wgt * bump) / s0, 2.2)
                }
            }}
            patches.append(Patch(x: x0, y: y0, width: pw, height: ph, factors: factors))
            spots.append(Spot(x: f.x, y: f.y, radius: r, bump: f.bump))
        }
        return patches.isEmpty ? nil : PhotoOrbs(width: w, height: h, patches: patches, spots: spots)
    }

    /// `image` with the orbs taken off: the factor image, scaled to `image`'s extent, multiplies its linear colour.
    func applied(to image: CIImage) -> CIImage {
        guard !patches.isEmpty, image.extent.width > 0, image.extent.height > 0 else { return image }
        var values = [Float](repeating: 1, count: width * height * 4)
        for p in patches { for yy in 0..<p.height { for xx in 0..<p.width {
            let dst = ((p.y + yy) * width + p.x + xx) * 4, src = (yy * p.width + xx) * 3
            // Overlapping patches multiply.
            for c in 0..<3 { values[dst + c] *= p.factors[src + c] }
        }}}
        let data = values.withUnsafeBytes { Data($0) }
        // Row 0 on top, as RestorationEngine.depthImage reads its map and as render(toBitmap:) writes.
        let factor = CIImage(bitmapData: data, bytesPerRow: width * 16, size: CGSize(width: width, height: height),
                             format: .RGBAf, colorSpace: nil)
        let e = image.extent
        let scaled = factor.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: e.width / CGFloat(width), y: e.height / CGFloat(height)))
            .transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY)).cropped(to: e)
        let multiply = CIFilter(name: "CIMultiplyCompositing")
        multiply?.setValue(scaled, forKey: kCIInputImageKey)
        multiply?.setValue(image, forKey: kCIInputBackgroundImageKey)
        return (multiply?.outputImage ?? image).cropped(to: e)
    }

    // MARK: helpers

    /// A 32-bit float context with no colour management, for the detection blurs.
    private static let floatContext: CIContext = {
        let options: [CIContextOption: Any] = [.workingFormat: CIFormat.RGBAf, .workingColorSpace: NSNull(),
                                               .cacheIntermediates: false]
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device, options: options) }
        return CIContext(options: options)
    }()

    /// Gaussian blurs of one plane on the GPU in 32-bit float, read back as floats (clamped edges).
    private struct Blur {
        let image: CIImage, width: Int, height: Int
        init(_ plane: [Float], width: Int, height: Int) {
            var rgba = [Float](repeating: 0, count: width * height * 4)
            for i in plane.indices { rgba[i * 4] = plane[i]; rgba[i * 4 + 3] = 1 }
            image = CIImage(bitmapData: rgba.withUnsafeBytes { Data($0) }, bytesPerRow: width * 16,
                            size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: nil)
            self.width = width; self.height = height
        }
        func gaussian(_ sigma: Float) -> [Float] {
            let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: image.extent)
            var out = [Float](repeating: 0, count: width * height * 4)
            PhotoOrbs.floatContext.render(blurred, toBitmap: &out, rowBytes: width * 16, bounds: image.extent,
                                          format: .RGBAf, colorSpace: nil)
            return (0..<(width * height)).map { out[$0 * 4] }
        }
    }

    /// Maximum over a (2 radius + 1)^2 box (edges padded with -infinity), separable, by vDSP's sliding window.
    static func maxFilter(_ v: [Float], _ w: Int, _ h: Int, radius: Int) -> [Float] {
        let n = 2 * radius + 1
        var rows = [Float](repeating: 0, count: w * h)
        var line = [Float](repeating: -.infinity, count: max(w, h) + 2 * radius)
        for y in 0..<h {
            for x in 0..<w { line[radius + x] = v[y * w + x] }
            for x in (radius + w)..<(w + 2 * radius) { line[x] = -.infinity }
            rows.withUnsafeMutableBufferPointer { out in
                vDSP_vswmax(line, 1, out.baseAddress! + y * w, 1, vDSP_Length(w), vDSP_Length(n))
            }
        }
        var out = [Float](repeating: 0, count: w * h), col = [Float](repeating: 0, count: h)
        for i in 0..<radius { line[i] = -.infinity }
        for x in 0..<w {
            for y in 0..<h { line[radius + y] = rows[y * w + x] }
            for y in (radius + h)..<(h + 2 * radius) { line[y] = -.infinity }
            vDSP_vswmax(line, 1, &col, 1, vDSP_Length(h), vDSP_Length(n))
            for y in 0..<h { out[y * w + x] = col[y] }
        }
        return out
    }

    /// Mean over a (2 radius + 1)^2 box, edges clamped, by a summed-area table.
    static func boxMean(_ v: [Float], _ w: Int, _ h: Int, radius: Int) -> [Float] {
        var table = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h {
            var row = 0.0
            for x in 0..<w { row += Double(v[y * w + x]); table[(y + 1) * (w + 1) + x + 1] = table[y * (w + 1) + x + 1] + row }
        }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            let x0 = max(0, x - radius), x1 = min(w, x + radius + 1), y0 = max(0, y - radius), y1 = min(h, y + radius + 1)
            let s = table[y1 * (w + 1) + x1] - table[y0 * (w + 1) + x1] - table[y1 * (w + 1) + x0] + table[y0 * (w + 1) + x0]
            out[y * w + x] = Float(s / Double((x1 - x0) * (y1 - y0)))
        }}
        return out
    }

    /// The half-max region of the peak at (x, y) inside a (2 radius + 1)^2 window, 4-connected: its area and how much
    /// of its bounding box it fills. Nil when the centre is not in it.
    static func halfMaxRegion(_ band: [Float], _ w: Int, _ h: Int, _ x: Int, _ y: Int, radius: Int, peak: Float) -> (Int, Float)? {
        let side = 2 * radius + 1
        var seen = [Bool](repeating: false, count: side * side)
        var stack = [(radius, radius)]
        guard band[y * w + x] >= 0.5 * peak else { return nil }
        seen[radius * side + radius] = true
        var area = 0, minX = radius, maxX = radius, minY = radius, maxY = radius
        while let (cx, cy) = stack.popLast() {
            area += 1; minX = min(minX, cx); maxX = max(maxX, cx); minY = min(minY, cy); maxY = max(maxY, cy)
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < side, ny < side, !seen[ny * side + nx] else { continue }
                let gx = x - radius + nx, gy = y - radius + ny
                guard gx >= 0, gy >= 0, gx < w, gy < h, band[gy * w + gx] >= 0.5 * peak else { continue }
                seen[ny * side + nx] = true; stack.append((nx, ny))
            }
        }
        return (area, Float(area) / Float((maxX - minX + 1) * (maxY - minY + 1)))
    }

    /// A Gaussian of the 3-channel plane `g` over one window (edges clamped), by direct separable sums.
    static func localGaussian(_ g: [Float], _ w: Int, _ h: Int, x0: Int, y0: Int, width: Int, height: Int, sigma: Float) -> [Float] {
        let r = Int((3 * sigma).rounded(.up))
        let kernel = (-r...r).map { exp(-Float($0 * $0) / (2 * sigma * sigma)) }
        let total = kernel.reduce(0, +)
        // Rows first over a taller band, then columns.
        let ty0 = y0 - r, th = height + 2 * r
        var rows = [Float](repeating: 0, count: width * th * 3)
        for ty in 0..<th {
            let sy = min(h - 1, max(0, ty0 + ty))
            for xx in 0..<width { for c in 0..<3 {
                var s: Float = 0
                for (k, kv) in kernel.enumerated() { let sx = min(w - 1, max(0, x0 + xx + k - r)); s += kv * g[(sy * w + sx) * 3 + c] }
                rows[(ty * width + xx) * 3 + c] = s / total
            }}
        }
        var out = [Float](repeating: 0, count: width * height * 3)
        for yy in 0..<height { for xx in 0..<width { for c in 0..<3 {
            var s: Float = 0
            for (k, kv) in kernel.enumerated() { s += kv * rows[((yy + k) * width + xx) * 3 + c] }
            out[(yy * width + xx) * 3 + c] = s / total
        }}}
        return out
    }
}
