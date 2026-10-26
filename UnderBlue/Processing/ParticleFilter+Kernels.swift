import CoreImage

/// The Core Image kernels of the particle filter (luma, peaks, mask, fill, tiles), compiled at run time.
extension ParticleFilter {
    // Not private: ParticleFilter.init in ParticleFilter.swift compiles it.
    static let metalSource = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    constant float2 ring16[16] = {
        float2(1.0f, 0.0f), float2(0.9239f, 0.3827f), float2(0.7071f, 0.7071f), float2(0.3827f, 0.9239f),
        float2(0.0f, 1.0f), float2(-0.3827f, 0.9239f), float2(-0.7071f, 0.7071f), float2(-0.9239f, 0.3827f),
        float2(-1.0f, 0.0f), float2(-0.9239f, -0.3827f), float2(-0.7071f, -0.7071f), float2(-0.3827f, -0.9239f),
        float2(0.0f, -1.0f), float2(0.3827f, -0.9239f), float2(0.7071f, -0.7071f), float2(0.9239f, -0.3827f)
    };

    // Perceptual luma: square root of linear Rec. 709 luma, so thresholds act alike in dark and bright water.
    [[stitchable]] float4 UnderBlueSpeckLuma(coreimage::sample_t s) {
        const float l = sqrt(max(dot(s.rgb, float3(0.2126f, 0.7152f, 0.0722f)), 0.0f));
        return float4(l, l, l, 1.0f);
    }

    // r: centre minus the brightest ring point. g: contrast a spot needs here. b: blurred luma.
    // p = (ring radius, floor, spread gain, max contrast).
    [[stitchable]] float4 UnderBlueSpeckPeak(coreimage::sampler lum, float4 p, coreimage::destination dest) {
        const float2 c = dest.coord();
        const float centre = lum.sample(lum.transform(c)).r;
        float hi = -1.0e4f, lo = 1.0e4f, sum = 0.0f;
        for (int i = 0; i < 16; i++) {
            const float v = lum.sample(lum.transform(c + p.x * ring16[i])).r;
            hi = max(hi, v); lo = min(lo, v); sum += v;
        }
        // A very bright spot (contrast over the ring mean above p.w) gets an unreachable threshold.
        const float need = centre - sum / 16.0f > p.w ? 1.0e4f : max(p.y, p.z * (hi - lo));
        return float4(centre - hi, need, centre, 1.0f);
    }

    // 0: neighbour not usable (the area around the spot changed), 1: spot found there, 2: spot gone.
    // Sample with p clamped to the pixel centres of extent e = (min x, min y, max x, max y): the edge pixel
    // repeats outside, as with clampedToExtent, but Core Image needs no clamped copy of the input.
    static float4 clamped(coreimage::sampler s, float2 p, float4 e) { return s.sample(s.transform(clamp(p, e.xy + 0.5f, e.zw - 0.5f))); }

