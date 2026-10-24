import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import simd
import ImageIO
import UniformTypeIdentifiers

// Analysis fields by name, for HT_EVAL_ANALYSIS_FIELDS. WaterAnalysis.fields holds the same key
// paths, but without the names an environment variable needs.
let analysisKeys: [String: WritableKeyPath<WaterAnalysis, Float>] = [
    "redLoss": \.redLoss, "cyanDominance": \.cyanDominance, "exposure": \.exposure,
    "contrast": \.contrast, "saturation": \.saturation,
    "meanRed": \.meanRed, "meanGreen": \.meanGreen, "meanBlue": \.meanBlue,
    "midLuminance": \.midLuminance,
    "waterRed": \.waterRed, "waterGreen": \.waterGreen, "waterBlue": \.waterBlue,
    "neutralRed": \.neutralRed, "neutralGreen": \.neutralGreen, "neutralBlue": \.neutralBlue,
    "neutralShare": \.neutralShare, "highShare": \.highShare, "lightShare": \.lightShare]

// Usage: eval <rawDir> <refDir|-> <outCSV> [all|dev|holdout|N] [sheetDir] [sheetNamesFile]
let args = CommandLine.arguments
let rawDir = URL(fileURLWithPath: args[1])
let refDir: URL? = args[2] == "-" ? nil : URL(fileURLWithPath: args[2])
let outCSV = args[3]
let split = args.count > 4 ? args[4] : "all"
let sheetDir: URL? = args.count > 5 ? URL(fileURLWithPath: args[5]) : nil
let sheetNames: Set<String>? = args.count > 6 ? Set(try String(contentsOfFile: args[6], encoding: .utf8).split(separator: "\n").map(String.init)) : nil
// HT_EVAL_MAXDIM overrides the render size (the AquaColorFix benchmark measures at 960).
let maxDim: CGFloat = CGFloat(Double(ProcessInfo.processInfo.environment["HT_EVAL_MAXDIM"] ?? "") ?? 640)

