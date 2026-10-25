// R2/R3 probe: precise segmentation seeded by a press point against the app's box seed.
// Usage: probe <image> <outdir> <name> <cropX,cropY,cropW,cropH | -> <label:x,y> ...   (x,y top-left normalized)
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

let ctx = CIContext(options: [.workingColorSpace: NSNull()])
let side: CGFloat = 2048

struct Mask { let w: Int; let h: Int; let v: [Float] }

func load(_ path: String) -> CIImage {
    let img = CIImage(contentsOf: URL(fileURLWithPath: path), options: [.applyOrientationProperty: true])!
    return img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
}

func grid(_ obs: PixelBufferObservation, extent: CGRect) -> Mask {
    let scale = min(1, side / max(extent.width, extent.height))
    let w = Int((extent.width * scale).rounded(.down)), h = Int((extent.height * scale).rounded(.down))
    var v = [Float](repeating: 0, count: w * h)
    obs.pixelBuffer.withUnsafeBuffer { buf in
        let full = CIImage(cvPixelBuffer: buf)
        let f = CIFilter.lanczosScaleTransform()
        f.inputImage = full
        f.scale = Float(CGFloat(w) / full.extent.width)
        f.aspectRatio = Float((CGFloat(h) / full.extent.height) / (CGFloat(w) / full.extent.width))
        v.withUnsafeMutableBytes { raw in
            ctx.render(f.outputImage!, toBitmap: raw.baseAddress!, rowBytes: w * 4,
                       bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .Rf, colorSpace: nil)
        }
    }
    for i in v.indices { v[i] = v[i].isFinite ? min(1, max(0, v[i])) : 0 }
    return Mask(w: w, h: h, v: v)
}

func maskImage(_ m: Mask, extent: CGRect) -> CIImage {
    let data = m.v.withUnsafeBytes { Data($0) }
    let img = CIImage(bitmapData: data, bytesPerRow: m.w * 4, size: CGSize(width: m.w, height: m.h), format: .Rf, colorSpace: nil)
    // Row 0 is the top row (render(toBitmap:) wrote it so); CIImage(bitmapData:) also reads row 0 as top.
    return img.transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(m.w), y: extent.height / CGFloat(m.h)))
}

func share(_ m: Mask) -> Float { m.v.reduce(0, +) / Float(m.v.count) }
func iou(_ a: Mask, _ b: Mask) -> Float {
    var i: Float = 0, u: Float = 0
    for k in a.v.indices { let x = a.v[k] > 0.5, y = b.v[k] > 0.5; if x && y { i += 1 }; if x || y { u += 1 } }
    return u > 0 ? i / u : 1
}

func overlay(_ photo: CIImage, _ m: Mask, crop: CGRect?, out: String) {
    let ext = photo.extent
    let mask = maskImage(m, extent: ext).applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0.6, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0.6, y: 0, z: 0, w: 0),
        "inputBVector": CIVector(x: 0.6, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0.6, y: 0, z: 0, w: 0)])
    let mint = CIImage(color: CIColor(red: 1, green: 0, blue: 1)).cropped(to: ext)
    let blend = CIFilter.blendWithMask()
    blend.inputImage = mint; blend.backgroundImage = photo; blend.maskImage = mask
    var img = (out.hasSuffix("_m.jpg") ? maskImage(m, extent: ext) : blend.outputImage!).cropped(to: ext)
    if let c = crop {
        // crop is top-left normalized; CI origin is bottom-left.
        let r = CGRect(x: c.minX * ext.width, y: (1 - c.maxY) * ext.height, width: c.width * ext.width, height: c.height * ext.height)
        img = img.cropped(to: r)
    } else {
        let s = 1600 / max(ext.width, ext.height)
        img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
    }
    img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
    try! ctx.writeJPEGRepresentation(of: img, to: URL(fileURLWithPath: out), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
}

func run(_ request: GenerateIterativeSegmentationRequest, on img: CIImage) async -> (PixelBufferObservation?, Double) {
    request.qualityLevel = .accurate
    let t = Date()
    let r = try? await request.perform(on: img)
    return (r ?? nil, Date().timeIntervalSince(t) * 1000)
}

