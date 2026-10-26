import CoreImage
import Metal

extension ParticleFilter {
    /// Camera motion on the GPU (Metal compute), block matching on 1/4-scale luma and its 1/8-scale half.
    /// Content at p in frame a sits at p + v in frame b, in full-resolution pixels, y down.
    /// Global shift: ±80 px search on 1/8 scale with each side's mean removed (frame width up to 8384 px), then ±2 px and a parabola fit
    /// on 1/4 scale. Per 64 px block: ±40 px around the global shift on 1/8 scale, then ±1 px and a parabola fit
    /// on 1/4 scale. A block keeps the global shift unless its best match is clearly better (flat water has
    /// no signal). A 3x3 median on the CPU then removes single-block outliers.
    final class MotionEstimator {
        struct Probe { let quarter: any MTLTexture, coarse: any MTLTexture }
        let device: any MTLDevice
        let queue: any MTLCommandQueue
        private let halve, coarseBand, coarseFinal, globalFine, shift, blocks: any MTLComputePipelineState
        private let coarseCost, fineCost, global, partial, aPartial: any MTLBuffer
        /// One result buffer per command buffer in flight, used in turn.
        private var results: [any MTLBuffer] = []
        private var result = 0
        /// Two probe slots, used in turn: the frame being measured and the one before it.
        private var slots: [Probe] = []
        private var slot = 0

        init?() {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            let options = MTLCompileOptions()
            options.mathMode = .safe
            guard let library = try? device.makeLibrary(source: Self.source, options: options),
                  let pipes = try? ["halve", "coarseBand", "coarseCost", "globalFine", "shift", "blocks"].map({ name -> any MTLComputePipelineState in
                      guard let f = library.makeFunction(name: name) else { throw CocoaError(.featureUnsupported) }
                      return try device.makeComputePipelineState(function: f) }),
                  let cc = device.makeBuffer(length: 441 * 4), let fc = device.makeBuffer(length: 25 * 4),
                  let gs = device.makeBuffer(length: 8), let pp = device.makeBuffer(length: 2 * 441 * 8 * 4),
                  let ap = device.makeBuffer(length: 8 * 4) else { return nil }
            self.device = device; self.queue = queue
            halve = pipes[0]; coarseBand = pipes[1]; coarseFinal = pipes[2]; globalFine = pipes[3]; shift = pipes[4]; blocks = pipes[5]
            coarseCost = cc; fineCost = fc; global = gs; partial = pp; aPartial = ap
        }

