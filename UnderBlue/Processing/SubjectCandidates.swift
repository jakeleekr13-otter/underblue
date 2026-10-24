import CoreGraphics
import CoreImage
import Vision

/// Which subjects protect the water around them. `.auto` is the automatic mask (SubjectMask.estimate).
/// `.picked(nil)` means the user chose no subject at all.
enum SubjectChoice: Sendable, Equatable {
    /// Labs off, or below 27: no subject lift. The local veil keeps the automatic mask, as main ships.
    case off
    /// Labs on: the lift on the automatic subjects.
    case auto
    case picked(SubjectMask?)
}

/// Vision instances that are close to each other, shown to the user as one thing.
/// A school of fish is one group: Vision cannot pick one fish out of it.
struct SubjectGroup: Identifiable, Sendable {
    let id: Int
    let instances: [Int]
    /// Share of the frame, 0...1.
    let share: Float
    /// 0...1 in the photo, origin at the top left.
    let bounds: CGRect
    /// Soft mask, `SubjectCandidates.width` by `height`, row 0 on top.
    let mask: [Float]
    /// White with the mask as alpha, for the picker overlay.
    let fill: CGImage?
    /// White line along the subject's edge, thick and thin, same size as `mask`. Drawn in the picker's colours.
    var thickOutline: CGImage? = nil
    var thinOutline: CGImage? = nil
    /// Where the badge sits, 0...1: the top of the subject.
    var anchor = CGPoint(x: 0.5, y: 0.5)
}

/// An instance before grouping. Only what grouping needs.
struct SubjectInstance: Equatable, Sendable {
    let index: Int
    let bounds: CGRect
    let share: Float
}

/// The groups a user can pick from, for one photo.
///
/// Three cases are handled here so the screens stay simple:
/// - Vision finds nothing: `estimate` returns nil and the screen tells the user.
/// - Many instances (a school, a reef full of fish): close ones merge, and at most `maximumGroups` stay.
/// - Too much picked: the picks may not cover more than `maximumPickedShare` of the frame.
///   The water around a subject is what the local veil measures. With little water left, it has nothing to measure.
struct SubjectCandidates: Sendable {
    let width: Int
    let height: Int
    let groups: [SubjectGroup]
    /// True when the group limit forced groups to merge.
    let merged: Bool

    /// Instances closer than this (share of the long side, edge to edge) are one group. Provisional: S1 sets it.
    static let groupGap: CGFloat = 0.04
    static let maximumGroups = 6
    /// An instance below this share of the frame is noise.
    static let minimumInstanceShare: Float = 0.0002
    /// A group below this share of the frame is noise.
    static let minimumGroupShare: Float = 0.001
    /// The picks together may cover this much of the frame. The auto mask allows 0.25; a user pick gets more room.
    static let maximumPickedShare: Float = 0.5

    // MARK: Grouping