    static int look(coreimage::sampler cur, coreimage::sampler n, float2 at, float2 flow, float4 v, float4 q, float floorLevel, float4 e) {
        float diff = 0.0f;
        for (int i = 0; i < 32; i++) {
            const float2 r = (i < 16 ? q.z : 2.0f * q.z) * ring16[i % 16];
            diff += abs(clamped(cur, at + r, e).b - clamped(n, at + flow + r, e).b);
        }
        if (diff / 32.0f > q.w * v.r + 0.5f * floorLevel) { return 0; }
        const float need = max(v.r * q.y, 0.5f * v.g);
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                if (clamped(n, at + flow + float2(dx, dy), e).r >= need) { return 1; }
            }
        }
        return 2;
    }

    // 1 when any pixel of this 8x8 tile is a spot candidate (contrast above the need), else 0.
    // Tile (i, j) covers origin + 8 * (i, j) and the 7 pixels after it on each axis.
    [[stitchable]] float4 UnderBlueSpeckTiles(coreimage::sampler peak, float2 origin, coreimage::destination dest) {
        const float2 base = origin + 8.0f * floor(dest.coord());
        for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 8; x++) {
                const float4 v = peak.sample(peak.transform(base + float2(x + 0.5f, y + 0.5f)));
                if (v.r > v.g) { return float4(1.0f); }
            }
        }
        return float4(0.0f, 0.0f, 0.0f, 1.0f);
    }

    // r: how strongly this pixel belongs to a drifting spot, 0...1. A spot centre within 4 px marks it,
    // so the camera's dark sharpening halo around a speck is covered too.
    // q = (neighbour count, match ratio, context radius, context tolerance). q2.x = floor. e = extent (min x, min y, max x, max y).
    // The flow images hold one texel per 64 px block; fm = (origin of block (0, 0) in this image, block count x, y).
    // Pixels whose 9x9 window touches no candidate tile return 0 at once. Outside the extent the peak map is
    // clamped, so the window is clamped to the extent before the tiles are looked up.
    [[stitchable]] float4 UnderBlueSpeckMask(coreimage::sampler cur, coreimage::sampler n0, coreimage::sampler n1,
                                             coreimage::sampler n2, coreimage::sampler flowA, coreimage::sampler flowB,
                                             coreimage::sampler tiles, float4 q, float4 q2, float4 e, float4 fm,
                                             coreimage::destination dest) {
        const float2 c = dest.coord();
        const float2 lo = clamp(c - 4.0f, e.xy + 0.5f, e.zw - 0.5f), hi = clamp(c + 4.0f, e.xy + 0.5f, e.zw - 0.5f);
        const int2 t0 = int2(floor((lo - e.xy) / 8.0f)), t1 = int2(floor((hi - e.xy) / 8.0f));
        bool candidate = false;
        for (int ty = t0.y; ty <= t1.y; ty++) {
            for (int tx = t0.x; tx <= t1.x; tx++) { candidate = candidate || tiles.sample(tiles.transform(float2(tx, ty) + 0.5f)).r > 0.5f; }
        }
        if (!candidate) { return float4(0.0f, 0.0f, 0.0f, 1.0f); }
        const int count = int(q.x);
        float best = 0.0f;
        for (int dy = -4; dy <= 4; dy++) {
            for (int dx = -4; dx <= 4; dx++) {
                const float2 o = c + float2(dx, dy);
                const float4 v = clamped(cur, o, e);
                if (v.r <= v.g) { continue; }
                const float2 f = clamp((o - fm.xy) / 64.0f, float2(0.5f), fm.zw - 0.5f);
                const float4 fa = flowA.sample(flowA.transform(f));
                const float2 fb = flowB.sample(flowB.transform(f)).rg;
                bool gone = look(cur, n0, o, fa.rg, v, q, q2.x, e) == 2;
                if (!gone && count > 1) { gone = look(cur, n1, o, fa.ba, v, q, q2.x, e) == 2; }
                if (!gone && count > 2) { gone = look(cur, n2, o, fb, v, q, q2.x, e) == 2; }
                if (!gone) { continue; }
                const float strength = smoothstep(v.g, 2.0f * v.g, v.r);
                const float reach = clamp(4.5f - length(float2(dx, dy)), 0.0f, 1.0f);
                best = max(best, max(strength, 0.5f) * reach);
            }
        }
        return float4(best, best, best, 1.0f);
    }

    // Replaces marked pixels with the mean of the unmarked ring pixels (the local background).
    [[stitchable]] float4 UnderBlueSpeckFill(coreimage::sampler src, coreimage::sampler mask, float4 p,
                                             coreimage::destination dest) {
        const float2 c = dest.coord();
        const float4 s = src.sample(src.transform(c));
        const float m = mask.sample(mask.transform(c)).r;
        if (m <= 0.0f) { return s; }
        float3 sum = float3(0.0f);
        float n = 0.0f;
        for (int i = 0; i < 16; i++) {
            const float2 at = c + p.x * ring16[i];
            if (mask.sample(mask.transform(at)).r > 0.0f) { continue; }
            sum += src.sample(src.transform(at)).rgb;
            n += 1.0f;
        }
        if (n < 4.0f) { return s; }
        return float4(mix(s.rgb, sum / n, m), s.a);
    }
    """
}