        /// Encodes the 1/4-scale render of `luma` (origin 0, full size w x h) and its 1/8-scale half into the next slot.
        /// The probe stays valid until the call after next.
        func probe(_ luma: CIImage, width w: Int, height h: Int, context: CIContext, into cb: any MTLCommandBuffer) -> Probe? {
            let qw = w / 4, qh = h / 4
            func texture(_ tw: Int, _ th: Int) -> (any MTLTexture)? {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: tw, height: th, mipmapped: false)
                d.usage = [.shaderRead, .shaderWrite, .renderTarget]; d.storageMode = .private
                return device.makeTexture(descriptor: d)
            }
            if slots.first?.quarter.width != qw || slots.first?.quarter.height != qh {
                slots = (0..<2).compactMap { _ in texture(qw, qh).flatMap { q in texture(qw / 2, qh / 2).map { Probe(quarter: q, coarse: $0) } } }
            }
            guard slots.count == 2 else { return nil }
            let (quarter, coarse) = (slots[slot].quarter, slots[slot].coarse)
            slot = 1 - slot
            let small = luma.transformed(by: CGAffineTransform(scaleX: CGFloat(qw) / CGFloat(w), y: CGFloat(qh) / CGFloat(h)),
                                         highQualityDownsample: true)
            let destination = CIRenderDestination(mtlTexture: quarter, commandBuffer: cb)
            destination.colorSpace = nil
            // Row 0 is the top of the image, as in a CVPixelBuffer and in the CPU version this replaced.
            destination.isFlipped = true
            guard (try? context.startTask(toRender: small, from: CGRect(x: 0, y: 0, width: qw, height: qh), to: destination, at: .zero)) != nil,
                  let e = cb.makeComputeCommandEncoder() else { return nil }
            e.setComputePipelineState(halve); e.setTexture(quarter, index: 0); e.setTexture(coarse, index: 1)
            e.dispatchThreads(MTLSize(width: qw / 2, height: qh / 2, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            e.endEncoding()
            return Probe(quarter: quarter, coarse: coarse)
        }

        /// Encodes the block search from `a` to `b`. Returns the buffer to read with `field` after `cb` completes.
        /// It stays valid until 3 more searches are encoded.
        func encodeField(from a: Probe, to b: Probe, into cb: any MTLCommandBuffer) -> (any MTLBuffer)? {
            let count = (a.quarter.width / 16) * (a.quarter.height / 16)
            if (results.first?.length ?? 0) < count * 8 {
                results = (0..<4).compactMap { _ in device.makeBuffer(length: count * 8, options: .storageModeShared) }
            }
            guard results.count == 4, a.coarse.width - 24 <= 1024, let e = cb.makeComputeCommandEncoder() else { return nil }
            let vectors = results[result]
            result = (result + 1) % 4
            let group = MTLSize(width: 256, height: 1, depth: 1)
            e.setTextures([a.coarse, b.coarse], range: 0..<2)
            e.setBuffer(coarseCost, offset: 0, index: 0); e.setBuffer(partial, offset: 0, index: 4); e.setBuffer(aPartial, offset: 0, index: 5)
            e.setComputePipelineState(coarseBand)
            for pass in [Int32(0), 1] {
                var p = pass
                e.setBytes(&p, length: 4, index: 6)
                e.dispatchThreadgroups(MTLSize(width: 21, height: 8, depth: 1), threadsPerThreadgroup: group)
            }
            e.setComputePipelineState(coarseFinal)
            e.dispatchThreads(MTLSize(width: 441, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
            e.setComputePipelineState(globalFine); e.setTextures([a.quarter, b.quarter], range: 0..<2); e.setBuffer(fineCost, offset: 0, index: 1)
            e.dispatchThreadgroups(MTLSize(width: 25, height: 1, depth: 1), threadsPerThreadgroup: group)
            e.setComputePipelineState(shift); e.setBuffer(global, offset: 0, index: 3)
            e.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e.setComputePipelineState(blocks); e.setTextures([a.quarter, b.quarter, a.coarse, b.coarse], range: 0..<4)
            e.setBuffer(vectors, offset: 0, index: 2)
            e.dispatchThreadgroups(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 128, height: 1, depth: 1))
            e.endEncoding()
            return vectors
        }

        /// A search result for frames of full size w x h, after its command buffer completed, with the 3x3 median applied.
        func field(_ vectors: any MTLBuffer, width w: Int, height h: Int) -> MotionField {
            let gw = w / 64, gh = h / 64
            let raw = Array(UnsafeBufferPointer(start: vectors.contents().assumingMemoryBound(to: SIMD2<Float>.self), count: gw * gh))
            var out = raw
            for by in 0..<gh { for bx in 0..<gw {
                var xs: [Float] = [], ys: [Float] = []
                for y in max(0, by - 1)...min(gh - 1, by + 1) { for x in max(0, bx - 1)...min(gw - 1, bx + 1) {
                    xs.append(raw[y * gw + x].x); ys.append(raw[y * gw + x].y) } }
                xs.sort(); ys.sort()
                out[by * gw + bx] = SIMD2(xs[xs.count / 2], ys[ys.count / 2])
            }}
            return MotionField(gw: gw, gh: gh, vectors: out)
        }

        static let source = """
        #include <metal_stdlib>
        using namespace metal;

        // 1/8 scale: mean of each 2x2 block of the 1/4-scale luma.
        kernel void halve(texture2d<float, access::read> q [[texture(0)]], texture2d<float, access::write> c [[texture(1)]],
                          uint2 p [[thread_position_in_grid]]) {
            if (p.x >= c.get_width() || p.y >= c.get_height()) { return; }
            const uint2 s = 2 * p;
            c.write(float4((q.read(s).r + q.read(s + uint2(1, 0)).r + q.read(s + uint2(0, 1)).r + q.read(s + uint2(1, 1)).r) / 4.0f), p);
        }

        // Sum over one threadgroup of 256 threads.
        static float groupSum(float v, threadgroup float *s, uint t) {
            v = simd_sum(v);
            if (t % 32 == 0) { s[t / 32] = v; }
            threadgroup_barrier(mem_flags::mem_threadgroup);
            float total = 0.0f;
            for (uint i = 0; i < 8; i++) { total += s[i]; }
            threadgroup_barrier(mem_flags::mem_threadgroup);
            return total;
        }

        // Mean absolute difference of a(p) and b(p + d) over the inner area, with each side's mean removed.
        // Threads split each row; the rows run in order.
        static float centred(texture2d<float, access::read> a, texture2d<float, access::read> b, int2 d, int margin,
                             threadgroup float *s, uint t) {
            const int x1 = int(a.get_width()) - margin, y1 = int(a.get_height()) - margin;
            const float n = float((x1 - margin) * (y1 - margin));
            float ma = 0.0f, mb = 0.0f;
            for (int y = margin; y < y1; y++) {
                for (int x = margin + int(t); x < x1; x += 256) { ma += a.read(uint2(x, y)).r; mb += b.read(uint2(x + d.x, y + d.y)).r; }
            }
            const float off = (groupSum(mb, s, t) - groupSum(ma, s, t)) / n;
            float sum = 0.0f;
            for (int y = margin; y < y1; y++) {
                for (int x = margin + int(t); x < x1; x += 256) { sum += abs(a.read(uint2(x, y)).r + off - b.read(uint2(x + d.x, y + d.y)).r); }
            }
            return groupSum(sum, s, t) / n;
        }

        static int argmin(device const float *c, int n) {
            int k = 0;
            for (int i = 1; i < n; i++) { if (c[i] < c[k]) { k = i; } }
            return k;
        }

        // Coarse global search, -10...10 px on 1/8 scale, 441 offsets in order dy, then dx.
        // One threadgroup per (dy, band of rows). Each row of a and of b is loaded once into threadgroup memory
        // and serves all 21 dx offsets: thread t < 252 owns offset dx = t % 21 - 10 and one of 12 row chunks.
        // pass 0: partial sums of b(p + d), and of a(p) (same for every d). pass 1: partial sums of
        // |a(p) + off - b(p + d)|, where off = mean b(p + d) - mean a(p) from the pass 0 sums.
        // part layout: [pass][offset][band]. aPart: [band]. Inner width is at most 1024 (checked on the CPU).
        constant int R = 10, M = 12, BANDS = 8, CHUNKS = 12;
        kernel void coarseBand(texture2d<float, access::read> a [[texture(0)]], texture2d<float, access::read> b [[texture(1)]],
                               device float *part [[buffer(4)]], device float *aPart [[buffer(5)]], constant int &pass [[buffer(6)]],
                               uint2 g [[threadgroup_position_in_grid]], uint t [[thread_index_in_threadgroup]]) {
            threadgroup float ta[1024], tb[1024 + 2 * R], red[256], redA[CHUNKS];
            const int iw = int(a.get_width()) - 2 * M, rows = int(a.get_height()) - 2 * M;
            const int dy = int(g.x) - R, band = int(g.y), r0 = M + rows * band / BANDS, r1 = M + rows * (band + 1) / BANDS;
            const int dxi = int(t) % 21, chunk = int(t) / 21, cw = (iw + CHUNKS - 1) / CHUNKS;
            const int c0 = min(iw, chunk * cw), c1 = min(iw, c0 + cw), offset = (dy + R) * 21 + dxi;
            float off = 0.0f;
            if (pass == 1 && t < 252) {
                float sa = 0.0f, sb = 0.0f;
                for (int k = 0; k < BANDS; k++) { sa += aPart[k]; sb += part[offset * BANDS + k]; }
                off = (sb - sa) / float(iw * rows);
            }
            float acc = 0.0f, accA = 0.0f;
            for (int y = r0; y < r1; y++) {
                for (int i = int(t); i < iw; i += 256) { ta[i] = a.read(uint2(M + i, y)).r; }
                for (int i = int(t); i < iw + 2 * R; i += 256) { tb[i] = b.read(uint2(M - R + i, y + dy)).r; }
                threadgroup_barrier(mem_flags::mem_threadgroup);
                if (t < 252) {
                    if (pass == 0) {
                        for (int i = c0; i < c1; i++) { acc += tb[i + dxi]; }
                        if (dxi == 0) { for (int i = c0; i < c1; i++) { accA += ta[i]; } }
                    } else {
                        for (int i = c0; i < c1; i++) { acc += abs(ta[i] + off - tb[i + dxi]); }
                    }
                }
                threadgroup_barrier(mem_flags::mem_threadgroup);
            }
            red[t] = acc;
            if (dxi == 0 && t < 252) { redA[chunk] = accA; }
            threadgroup_barrier(mem_flags::mem_threadgroup);
            if (t < 21) {
                float sum = 0.0f;
                for (int c = 0; c < CHUNKS; c++) { sum += red[c * 21 + int(t)]; }
                part[(pass * 441 + (dy + R) * 21 + int(t)) * BANDS + band] = sum;
            }
            if (pass == 0 && t == 0 && g.x == 0) {
                float sum = 0.0f;
                for (int c = 0; c < CHUNKS; c++) { sum += redA[c]; }
                aPart[band] = sum;
            }
        }

        // Coarse cost per offset from the pass 1 partial sums. One thread per offset.
        kernel void coarseCost(texture2d<float, access::read> a [[texture(0)]], device const float *part [[buffer(4)]],
                               device float *cost [[buffer(0)]], uint g [[thread_position_in_grid]]) {
            if (g >= 441) { return; }
            float sum = 0.0f;
            for (int k = 0; k < BANDS; k++) { sum += part[(441 + int(g)) * BANDS + k]; }
            cost[g] = sum / float((int(a.get_width()) - 2 * M) * (int(a.get_height()) - 2 * M));
        }

        // One threadgroup per offset, ±2 px on 1/4 scale around the best coarse offset.
        kernel void globalFine(texture2d<float, access::read> a [[texture(0)]], texture2d<float, access::read> b [[texture(1)]],
                               device const float *coarse [[buffer(0)]], device float *cost [[buffer(1)]],
                               uint g [[threadgroup_position_in_grid]], uint t [[thread_index_in_threadgroup]]) {
            threadgroup float s[8];
            const int k = argmin(coarse, 441);
            const int2 d = 2 * int2(k % 21 - 10, k / 21 - 10) + int2(int(g % 5) - 2, int(g / 5) - 2);
            const float v = centred(a, b, d, 24, s, t);
            if (t == 0) { cost[g] = v; }
        }

        static float parabola(float l, float m, float r) {
            const float d = l - 2.0f * m + r;
            return d > 0.0f && isfinite(d) ? max(-0.5f, min(0.5f, (l - r) / (2.0f * d))) : 0.0f;
        }

        // Mean absolute difference of a size x size block at (x0, y0) and the block moved by d. FLT_MAX off the edge.
        static float blockCost(texture2d<float, access::read> a, texture2d<float, access::read> b, int x0, int y0, int size, int2 d) {
            if (x0 + d.x < 0 || y0 + d.y < 0 || x0 + size + d.x > int(a.get_width()) || y0 + size + d.y > int(a.get_height())) { return FLT_MAX; }
            float sum = 0.0f;
            for (int y = y0; y < y0 + size; y++) {
                for (int x = x0; x < x0 + size; x++) { sum += abs(a.read(uint2(x, y)).r - b.read(uint2(x + d.x, y + d.y)).r); }
            }
            return sum / float(size * size);
        }

        // The global shift from both searches, in full-resolution pixels. One thread.
        kernel void shift(device const float *coarse [[buffer(0)]], device const float *fine [[buffer(1)]],
                          device float2 *global [[buffer(3)]]) {
            const int k = argmin(coarse, 441), f = argmin(fine, 25), i = f % 5, j = f / 5;
            const float sx = (i > 0 && i < 4) ? parabola(fine[f - 1], fine[f], fine[f + 1]) : 0.0f;
            const float sy = (j > 0 && j < 4) ? parabola(fine[f - 5], fine[f], fine[f + 5]) : 0.0f;
            global[0] = float2(float(2 * (k % 21 - 10) + i - 2) + sx, float(2 * (k / 21 - 10) + j - 2) + sy) * 4.0f;
        }

        // One threadgroup (128 threads) per 64 px block, 16 px on 1/4 scale. out: vectors in full-resolution pixels.
        // Offsets are scanned in the order dy, then dx, and the first lowest cost wins.
        kernel void blocks(texture2d<float, access::read> a4 [[texture(0)]], texture2d<float, access::read> b4 [[texture(1)]],
                           texture2d<float, access::read> a8 [[texture(2)]], texture2d<float, access::read> b8 [[texture(3)]],
                           device float2 *out [[buffer(2)]], device const float2 *globalShift [[buffer(3)]],
                           uint g [[threadgroup_position_in_grid]], uint t [[thread_index_in_threadgroup]]) {
            threadgroup float coarse[121], fine[10];
            const int gw = int(a4.get_width()) / 16, bx = int(g) % gw, by = int(g) / gw;
            const float2 global = globalShift[0];
            const int2 g8 = int2(round(global / 8.0f));
            if (t < 121) { coarse[t] = blockCost(a8, b8, bx * 8, by * 8, 8, g8 + int2(int(t % 11) - 5, int(t / 11) - 5)); }
            threadgroup_barrier(mem_flags::mem_threadgroup);
            int k = 0;
            for (int n = 1; n < 121; n++) { if (coarse[n] < coarse[k]) { k = n; } }
            const int2 at = g8 + int2(k % 11 - 5, k / 11 - 5);
            if (t < 10) {
                const int2 d = t < 9 ? 2 * at + int2(int(t % 3) - 1, int(t / 3) - 1) : int2(round(global / 4.0f));
                fine[t] = blockCost(a4, b4, bx * 16, by * 16, 16, d);
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
            if (t != 0) { return; }
            int m = 0;
            for (int n = 1; n < 9; n++) { if (fine[n] < fine[m]) { m = n; } }
            const float atGlobal = fine[9];
            if (!(fine[m] < 0.8f * atGlobal && atGlobal - fine[m] > 0.002f)) { out[g] = global; return; }
            const float vx = m % 3 == 1 ? parabola(fine[3], fine[4], fine[5]) : 0.0f;
            const float vy = m / 3 == 1 ? parabola(fine[1], fine[4], fine[7]) : 0.0f;
            out[g] = float2(float(2 * at.x + m % 3 - 1) + vx, float(2 * at.y + m / 3 - 1) + vy) * 4.0f;
        }
        """
    }

    /// Motion per 64 px block, full-resolution pixels, y down.
    struct MotionField: Sendable {
        let gw: Int, gh: Int
        var vectors: [SIMD2<Float>]
        static let block: Float = 64

        /// Bilinear between block centres.
        func at(_ x: Float, _ y: Float) -> SIMD2<Float> {
            let fx = min(Float(gw - 1), max(0, x / Self.block - 0.5)), fy = min(Float(gh - 1), max(0, y / Self.block - 0.5))
            let x0 = Int(fx), y0 = Int(fy), x1 = min(gw - 1, x0 + 1), y1 = min(gh - 1, y0 + 1)
            let tx = fx - Float(x0), ty = fy - Float(y0)
            let top = vectors[y0 * gw + x0] * (1 - tx) + vectors[y0 * gw + x1] * tx
            let bottom = vectors[y1 * gw + x0] * (1 - tx) + vectors[y1 * gw + x1] * tx
            return top * (1 - ty) + bottom * ty
        }

        static func + (a: MotionField, b: MotionField) -> MotionField {
            MotionField(gw: a.gw, gh: a.gh, vectors: zip(a.vectors, b.vectors).map { $0 + $1 })
        }
        static prefix func - (a: MotionField) -> MotionField { MotionField(gw: a.gw, gh: a.gh, vectors: a.vectors.map { -$0 }) }
    }
}