let engine = FilterEngine()
let depthEstimator = DepthEstimator()
let waterEstimator = WaterModelEstimator()
let restoration = RestorationEngine()
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func load(_ url: URL) -> CIImage? {
    // Camera RAW goes through CIRAWFilter, as PhotoProcessor.openRAW does. CIImage(contentsOf:) would
    // hand back the small embedded preview instead. A camera JPEG and its RAW are different starting
    // images, and the pipeline lands differently on each (docs/JpegInput.md).
    if UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) == true {
        return CIRAWFilter(imageURL: url)?.outputImage
    }
    return CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
}
func fit(_ image: CIImage, width: Int, height: Int) -> CIImage {
    let t = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    return t.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / t.extent.width, y: CGFloat(height) / t.extent.height))
        .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
}
// HT_EVAL_P3=1 writes the app's own output space (FilterEngine.photoSpace, Display P3) instead of
// sRGB. PhotoProcessor saves in P3, so an sRGB sheet is not what the app shows: a saturated orange
// reef is pushed to the sRGB gamut edge and reads redder there (23 Oct 2026).
let outputSpace = ProcessInfo.processInfo.environment["HT_EVAL_P3"] == "1" ? FilterEngine.photoSpace : sRGB
// HT_EVAL_PRECISE_MASK=1 makes both masks with SubjectMask.estimatePrecise (E24), as the single-photo
// editor would, and falls back to estimate when it returns nil.
let preciseMask = ProcessInfo.processInfo.environment["HT_EVAL_PRECISE_MASK"] == "1"
// The model reads notReady in every new process until it has run once, and estimatePrecise never downloads,
// so the harness checks it here. A nil precise mask is reported, never replaced in silence: on 24 Oct 2026 a
// silent fallback rendered three experiments with the old mask (E25).
var preciseChecked = false
@MainActor func subjectMask(_ image: CIImage, cap: Float) async -> SubjectMask? {
    if preciseMask, #available(macOS 27.0, *) {
        if !preciseChecked { preciseChecked = true; print("precise model usable: \(await SubjectMask.preciseModelUsable())") }
        if let m = await SubjectMask.estimatePrecise(image, cap: cap, context: engine.context) { return m }
        print("note: precise mask nil (cap \(cap)): no subject, a share out of range, or the model not ready; trying SubjectMask.estimate")
    }
    return SubjectMask.estimate(image, cap: cap)
}
// HT_EVAL_TIER_MAP=1 gives the lift the soft tier map agreed with the picker session (E25): the picker's
// outline before its 0.5 cut. Natural's correction, a 1024 grid, ramps notWater 0.4-0.6, in front of the
// open water by 0.05-0.15, texture 0.025-0.045, and the outline's cleaning fed back, feathered by 2 cells.
// A prototype: the app gets the same map from SubjectTiers.
let tierMapOn = ProcessInfo.processInfo.environment["HT_EVAL_TIER_MAP"] == "1"
func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(1, max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
func softTiers(_ source: CIImage, plan: RestorationPlan, analysis: WaterAnalysis, subject: SubjectMask?) -> SubjectTierMap? {
    let long = max(source.extent.width, source.extent.height)
    let width = Int((source.extent.width / long * 1024).rounded()), height = Int((source.extent.height / long * 1024).rounded())
    let small = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY)
        .concatenating(CGAffineTransform(scaleX: CGFloat(width) / source.extent.width, y: CGFloat(height) / source.extent.height)))
    var natural = FilterSettings(); natural.analysis = analysis
    let current = restoration.corrections(settings: natural, plan: plan).current
    guard let share = engine.waterShare(small, correction: current), let transmission = restoration.contrastTransmission(small, plan: plan) else { return nil }
    let c = engine.context, n = width * height
    let shareValues = SubjectTiers.channel(share, 3, width: width, height: height, context: c)
    let tValues = SubjectTiers.channel(transmission, 0, width: width, height: height, context: c)
    let map = plan.depth
    let depthImage = CIImage(bitmapData: map.values.withUnsafeBytes { Data($0) }, bytesPerRow: map.width * MemoryLayout<Float>.size,
                             size: CGSize(width: map.width, height: map.height), format: .Rf, colorSpace: nil)
    let depth = SubjectTiers.channel(depthImage, 0, width: width, height: height, context: c)
    let r = SubjectTiers.channel(small, 0, width: width, height: height, context: c), g = SubjectTiers.channel(small, 1, width: width, height: height, context: c)
    let b = SubjectTiers.channel(small, 2, width: width, height: height, context: c)
    let luma = (0..<n).map { i in pow(max(0, 0.2126 * r[i] + 0.7152 * g[i] + 0.0722 * b[i]), 1 / 2.2) }
    let texture = SubjectTiers.texture(luma: luma, width: width, height: height)
    let water = SubjectTiers.waterDepth(waterShare: shareValues, depth: depth)
    var object = [Float](repeating: 0, count: n)
    for i in 0..<n {
        let notWater = smooth(0.4, 0.6, 1 - min(1, max(0, shareValues[i])))
        let front = water.map { 1 - smooth($0 - 0.15, $0 - 0.05, depth[i]) } ?? 1
        // No subject factor: the kernel takes the picked subjects out with (1 - w), so an excluded subject is
        // treated like the scene around it (Jake, 24 Oct 2026). The app's SubjectTiers.make does the same.
        object[i] = notWater * front * smooth(0.025, 0.045, texture[i])
    }
    let kept = SubjectTiers.cleaned(object.map { $0 >= 0.5 }, width: width, height: height,
                                    minimum: max(1, Int(Float(n) * SubjectTiers.minimumPieceShare)), hole: max(1, Int(Float(n) * SubjectTiers.minimumHoleShare)))
    // Feather the cleaned outline: a 5 x 5 box, so the cleaning makes no step in the lift.
    var feather = [Float](repeating: 0, count: n)
    for y in 0..<height { for x in 0..<width {
        var sum: Float = 0, count: Float = 0
        for dy in -2...2 { for dx in -2...2 { let yy = y + dy, xx = x + dx; if yy >= 0, yy < height, xx >= 0, xx < width { sum += kept[yy * width + xx] ? 1 : 0; count += 1 } } }
        feather[y * width + x] = sum / count
    } }
    let t = tValues.map { min(1, max(0, $0)) }
    return SubjectTierMap(width: width, height: height, tier2: (0..<n).map { object[$0] * feather[$0] * t[$0] },
                          tier3: (0..<n).map { object[$0] * feather[$0] * (1 - t[$0]) })
}
func render(_ image: CIImage, _ w: Int, _ h: Int) -> [UInt8] {
    var px = [UInt8](repeating: 0, count: w * h * 4)
    engine.context.render(image, toBitmap: &px, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: h),
                          format: .RGBA8, colorSpace: outputSpace)
    return px
}
func save(_ image: CIImage, _ url: URL) {
    guard let cg = engine.context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: outputSpace),
          let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    CGImageDestinationFinalize(d)
    // Lossless companion for patch colour and noise measurements. Keep JPEG sheets compatible.
    if ProcessInfo.processInfo.environment["HT_EVAL_PNG"] == "1",
       let png = CGImageDestinationCreateWithURL(url.deletingPathExtension().appendingPathExtension("png") as CFURL,
                                                UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(png, cg, nil)
        CGImageDestinationFinalize(png)
    }
}
func grayWorld(_ image: CIImage) -> CIImage {
    let avg = CIFilter.areaAverage(); avg.inputImage = image; avg.extent = image.extent
    var m = [Float](repeating: 0, count: 4)
    engine.context.render(avg.outputImage!, toBitmap: &m, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                          format: .RGBAf, colorSpace: FilterEngine.workingSpace)
    let mean = (m[0] + m[1] + m[2]) / 3
    let g = (0..<3).map { CGFloat(min(4, mean / max(0.002, m[$0]))) }
    let f = CIFilter.colorMatrix(); f.inputImage = image
    f.rVector = CIVector(x: g[0], y: 0, z: 0, w: 0); f.gVector = CIVector(x: 0, y: g[1], z: 0, w: 0)
    f.bVector = CIVector(x: 0, y: 0, z: g[2], w: 0)
    return f.outputImage!.cropped(to: image.extent)
}