let a = CommandLine.arguments
let photo = load(a[1]), outDir = a[2], name = a[3]
let cropArg = a[4]
let crop: CGRect? = cropArg == "-" ? nil : { let p = cropArg.split(separator: ",").map { CGFloat(Double($0)!) }; return CGRect(x: p[0], y: p[1], width: p[2], height: p[3]) }()
// label:x,y[+x,y...][-x,y...]  + adds an included point, - an excluded point.
struct Seed { let label: String; let p: CGPoint; let extra: [(Bool, CGPoint)] }
func pt(_ s: Substring) -> CGPoint { let xy = s.split(separator: ",").map { CGFloat(Double($0)!) }; return CGPoint(x: xy[0], y: xy[1]) }
let points: [Seed] = a.dropFirst(5).map { s in
    let parts = s.split(separator: ":"); var rest = Substring(parts[1]); var extra: [(Bool, CGPoint)] = []
    var cuts: [(Bool, Substring)] = []; var cur = ""; var sign = true; var first: Substring = ""
    for ch in rest { if ch == "+" || ch == "-" { if first.isEmpty { first = Substring(cur) } else { cuts.append((sign, Substring(cur))) }; cur = ""; sign = ch == "+" } else { cur.append(ch) } }
    if first.isEmpty { first = Substring(cur) } else { cuts.append((sign, Substring(cur))) }
    rest = ""; extra = cuts.map { ($0.0, pt($0.1)) }
    return Seed(label: String(parts[0]), p: pt(first), extra: extra)
}

// Warm the model once so timings exclude the load.
_ = await run(GenerateIterativeSegmentationRequest(seedBox: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)), on: photo)

// The app's box seed: the box around the coarse foreground mask above 0.5.
var boxMask: Mask?
if let inst = try? await GenerateForegroundInstanceMaskRequest().perform(on: photo), !inst.allInstances.isEmpty,
   let coarse = try? inst.generateMask(for: inst.allInstances) {
    CVPixelBufferLockBaseAddress(coarse, .readOnly)
    let w = CVPixelBufferGetWidth(coarse), h = CVPixelBufferGetHeight(coarse), row = CVPixelBufferGetBytesPerRow(coarse)
    let base = CVPixelBufferGetBaseAddress(coarse)!
    var minX = w, maxX = -1, minY = h, maxY = -1
    for y in 0..<h { let line = (base + y * row).assumingMemoryBound(to: Float.self)
        for x in 0..<w where line[x] > 0.5 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
    CVPixelBufferUnlockBaseAddress(coarse, .readOnly)
    if maxX >= minX {
        let box = NormalizedRect(x: CGFloat(minX) / CGFloat(w), y: 1 - CGFloat(maxY + 1) / CGFloat(h),
                                 width: CGFloat(maxX - minX + 1) / CGFloat(w), height: CGFloat(maxY - minY + 1) / CGFloat(h))
        let (obs, ms) = await run(GenerateIterativeSegmentationRequest(seedBox: box), on: photo)
        if let obs {
            let m = grid(obs, extent: photo.extent); boxMask = m
            print(String(format: "%@ box instances=%d share=%.4f ms=%.0f", name, inst.allInstances.count, share(m), ms))
            overlay(photo, m, crop: nil, out: "\(outDir)/\(name)_box.jpg")
            if crop != nil { overlay(photo, m, crop: crop, out: "\(outDir)/\(name)_box_crop.jpg") ; overlay(photo, m, crop: crop, out: "\(outDir)/\(name)_box_crop_m.jpg") }
        }
    }
} else { print("\(name) box: no Vision instance") }

var pointMasks: [(String, Mask)] = []
for sd in points {
    let label = sd.label, p = sd.p
    let req = GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: p.x, y: 1 - p.y))
    for (inc, q) in sd.extra {
        let n = NormalizedPoint(x: q.x, y: 1 - q.y)
        if inc { try! req.addIncludedPoint(n) } else { try! req.addExcludedPoint(n) }
    }
    let (obs, ms) = await run(req, on: photo)
    guard let obs else { print("\(name) \(label): no result"); continue }
    let m = grid(obs, extent: photo.extent); pointMasks.append((label, m))
    let vsBox = boxMask.map { String(format: "%.3f", iou(m, $0)) } ?? "n/a"
    print(String(format: "%@ point %@ (%.3f,%.3f) share=%.4f iouBox=%@ ms=%.0f", name, label, p.x, p.y, share(m), vsBox, ms))
    overlay(photo, m, crop: nil, out: "\(outDir)/\(name)_\(label).jpg")
    if crop != nil { overlay(photo, m, crop: crop, out: "\(outDir)/\(name)_\(label)_crop.jpg") ; overlay(photo, m, crop: crop, out: "\(outDir)/\(name)_\(label)_crop_m.jpg") }
}
// Pairwise IoU between point masks (R3: does the press location change the mask?)
for i in pointMasks.indices { for j in pointMasks.indices where j > i {
    print(String(format: "%@ iou %@-%@ = %.3f", name, pointMasks[i].0, pointMasks[j].0, iou(pointMasks[i].1, pointMasks[j].1)))
} }