    /// Groups of instance indices. Close instances merge. While there are more than `limit` groups,
    /// the smallest merges into its nearest neighbour. `aspect` is width / height.
    static func grouped(_ instances: [SubjectInstance], aspect: CGFloat, gap: CGFloat = groupGap,
                        limit: Int = maximumGroups) -> (groups: [[SubjectInstance]], merged: Bool) {
        guard !instances.isEmpty else { return ([], false) }
        // Distances are measured in long sides, so a limit means the same on a wide and a tall photo.
        let sx = aspect >= 1 ? 1 : aspect, sy = aspect >= 1 ? 1 / aspect : 1
        func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let dx = max(0, max(a.minX - b.maxX, b.minX - a.maxX)) * sx
            let dy = max(0, max(a.minY - b.maxY, b.minY - a.maxY)) * sy
            return (dx * dx + dy * dy).squareRoot()
        }
        var clusters = instances.map { [$0] }
        func box(_ cluster: [SubjectInstance]) -> CGRect { cluster.dropFirst().reduce(cluster[0].bounds) { $0.union($1.bounds) } }
        func share(_ cluster: [SubjectInstance]) -> Float { cluster.reduce(0) { $0 + $1.share } }
        // Merge until no two clusters are within the gap. A merged cluster has a larger box, so repeat.
        var changed = true
        while changed {
            changed = false
            search: for i in clusters.indices {
                for j in clusters.indices where j > i && distance(box(clusters[i]), box(clusters[j])) <= gap {
                    clusters[i] += clusters[j]
                    clusters.remove(at: j)
                    changed = true
                    break search
                }
            }
        }
        var merged = false
        while clusters.count > max(1, limit) {
            let small = clusters.indices.min { share(clusters[$0]) < share(clusters[$1]) }!
            let near = clusters.indices.filter { $0 != small }
                .min { distance(box(clusters[small]), box(clusters[$0])) < distance(box(clusters[small]), box(clusters[$1])) }!
            clusters[near] += clusters[small]
            clusters.remove(at: small)
            merged = true
        }
        let ordered = clusters.sorted { share($0) > share($1) }
        return (ordered.map { $0.sorted { $0.index < $1.index } }, merged)
    }

    // MARK: Picking

    var isEmpty: Bool { groups.isEmpty }

    func group(_ id: Int) -> SubjectGroup? { groups.first { $0.id == id } }

    /// Share of the frame the picked groups cover.
    func share(of picks: Set<Int>) -> Float { groups.filter { picks.contains($0.id) }.reduce(0) { $0 + $1.share } }

    /// A pick is refused when it would push the picks past the cap. Removing a pick is always allowed.
    func accepts(_ id: Int, adding picks: Set<Int>) -> Bool {
        picks.contains(id) || share(of: picks.union([id])) <= Self.maximumPickedShare
    }

    /// The picked groups as one mask, or nil when nothing is picked.
    func mask(picking picks: Set<Int>) -> SubjectMask? {
        let chosen = groups.filter { picks.contains($0.id) && $0.mask.count == width * height }
        guard let first = chosen.first else { return nil }
        var values = first.mask
        for group in chosen.dropFirst() { for i in values.indices { values[i] = max(values[i], group.mask[i]) } }
        return SubjectMask(width: width, height: height, values: values)
    }

    /// The same groups with new masks of one size, such as the precise masks (SubjectMask.precise).
    /// Shares, boxes and the drawing follow the new masks. The drawing is made at a long side of at most
    /// `drawingSide`, because the outline's dilation is slow on a 2048 grid. Nil when the count or sizes
    /// differ, or a mask is empty.
    static let drawingSide = 1024
    func replacingMasks(_ masks: [SubjectMask]) -> SubjectCandidates? {
        guard masks.count == groups.count, let first = masks.first,
              masks.allSatisfy({ $0.width == first.width && $0.height == first.height && $0.values.count == first.width * first.height })
        else { return nil }
        let w = first.width, h = first.height
        let step = max(1, Int((Float(max(w, h)) / Float(Self.drawingSide)).rounded(.up)))
        let dw = max(2, w / step), dh = max(2, h / step)
        var built: [SubjectGroup] = []
        for (group, mask) in zip(groups, masks) {
            let share = mask.values.reduce(0, +) / Float(mask.values.count)
            var minX = w, maxX = -1, minY = h, maxY = -1
            for y in 0..<h { for x in 0..<w where mask.values[y * w + x] > 0.5 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            } }
            guard share > 0, maxX >= minX, maxY >= minY else { return nil }
            let bounds = CGRect(x: CGFloat(minX) / CGFloat(w), y: CGFloat(minY) / CGFloat(h),
                                width: CGFloat(maxX - minX + 1) / CGFloat(w), height: CGFloat(maxY - minY + 1) / CGFloat(h))
            // Box mean over step x step cells, for the drawing only.
            var small = [Float](repeating: 0, count: dw * dh)
            for y in 0..<dh { for x in 0..<dw {
                var sum: Float = 0
                for sy in 0..<step { for sx in 0..<step { sum += mask.values[min(h - 1, y * step + sy) * w + min(w - 1, x * step + sx)] } }
                small[y * dw + x] = sum / Float(step * step)
            } }
            built.append(SubjectGroup(id: group.id, instances: group.instances, share: share, bounds: bounds, mask: mask.values,
                                      fill: Self.fill(small, width: dw, height: dh),
                                      thickOutline: Self.outline(small, width: dw, height: dh, radius: 4),
                                      thinOutline: Self.outline(small, width: dw, height: dh, radius: 1),
                                      anchor: Self.top(small, width: dw, height: dh)))
        }
        return SubjectCandidates(width: w, height: h, groups: built, merged: merged)
    }

    /// The group under a point (0...1, top left origin): one whose mask covers it, else the nearest group
    /// whose box, grown by `tolerance`, holds it. A small subject then stays easy to hit.
    func group(at point: CGPoint, tolerance: CGFloat) -> Int? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let x = min(width - 1, max(0, Int(point.x * CGFloat(width)))), y = min(height - 1, max(0, Int(point.y * CGFloat(height))))
        if point.x >= 0, point.x <= 1, point.y >= 0, point.y <= 1,
           let hit = groups.first(where: { $0.mask.count == width * height && $0.mask[y * width + x] > 0.5 }) { return hit.id }
        let near = groups.filter { $0.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        return near.min { distance(point, $0.bounds) < distance(point, $1.bounds) }?.id
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = point.x - rect.midX, dy = point.y - rect.midY
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: Vision

    /// Runs Vision once and builds the groups. Nil when Vision finds no usable subject.
    static func estimate(_ image: CIImage) -> SubjectCandidates? {
        guard let input = SubjectMask.visionInput(image) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: input, options: [:])
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first,
              !observation.allInstances.isEmpty,
              let instances = measure(observation.instanceMask, allowed: observation.allInstances)
        else { return nil }
        let aspect = image.extent.width / max(1, image.extent.height)
        let found = grouped(instances, aspect: aspect)
        var built: [SubjectGroup] = []
        var size: (width: Int, height: Int)?
        for cluster in found.groups {
            let share = cluster.reduce(0) { $0 + $1.share }
            guard share >= minimumGroupShare else { continue }
            let indices = cluster.map(\.index)
            guard let buffer = try? observation.generateMask(forInstances: IndexSet(indices)),
                  let soft = SubjectMask.grid(buffer, extent: image.extent) else { continue }
            if let size, size != (soft.width, soft.height) { continue }
            size = (soft.width, soft.height)
            let bounds = cluster.dropFirst().reduce(cluster[0].bounds) { $0.union($1.bounds) }
            built.append(SubjectGroup(id: built.count, instances: indices, share: share, bounds: bounds,
                                      mask: soft.values, fill: fill(soft.values, width: soft.width, height: soft.height),
                                      thickOutline: outline(soft.values, width: soft.width, height: soft.height, radius: 4),
                                      thinOutline: outline(soft.values, width: soft.width, height: soft.height, radius: 1),
                                      anchor: top(soft.values, width: soft.width, height: soft.height)))
        }
        guard let size, !built.isEmpty else { return nil }
        return SubjectCandidates(width: size.width, height: size.height, groups: built, merged: found.merged)
    }

    /// Share and bounds of each labelled instance. Label 0 is background.
    private static func measure(_ buffer: CVPixelBuffer, allowed: IndexSet) -> [SubjectInstance]? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8,
              width > 1, height > 1, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var count = [Int](repeating: 0, count: 256)
        var minX = [Int](repeating: width, count: 256), maxX = [Int](repeating: -1, count: 256)
        var minY = [Int](repeating: height, count: 256), maxY = [Int](repeating: -1, count: 256)
        for y in 0..<height {
            let line = (base + y * row).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let label = Int(line[x])
                guard label != 0 else { continue }
                count[label] += 1
                minX[label] = min(minX[label], x); maxX[label] = max(maxX[label], x)
                minY[label] = min(minY[label], y); maxY[label] = max(maxY[label], y)
            }
        }
        let total = Float(width * height)
        return allowed.filter { $0 > 0 && $0 < 256 && count[$0] > 0 }.compactMap { label in
            let share = Float(count[label]) / total
            guard share >= minimumInstanceShare else { return nil }
            let box = CGRect(x: CGFloat(minX[label]) / CGFloat(width), y: CGFloat(minY[label]) / CGFloat(height),
                             width: CGFloat(maxX[label] - minX[label] + 1) / CGFloat(width),
                             height: CGFloat(maxY[label] - minY[label] + 1) / CGFloat(height))
            return SubjectInstance(index: label, bounds: box, share: share)
        }
    }

    /// The subject's edge as white alpha, `radius` mask pixels thick on each side. Edge = a subject pixel next to a non-subject pixel.
    static func outline(_ values: [Float], width: Int, height: Int, radius: Int) -> CGImage? {
        guard values.count == width * height else { return nil }
        func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height && values[y * width + x] > 0.5 }
        var edge = [Bool](repeating: false, count: width * height)
        for y in 0..<height { for x in 0..<width where inside(x, y) {
            edge[y * width + x] = !(inside(x - 1, y) && inside(x + 1, y) && inside(x, y - 1) && inside(x, y + 1))
        } }
        // Grow the edge: a max filter along rows, then along columns.
        func grow(_ input: [Bool], horizontal: Bool) -> [Bool] {
            var output = input
            for y in 0..<height { for x in 0..<width where input[y * width + x] {
                for d in -radius...radius {
                    let nx = horizontal ? x + d : x, ny = horizontal ? y : y + d
                    if nx >= 0, ny >= 0, nx < width, ny < height { output[ny * width + nx] = true }
                }
            } }
            return output
        }
        let thick = grow(grow(edge, horizontal: true), horizontal: false)
        return fill(thick.map { $0 ? 1 : 0 }, width: width, height: height)
    }

    /// The top of the subject: the first row with a subject pixel, at the middle of that row's subject pixels.
    static func top(_ values: [Float], width: Int, height: Int) -> CGPoint {
        for y in 0..<height {
            let xs = (0..<width).filter { values[y * width + $0] > 0.5 }
            if let first = xs.first, let last = xs.last {
                return CGPoint(x: CGFloat(first + last) / 2 / CGFloat(width), y: CGFloat(y) / CGFloat(height))
            }
        }
        return CGPoint(x: 0.5, y: 0.5)
    }

    static func fill(_ values: [Float], width: Int, height: Int) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in values.indices {
            let alpha = UInt8((values[i] * 255).rounded())
            bytes[i * 4] = alpha; bytes[i * 4 + 1] = alpha; bytes[i * 4 + 2] = alpha; bytes[i * 4 + 3] = alpha
        }
        return bytes.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }
}