// sRGB8 -> Lab (D65)
func lab(_ r8: UInt8, _ g8: UInt8, _ b8: UInt8) -> SIMD3<Float> {
    func lin(_ v: UInt8) -> Float { let c = Float(v) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    let r = lin(r8), g = lin(g8), b = lin(b8)
    let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    func f(_ t: Float) -> Float { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
    return SIMD3(116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
}
struct Metrics { var psnr = Float.nan, ssim = Float.nan, deltaE = Float.nan
    var farHue: Float = 0, farChroma: Float = 0, nearA: Float = 0, nearRG: Float = 0, contrastL: Float = 0
    var meanL: Float = 0, localContrast: Float = 0, farLocalContrast: Float = 0
    var farHueOK: Float = 0, farChromaOK: Float = 0
    // Subject lift metrics (docs/SubjectEmphasis.md, E3). Nil mask leaves them at nan, not 0:
    // a zero would read as measured. See the plan's note on unmeasured cells.
    var subjectShare = Float.nan, subjectL = Float.nan, outsideL = Float.nan
    var subjectChroma = Float.nan, subjectViolet = Float.nan, clipped: Float = 0, subjectClipped = Float.nan
    var outsideChroma = Float.nan
    // Subject-only texture. The plain localContrast is the whole frame, which hides the subject.
    var subjectLocalContrast = Float.nan, subjectOvershoot = Float.nan }

/// Middle value of an unsorted array. Nan when empty.
func median(_ v: [Float]) -> Float {
    guard !v.isEmpty else { return .nan }
    let s = v.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

// OKLab (a, b) of an sRGB8 pixel. OKLab hue separates azure, blue, indigo and violet, where CIELAB hue does not.
func okab(_ r8: UInt8, _ g8: UInt8, _ b8: UInt8) -> SIMD2<Float> {
    func lin(_ v: UInt8) -> Float { let c = Float(v) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    let r = lin(r8), g = lin(g8), b = lin(b8)
    let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return SIMD2(1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}
func toneMetrics(_ px: [UInt8], _ w: Int, _ h: Int, depth: NormalizedDepthMap, mask: SubjectMask? = nil) -> Metrics {
    var m = Metrics()
    var farOK = SIMD2<Float>(0, 0)
    var far = SIMD2<Float>(0, 0), farN: Float = 0, nearA: Float = 0, nearR: Float = 0, nearG: Float = 0, nearN: Float = 0
    var Ls: [Float] = []; Ls.reserveCapacity(w * h)
    // Inside the mask against outside it. A pixel counts as subject above 0.5, as the picker does.
    var subjectLs: [Float] = [], outsideLs: [Float] = [], subjectCs: [Float] = [], outsideCs: [Float] = []
    var maskSum: Float = 0, violetN: Float = 0, subjectN: Float = 0, clipped: Float = 0, subjectClipped: Float = 0
    let sorted = depth.values.sorted()
    let farCut = sorted[sorted.count * 7 / 10], nearCut = sorted[sorted.count * 3 / 10]
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        let l = lab(px[i], px[i+1], px[i+2]); Ls.append(l.x)
        let d = depth.values[(y * depth.height / h) * depth.width + (x * depth.width / w)]
        if d >= farCut { far += SIMD2(l.y, l.z); farOK += okab(px[i], px[i+1], px[i+2]); farN += 1 }
        if d <= nearCut { nearA += l.y; nearR += Float(px[i]); nearG += Float(px[i+1]); nearN += 1 }
        if px[i] == 255 || px[i+1] == 255 || px[i+2] == 255 { clipped += 1 }
        if let mask {
            let mv = mask.values[(y * mask.height / h) * mask.width + (x * mask.width / w)]
            maskSum += mv
            guard mv > 0.5 else {
                // The lift scales chroma, so the water guard has to watch chroma, not only L.
                let ab = okab(px[i], px[i+1], px[i+2])
                outsideLs.append(l.x); outsideCs.append(sqrt(ab.x * ab.x + ab.y * ab.y)); continue
            }
            let ab = okab(px[i], px[i+1], px[i+2])
            let chroma = sqrt(ab.x * ab.x + ab.y * ab.y)
            subjectLs.append(l.x); subjectCs.append(chroma); subjectN += 1
            if px[i] == 255 || px[i+1] == 255 || px[i+2] == 255 { subjectClipped += 1 }
            var hue = atan2(ab.y, ab.x) * 180 / .pi; if hue < 0 { hue += 360 }
            // Violet band from scripts/color-eval/README.md, with the 0.03 chroma floor the
            // ColorAlgorithm Rejected table uses, so near-grey pixels do not count.
            if hue >= 282, chroma >= 0.03 { violetN += 1 }
        }
    } }
    far /= max(1, farN)
    var hue = atan2(far.y, far.x) * 180 / .pi; if hue < 0 { hue += 360 }
    m.farHue = hue; m.farChroma = sqrt(far.x * far.x + far.y * far.y)
    farOK /= max(1, farN)
    var hueOK = atan2(farOK.y, farOK.x) * 180 / .pi; if hueOK < 0 { hueOK += 360 }
    m.farHueOK = hueOK; m.farChromaOK = sqrt(farOK.x * farOK.x + farOK.y * farOK.y)
    m.nearA = nearA / max(1, nearN); m.nearRG = nearR / max(1, nearG)
    let mean = Ls.reduce(0, +) / Float(Ls.count)
    m.contrastL = sqrt(Ls.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(Ls.count))
    m.meanL = mean
    // Haze proxy independent of hue: a veil lowers local L* contrast. 16x16 non-overlapping windows.
    var local: Float = 0, localN: Float = 0, farLocal: Float = 0, farLocalN: Float = 0
    var subjLocal: Float = 0, subjLocalN: Float = 0, over: Float = 0
    for y0 in stride(from: 0, through: h - 16, by: 16) { for x0 in stride(from: 0, through: w - 16, by: 16) {
        var s: Float = 0, s2: Float = 0
        for y in y0..<(y0 + 16) { for x in x0..<(x0 + 16) { let v = Ls[y * w + x]; s += v; s2 += v * v } }
        let sd = sqrt(max(0, s2 / 256 - (s / 256) * (s / 256)))
        local += sd; localN += 1
        let d = depth.values[((y0 + 8) * depth.height / h) * depth.width + ((x0 + 8) * depth.width / w)]
        if d >= farCut { farLocal += sd; farLocalN += 1 }
        if let mask, mask.values[((y0 + 8) * mask.height / h) * mask.width + ((x0 + 8) * mask.width / w)] > 0.5 {
            // How far the window's brightest and darkest pixels sit from its mean. A halo shows up here
            // before it shows up in the standard deviation.
            var hi = -Float.greatestFiniteMagnitude, lo = Float.greatestFiniteMagnitude
            for y in y0..<(y0 + 16) { for x in x0..<(x0 + 16) {
                hi = max(hi, Ls[y * w + x]); lo = min(lo, Ls[y * w + x])
            } }
            subjLocal += sd; subjLocalN += 1; over += (hi - s / 256) + (s / 256 - lo)
        }
    } }
    m.localContrast = local / max(1, localN); m.farLocalContrast = farLocal / max(1, farLocalN)
    m.clipped = clipped / Float(w * h)
    if mask != nil {
        m.subjectShare = maskSum / Float(w * h)
        m.subjectL = median(subjectLs); m.outsideL = median(outsideLs); m.subjectChroma = median(subjectCs)
        m.outsideChroma = median(outsideCs)
        if subjLocalN > 0 { m.subjectLocalContrast = subjLocal / subjLocalN; m.subjectOvershoot = over / subjLocalN }
        m.subjectViolet = subjectN > 0 ? violetN / subjectN : .nan
        m.subjectClipped = subjectN > 0 ? subjectClipped / subjectN : .nan
    }
    return m
}
func fullReference(_ a: [UInt8], _ b: [UInt8], _ w: Int, _ h: Int, into m: inout Metrics) {
    var se: Double = 0, de: Double = 0
    var la = [Float](repeating: 0, count: w * h), lb = la
    for p in 0..<(w * h) {
        let i = p * 4
        for c in 0..<3 { let d = Double(a[i+c]) - Double(b[i+c]); se += d * d }
        let x = lab(a[i], a[i+1], a[i+2]), y = lab(b[i], b[i+1], b[i+2])
        de += Double(simd_length(x - y)); la[p] = x.x; lb[p] = y.x
    }
    let mse = se / Double(w * h * 3)
    m.psnr = Float(10 * log10(255 * 255 / max(mse, 1e-10))); m.deltaE = Float(de / Double(w * h))
    // SSIM on L*, 8x8 box windows, stride 4.
    let c1: Float = pow(0.01 * 100, 2), c2: Float = pow(0.03 * 100, 2)
    var total: Float = 0, n: Float = 0
    for y in stride(from: 0, through: h - 8, by: 4) { for x in stride(from: 0, through: w - 8, by: 4) {
        var ma: Float = 0, mb: Float = 0
        for j in 0..<8 { for k in 0..<8 { ma += la[(y+j)*w+x+k]; mb += lb[(y+j)*w+x+k] } }
        ma /= 64; mb /= 64
        var va: Float = 0, vb: Float = 0, cv: Float = 0
        for j in 0..<8 { for k in 0..<8 { let p = la[(y+j)*w+x+k] - ma, q = lb[(y+j)*w+x+k] - mb; va += p*p; vb += q*q; cv += p*q } }
        va /= 63; vb /= 63; cv /= 63
        total += ((2*ma*mb + c1) * (2*cv + c2)) / ((ma*ma + mb*mb + c1) * (va + vb + c2)); n += 1
    } }
    m.ssim = total / max(1, n)
}

// HT_EVAL_ABLATE=1 (E27) adds `abl_<stage>` outputs: the current path with one finishing stage off.
// HT_EVAL_VIDEO_PATH=1 adds `videopath`: combined() as video calls it (video: true), to check a photo-only change leaves it.
let videoPath = ProcessInfo.processInfo.environment["HT_EVAL_VIDEO_PATH"] == "1"
let ablations: [(String, (inout ColorCorrection) -> Void)] = ProcessInfo.processInfo.environment["HT_EVAL_ABLATE"] == "1" ? [
    ("none", { _ in }), ("clarity", { $0.clarity = 0 }), ("definition", { $0.definition = 0 }), ("detail", { $0.detail = 0 }),
    ("shadows", { $0.shadowLift = 0; $0.highlightAmount = 1 }), ("vibrance", { $0.vibrance = 0 }), ("saturation", { $0.saturation = 1 }),
    ("tone", { $0.contrast = 1; $0.brightness = 0; $0.toneCurve = 0; $0.midLift = 0 }), ("subject", { $0.subjectTone = SIMD3(repeating: 1) }),
    ("neutral", { $0.neutralGains = SIMD3(repeating: 1) }), ("reference", { $0.referenceStrength = 0 }),
    ("local", { $0.clarity = 0; $0.definition = 0; $0.detail = 0; $0.shadowLift = 0; $0.highlightAmount = 1 }),
    ("all", { $0.clarity = 0; $0.definition = 0; $0.detail = 0; $0.shadowLift = 0; $0.highlightAmount = 1; $0.contrast = 1; $0.brightness = 0
              $0.toneCurve = 0; $0.midLift = 0; $0.vibrance = 0; $0.saturation = 1; $0.warmth = 0 })] : []
let variants = ["original", "grayworld", "current", "restoration", "combined", "lift", "uniform", "reference", "signal"] + ablations.map { "abl_\($0.0)" } + (ablations.isEmpty ? [] : ["abl_calm", "abl_bare", "abl_combsubject", "abl_combrestored"]) + (videoPath ? ["videopath"] : [])
var csv = "image,variant,psnr,ssim,deltaE,farHue,farChroma,nearA,nearRG,contrastL,meanL,localContrast,farLocalContrast,farHueOK,farChromaOK,fallback,confidence,depthConf,waterConf,betaDR,betaDG,betaDB,binfR,binfG,binfB,floorPct,gainPct,recR,subjectShare,subjectL,outsideL,subjectChroma,subjectViolet,clipped,subjectClipped,outsideChroma,subjectLocalContrast,subjectOvershoot\n"
let files = try FileManager.default.contentsOfDirectory(atPath: rawDir.path).filter { [".png", ".jpg", ".jpeg", ".arw"].contains(where: $0.lowercased().hasSuffix) }.sorted()
let started = Date()
var done = 0
// "dev:N" = visual-set names + first N dev images; "holdout:N" = first N holdout images.
let parts = split.split(separator: ":").map(String.init)
let cap = parts.count > 1 ? Int(parts[1]) ?? .max : .max
var taken = 0
let selected: [String] = files.enumerated().compactMap { i, f in
    switch parts[0] {
    case "dev", "holdout":
        guard (i % 2 == 1) == (parts[0] == "dev") else { return nil }
        if parts[0] == "dev", sheetNames?.contains(f) ?? false { return f }
        guard taken < cap else { return nil }
        taken += 1; return f
    case "all": return f
    default: return i < (Int(split) ?? .max) ? f : nil }
}
for name in selected {
    guard let rawFull = load(rawDir.appendingPathComponent(name)) else { continue }
    let scale = min(1, maxDim / max(rawFull.extent.width, rawFull.extent.height))
    let w = Int(rawFull.extent.width * scale), h = Int(rawFull.extent.height * scale)
    let source = fit(engine.sdr(rawFull), width: w, height: h)
    // HT_EVAL_ANALYSIS_SWAP="<from>:<to>" analyses a different file and renders this one with it.
    // It answers one question: how much of a result comes from the analysis, and how much from the
    // image itself. "_jpg.jpg:_raw.arw" renders a camera JPEG with its RAW's analysis.
    // As PhotoProcessor does: the veil's mask, made before the analysis, which trusts a white
    // reference on a subject. HT_EVAL_NO_SUBJECT_REFERENCE=1 analyses without it, as 1.1.4 did.
    let subjects = await subjectMask(source, cap: SubjectMask.maximumShare)
    var analysis = engine.analyze(source, subjects: ProcessInfo.processInfo.environment["HT_EVAL_NO_SUBJECT_REFERENCE"] == nil ? subjects : nil)
    if let swap = ProcessInfo.processInfo.environment["HT_EVAL_ANALYSIS_SWAP"] {
        let parts = swap.split(separator: ":").map(String.init)
        precondition(parts.count == 2, "HT_EVAL_ANALYSIS_SWAP needs <from>:<to>")
        guard name.hasSuffix(parts[0]) else { print("skip \(name): no \(parts[0])"); continue }
        let other = rawDir.appendingPathComponent(String(name.dropLast(parts[0].count)) + parts[1])
        guard let otherFull = load(other) else { print("swap failed \(other.lastPathComponent)"); continue }
        let otherAnalysis = engine.analyze(fit(engine.sdr(otherFull), width: w, height: h))
        // HT_EVAL_ANALYSIS_FIELDS="waterRed,waterGreen" copies only those fields. Unset copies all.
        // One field at a time says which part of the analysis carries a result.
        if let names = ProcessInfo.processInfo.environment["HT_EVAL_ANALYSIS_FIELDS"] {
            for name in names.split(separator: ",").map(String.init) {
                guard let key = analysisKeys[name] else { preconditionFailure("unknown analysis field \(name)") }
                analysis[keyPath: key] = otherAnalysis[keyPath: key]
            }
        } else {
            analysis = otherAnalysis
        }
    }
    var settings = FilterSettings(); settings.analysis = analysis
    // HT_EVAL_INTENSITY overrides the preset slider, to match a given app export.
    if let i = ProcessInfo.processInfo.environment["HT_EVAL_INTENSITY"], let v = Float(i) { settings.intensity = v }
    // HT_EVAL_CUSTOM="brightness,contrast,saturation,clarity,temperature" renders the Custom preset at those slider positions.
    if let custom = ProcessInfo.processInfo.environment["HT_EVAL_CUSTOM"] {
        let p = custom.split(separator: ",").compactMap { Float($0) }
        precondition(p.count == 5, "HT_EVAL_CUSTOM needs five numbers")
        settings.preset = .custom
        settings.adjustments = CustomAdjustments(brightness: p[0], contrast: p[1], saturation: p[2], clarity: p[3], temperature: p[4])
    }
    var plan: RestorationPlan?
    var depthMap: NormalizedDepthMap?
    var liftMask: SubjectMask?
    do {
        let depth = try await depthEstimator.monocularDepth(for: source)
        depthMap = depth.map
        plan = try waterEstimator.estimate(image: source, depth: depth, legacy: analysis, context: engine.context)
        // As PhotoProcessor does. The uniform (video) plan below has no mask, as video has none.
        plan?.subjectMask = subjects
        // The subject lift has its own cap (docs/SubjectEmphasis.md, E2), so m5's coral block counts.
        liftMask = await subjectMask(source, cap: SubjectMask.liftMaximumShare)
        // HT_EVAL_WATER_SWAP="<from>:<to>" fits the water model on a different file and puts it on
        // this image's plan. Depth, limits and the subject mask stay this image's. It separates the
        // water fit from the image, the way HT_EVAL_ANALYSIS_SWAP separates the analysis.
        if let swap = ProcessInfo.processInfo.environment["HT_EVAL_WATER_SWAP"], let mine = plan {
            let parts = swap.split(separator: ":").map(String.init)
            precondition(parts.count == 2, "HT_EVAL_WATER_SWAP needs <from>:<to>")
            let other = rawDir.appendingPathComponent(String(name.dropLast(parts[0].count)) + parts[1])
            guard name.hasSuffix(parts[0]), let otherFull = load(other) else { print("water swap failed \(name)"); continue }
            let otherSource = fit(engine.sdr(otherFull), width: w, height: h)
            let otherDepth = try await depthEstimator.monocularDepth(for: otherSource)
            guard let theirs = try? waterEstimator.estimate(image: otherSource, depth: otherDepth,
                                                            legacy: engine.analyze(otherSource), context: engine.context)
            else { print("water swap fit failed \(name)"); continue }
            var swapped = RestorationPlan(depth: mine.depth, depthSource: mine.depthSource,
                                          depthStatistics: mine.depthStatistics,
                                          backscatterInfinity: theirs.backscatterInfinity,
                                          betaDirect: theirs.betaDirect, betaBackscatter: theirs.betaBackscatter,
                                          confidence: mine.confidence, limits: mine.limits,
                                          transmissionFloorPixelPercentage: mine.transmissionFloorPixelPercentage,
                                          maximumGainPixelPercentage: mine.maximumGainPixelPercentage,
                                          depthConfidence: mine.depthConfidence,
                                          waterFitConfidence: theirs.waterFitConfidence,
                                          temporalConfidence: mine.temporalConfidence,
                                          channelRecoverability: theirs.channelRecoverability)
            swapped.veilLevel = mine.veilLevel
            swapped.subjectMask = mine.subjectMask
            plan = swapped
        }
        if ProcessInfo.processInfo.environment["HT_EVAL_LOG"] != nil, let m = plan?.subjectMask { print("\(name) subjects: \(m.width)x\(m.height) share=\(m.values.reduce(0, +) / Float(m.values.count))") }
    } catch { }
    guard let depthMap else { print("depth failed \(name)"); continue }
    let current = engine.apply(source, settings: settings)
    if ProcessInfo.processInfo.environment["HT_EVAL_LOG"] != nil {
        let a = analysis
        print("\(name) analysis: redLoss=\(a.redLoss) contrast=\(a.contrast) sat=\(a.saturation) mean=(\(a.meanRed),\(a.meanGreen),\(a.meanBlue)) mid=\(a.midLuminance) water=(\(a.waterRed),\(a.waterGreen),\(a.waterBlue)) neutral=(\(a.neutralRed),\(a.neutralGreen),\(a.neutralBlue)) share=\(a.neutralShare) high=\(a.highShare)")
        for (label, c) in [("current", ColorCorrection.make(analysis: analysis, preset: settings.preset)),
                           ("restored", plan.map { ColorCorrection.make(analysis: analysis, preset: settings.preset, plan: $0) })] {
            guard let c else { continue }
            // Reflection keeps this harness usable against older source snapshots without these fields.
            let referenceValues = Mirror(reflecting: c).children.filter { $0.label?.hasPrefix("reference") == true }
            if !referenceValues.isEmpty {
                print("\(name) \(label) adaptation: " + referenceValues.map { "\($0.label!)=\($0.value)" }.joined(separator: " "))
            }
            print("\(name) \(label): gains=(\(c.castGains.x),\(c.castGains.y),\(c.castGains.z)) water=(\(c.waterTone.x),\(c.waterTone.y),\(c.waterTone.z))x\(c.waterSaturation) redness=\(c.waterRedness) chroma=\(c.waterChroma) type=\(c.waterType) guard=\(c.violetGuard) gate=\(c.redGateLow) rebuild=\(c.redRebuild) subjectRed=\(c.subjectRed) midLift=\(c.midLift) curve=\(c.toneCurve)@\(c.tonePivot) bright=\(c.brightness) contrast=\(c.contrast) sat=\(c.saturation) shadows=\(c.shadowLift) clarity=\(c.clarity) def=\(c.definition) vib=\(c.vibrance) weight=\(c.physicalWeight) neutral=(\(c.neutralGains.x),\(c.neutralGains.y),\(c.neutralGains.z)) subject=(\(c.subjectTone.x),\(c.subjectTone.y),\(c.subjectTone.z)) waterLit=(\(c.waterLit.x),\(c.waterLit.y),\(c.waterLit.z))")
        }
        // Probe: one colour (working space, linear) through the colour kernel alone and through the whole
        // finishing chain, so a tuning run can see what each stage does to the water, the neutral surface and the subject.
        func probe(_ c: SIMD3<Float>, _ v: ColorCorrection) -> String {
            let kernel = FinishingMath.color(c, correction: v)
            let color = CIImage(color: CIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), colorSpace: FilterEngine.workingSpace)!)
                .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
            var px = [Float](repeating: 0, count: 4)
            engine.context.render(engine.finishing(color, correction: v), toBitmap: &px, rowBytes: 16,
                                  bounds: CGRect(x: 8, y: 8, width: 1, height: 1), format: .RGBAf, colorSpace: FilterEngine.workingSpace)
            func f(_ x: SIMD3<Float>) -> String { let l = ColorCorrection.oklch(x); return "(\(String(format: "%.3f,%.3f,%.3f", x.x, x.y, x.z))) h\(Int(l.z)) C\(String(format: "%.3f", l.y))" }
            return "in \(f(c)) -> kernel \(f(kernel)) waterLike \(String(format: "%.2f", FinishingMath.waterLike(c * v.castGains, correction: v))) neutralW \(String(format: "%.2f", FinishingMath.neutralWeight(c * v.castGains, correction: v))) -> chain \(f(SIMD3(px[0], px[1], px[2])))"
        }
        let currentValues = ColorCorrection.make(analysis: analysis, preset: settings.preset)
        for (label, c) in [("water", a.waterColor), ("neutral", a.neutralColor), ("mean", a.meanColor)] where c.max() > 0 {
            print("\(name) probe current \(label): \(probe(c, currentValues))")
            if let plan {
                let v = ColorCorrection.make(analysis: analysis, preset: settings.preset, plan: plan)
                let sorted = plan.depth.values.sorted()
                let restored = ColorCorrection.restoredMean(c, plan: plan, depth: label == "neutral" ? sorted[sorted.count * 35 / 100] : nil)
                print("\(name) probe restored \(label): \(probe(restored, v))")
            }
        }
        if let p = plan { print("\(name) plan: conf=\(p.confidence) depthConf=\(p.depthConfidence) fit=\(p.waterFitConfidence) binf=\(p.backscatterInfinity) betaD=\(p.betaDirect) betaB=\(p.betaBackscatter) rec=\(p.channelRecoverability) medianDepth=\(p.depth.median)") }
    }
    var outputs: [String: CIImage] = ["original": source, "grayworld": grayWorld(source), "current": current]
    // HT_EVAL_PROBE="r,g,b;..." (sRGB 0-255, E27): prints the kernel mirror's water-like weight and colour for each.
    if let probe = ProcessInfo.processInfo.environment["HT_EVAL_PROBE"] {
        let v = ColorCorrection.make(analysis: settings.analysis, preset: settings.preset, adjustments: settings.adjustments)
        print("\(name) probe waterChroma=\(v.waterChroma) waterRedness=\(v.waterRedness)")
        for item in probe.split(separator: ";") {
            let p = item.split(separator: ",").compactMap { Float($0) }; guard p.count == 3 else { continue }
            func lin(_ x: Float) -> Float { let u = x / 255; return u <= 0.04045 ? u / 12.92 : pow((u + 0.055) / 1.055, 2.4) }
            let input = FinishingMath.working(SIMD3(lin(p[0]), lin(p[1]), lin(p[2])))
            let c = input * v.castGains, top = c.max()
            let out = FinishingMath.display(FinishingMath.color(input, correction: v))
            func enc(_ x: Float) -> Int { let u = min(1, max(0, x)); return Int(255 * (u <= 0.0031308 ? 12.92 * u : 1.055 * pow(u, 1 / 2.4) - 0.055)) }
            print("  \(item): chroma=\((top - c.min()) / max(top, 1e-4)) waterLike=\(FinishingMath.waterLike(c, correction: v)) out=(\(enc(out.x)),\(enc(out.y)),\(enc(out.z)))")
        }
    }
    for (key, change) in ablations {
        var c = ColorCorrection.make(analysis: settings.analysis, preset: settings.preset, adjustments: settings.adjustments); change(&c)
        outputs["abl_\(key)"] = engine.apply(source, correction: c, intensity: settings.appliedIntensity)
    }
    if !ablations.isEmpty {
        let c = ColorCorrection.make(analysis: settings.analysis, preset: settings.preset, adjustments: settings.adjustments)
        outputs["abl_calm"] = engine.apply(source, correction: c, intensity: settings.appliedIntensity, calmWeight: CIImage(color: .black).cropped(to: source.extent))
        var bare = c; ablations.first { $0.0 == "all" }?.1(&bare)
        outputs["abl_bare"] = engine.apply(source, correction: bare, intensity: settings.appliedIntensity, calmWeight: CIImage(color: .black).cropped(to: source.extent))
        if let plan {
            var off = restoration.corrections(settings: settings, plan: plan)
            off.current.subjectTone = SIMD3(repeating: 1); off.restored.subjectTone = SIMD3(repeating: 1)
            outputs["abl_combsubject"] = try? restoration.combined(source, plan: plan, values: off, settings: settings, filter: engine)
            var offR = restoration.corrections(settings: settings, plan: plan); offR.restored.subjectTone = SIMD3(repeating: 1)
            outputs["abl_combrestored"] = try? restoration.combined(source, plan: plan, values: offR, settings: settings, filter: engine)
        }
    }
    if let plan, let raw = try? restoration.restore(source, plan: plan) {
        outputs["restoration"] = engine.blend(source, raw, amount: plan.confidence)
        outputs["combined"] = (try? restoration.combined(source, plan: plan, settings: settings, filter: engine)) ?? current
        if videoPath { outputs["videopath"] = try? restoration.combined(source, plan: plan, values: restoration.corrections(settings: settings, plan: plan), settings: settings, filter: engine, video: true) }
        // HT_EVAL_LIFT="strength,chromaCap,highlightStart,noiseFloor,chromaExponent,contrast" renders the lift as its own
        // variant (docs/SubjectEmphasis.md, E4). Without the mask the lift output equals combined.
        if let liftMask, let spec = ProcessInfo.processInfo.environment["HT_EVAL_LIFT"] {
            let v = spec.split(separator: ",").compactMap { Float($0) }
            precondition(v.count == 15, "HT_EVAL_LIFT: strength,chromaCap,highlightStart,noiseFloor,chromaExponent,contrast,detail,clarity,highlights,maskLow,maskHigh,tier2,tier3,highlights2,highlights3")
            var lift = SubjectLift(mask: liftMask, strength: v[0], chromaCap: v[1], tier2: v[11],
                                   tier3: v[12], highlights2: v[13], highlights3: v[14],
                                   maskLow: v[9], maskHigh: v[10], clarity: v[7], highlights: v[8],
                                   detail: v[6], contrast: v[5], chromaExponent: v[4],
                                   highlightStart: v[2], noiseFloor: v[3])
            if tierMapOn { lift.tiers = softTiers(source, plan: plan, analysis: analysis, subject: liftMask) }
            // HT_EVAL_TIER_DUMP=<dir> writes the map as <name>_tiers.png: red tier two, green tier three.
            if let dir = ProcessInfo.processInfo.environment["HT_EVAL_TIER_DUMP"], let map = lift.tiers,
               let cg = engine.context.createCGImage(map.image(matching: CGRect(x: 0, y: 0, width: map.width, height: map.height)),
                                                     from: CGRect(x: 0, y: 0, width: map.width, height: map.height)),
               let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(dir)/\(name)_tiers.png") as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, cg, nil); CGImageDestinationFinalize(dest)
            }
            outputs["lift"] = (try? restoration.combined(source, plan: plan, settings: settings, filter: engine,
                                                         subjectLift: lift)) ?? outputs["combined"]
        } else {
            outputs["lift"] = outputs["combined"]
        }
        // HT_EVAL_SIGNAL=1 adds the lift's contrast transmission (UnderBlueContrastTransmission) as a grey variant.
        if ProcessInfo.processInfo.environment["HT_EVAL_SIGNAL"] == "1", let signal = restoration.contrastTransmission(source, plan: plan) {
            outputs["signal"] = signal
        }
        if let uniform = try? plan.withUniformDepth() {
            // The video entry point (correction values passed in), as video frames are rendered.
            outputs["uniform"] = (try? restoration.combined(source, plan: uniform, values: restoration.corrections(settings: settings, plan: uniform),
                                                            settings: settings, filter: engine)) ?? current
        }
    } else {
        outputs["restoration"] = source; outputs["combined"] = current; outputs["uniform"] = current
        outputs["lift"] = current
    }
    var refPx: [UInt8]?
    if let refDir, let ref = load(refDir.appendingPathComponent(name)) {
        outputs["reference"] = fit(ref, width: w, height: h); refPx = render(outputs["reference"]!, w, h)
    }
    for v in variants {
        guard let img = outputs[v] else { continue }
        let px = v == "reference" ? refPx! : render(img, w, h)
        var m = toneMetrics(px, w, h, depth: depthMap, mask: liftMask)
        if let refPx, v != "reference" { fullReference(px, refPx, w, h, into: &m) }
        let p = plan
        let fields: [String] = [name, v, "\(m.psnr)", "\(m.ssim)", "\(m.deltaE)", "\(m.farHue)", "\(m.farChroma)", "\(m.nearA)",
            "\(m.nearRG)", "\(m.contrastL)", "\(m.meanL)", "\(m.localContrast)", "\(m.farLocalContrast)", "\(m.farHueOK)", "\(m.farChromaOK)", p == nil ? "1" : "0", "\(p?.confidence ?? 0)", "\(p?.depthConfidence ?? 0)",
            "\(p?.waterFitConfidence ?? 0)", "\(p?.betaDirect.x ?? 0)", "\(p?.betaDirect.y ?? 0)", "\(p?.betaDirect.z ?? 0)",
            "\(p?.backscatterInfinity.x ?? 0)", "\(p?.backscatterInfinity.y ?? 0)", "\(p?.backscatterInfinity.z ?? 0)",
            "\(p?.transmissionFloorPixelPercentage ?? 0)", "\(p?.maximumGainPixelPercentage ?? 0)", "\(p?.channelRecoverability.x ?? 0)",
            "\(m.subjectShare)", "\(m.subjectL)", "\(m.outsideL)", "\(m.subjectChroma)", "\(m.subjectViolet)", "\(m.clipped)", "\(m.subjectClipped)", "\(m.outsideChroma)", "\(m.subjectLocalContrast)", "\(m.subjectOvershoot)"]
        csv += fields.joined(separator: ",") + "\n"
        if let sheetDir, sheetNames?.contains(name) ?? true { save(img, sheetDir.appendingPathComponent("\(name.split(separator: ".")[0])__\(v).jpg")) }
    }
    done += 1
    if done % 50 == 0 { print("\(done) images, \(Int(Date().timeIntervalSince(started)))s"); try csv.write(toFile: outCSV, atomically: true, encoding: .utf8) }
}
try csv.write(toFile: outCSV, atomically: true, encoding: .utf8)
print("done \(done) images in \(Int(Date().timeIntervalSince(started)))s")
