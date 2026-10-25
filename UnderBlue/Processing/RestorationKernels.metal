// The restoration kernels. RestorationEngine loads them; RestorationMath mirrors them.
#include <CoreImage/CoreImage.h>
using namespace metal;

[[stitchable]] float4 UnderBlueRestoration(coreimage::sample_t source,
                                            coreimage::sample_t depthSample,
                                            coreimage::sample_t broadSample,
                                            float4 backscatterInfinity,
                                            float4 betaDirect,
                                            float4 betaBackscatter,
                                            float4 limits,
                                            float4 maximumGain,
                                            float4 recoverability,
                                            float4 veil) {
    const float z = clamp(depthSample.r, 0.0f, 1.0f);
    const float3 directTransmission = exp(-max(betaDirect.rgb, float3(0.0f)) * z);
    const float3 backscatterTransmission = exp(-max(betaBackscatter.rgb, float3(0.0f)) * z);
    const float3 safeTransmission = max(directTransmission, float3(max(0.01f, limits.x)));
    const float3 gain = min(1.0f / safeTransmission, max(maximumGain.rgb, float3(1.0f)));
    float3 backscatter = max(backscatterInfinity.rgb, float3(0.0f)) * (1.0f - backscatterTransmission);
    // Local veil (veil = level, lowest scale, highest scale): the veil follows the broad light
    // around the pixel (broadSample) in size, as a share of the scene's water level, and in colour.
    // RestorationMath.localVeil mirrors it.
    if (veil.x > 1e-4f) {
        const float3 luma = float3(0.2126f, 0.7152f, 0.0722f);
        const float3 broad = max(broadSample.rgb, float3(0.0f));
        const float broadLum = dot(broad, luma);
        backscatter *= clamp(broadLum / veil.x, veil.y, veil.z);
        if (broadLum > 1e-4f) { backscatter = broad * (dot(backscatter, luma) / broadLum); }
    }
    float3 restored = max(source.rgb - backscatter, float3(0.0f)) * gain;
    // Video (veil.w = 1): the highlight protection reads the middle channel, not the brightest. Blue water
    // has one bright channel at all times, so the peak took it for a highlight and sent 44% of the restored
    // pixel back to the source. That weight fell away over 50 rows and drew a hard layer edge (22 Oct 2026).
    // A white highlight has two bright channels. Photos keep the peak: there it also hides a dark blob that
    // the local veil draws in bright open blue water (r13). RestorationMath mirrors it.
    const float peak = veil.w > 0.5f ? max(min(source.r, source.g), min(max(source.r, source.g), source.b))
                                     : max(source.r, max(source.g, source.b));
    const float highlight = smoothstep(limits.y, max(limits.y + 0.001f, limits.z), peak) * 0.8f;
    restored = mix(restored, source.rgb, highlight);
    restored = clamp(restored, float3(0.0f), float3(max(0.5f, limits.w)));
    restored = source.rgb + (restored - source.rgb) * clamp(recoverability.rgb, 0.0f, 1.0f);
    // Where veil removal leaves little light (channel sum), keep the source hue at the
    // restored level, so far water does not turn red-brown or violet.
    // RestorationMath.keepHueWhereDark mirrors it.
    const float3 lit = max(source.rgb, float3(0.0f));
    const float before = lit.r + lit.g + lit.b;
    if (before > 1e-5f) {
        const float3 now = max(restored, float3(0.0f));
        const float kept = (now.r + now.g + now.b) / before;
        restored = mix(restored, lit * kept, 1.0f - smoothstep(0.3f, 0.6f, kept));
    }
    // A blue source pixel that turned green only because the veil took nearly all its blue
    // (green/blue grew 4-8 times) keeps its source hue at the restored level.
    // RestorationMath.keepBlueFamily mirrors it.
    if (before > 1e-5f) {
        const float3 now = max(restored, float3(0.0f));
        const float blueness = smoothstep(1.0f, 1.1f, lit.b / max(max(lit.r, lit.g), 1e-4f));
        const float greenBlue = now.g / max(now.b, 1e-4f);
        const float growth = greenBlue / max(lit.g / max(lit.b, 1e-4f), 1e-4f);
        const float amount = blueness * smoothstep(1.1f, 1.4f, greenBlue) * smoothstep(4.0f, 8.0f, growth);
        restored = mix(restored, lit * ((now.r + now.g + now.b) / before), amount);
    }
    // A pale source pixel whose red already reaches green lost no red, so restoration may not
    // raise its red/green. RestorationMath.keepWarmRatio mirrors it.
    if (before > 1e-5f) {
        const float sourceTop = max(lit.r, max(lit.g, lit.b));
        const float sourceChroma = sourceTop > 1e-4f ? (sourceTop - min(lit.r, min(lit.g, lit.b))) / sourceTop : 0.0f;
        const float ratio = lit.r / max(lit.g, 1e-4f);
        const float uncast = smoothstep(0.92f, 1.0f, ratio) * (1.0f - smoothstep(0.15f, 0.3f, sourceChroma));
        restored.r = mix(restored.r, min(restored.r, max(restored.g, 0.0f) * ratio), uncast);
    }
    if (!all(isfinite(restored))) { restored = max(source.rgb, float3(0.0f)); }
    return float4(restored, source.a);
}

// Fine detail on the restored image: the source's detail (source - low) times the pixel's own
// restoration ratio (restoredLow / low), not 1 / transmission. See restore(_:plan:).
[[stitchable]] float4 UnderBlueRestoredDetail(coreimage::sample_t source, coreimage::sample_t low,
                                              coreimage::sample_t restoredLow, float4 maximumGain) {
    const float3 ratio = clamp(max(restoredLow.rgb, float3(0.0f)) / max(low.rgb, float3(1e-4f)),
                               float3(0.0f), max(maximumGain.rgb, float3(1.0f)));
    const float3 out = max(restoredLow.rgb + (source.rgb - low.rgb) * ratio, float3(0.0f));
    return all(isfinite(out)) ? float4(out, source.a) : restoredLow;
}

// The current and the restored result mixed per pixel: weights.x (the physical weight) times a
// ramp over depth 0 to weights.y. See RestorationEngine.combined.
[[stitchable]] float4 UnderBlueDepthBlend(coreimage::sample_t current, coreimage::sample_t depthAware,
                                          coreimage::sample_t depthSample, float4 weights) {
    const float w = weights.x * smoothstep(0.0f, max(1e-4f, weights.y), clamp(depthSample.r, 0.0f, 1.0f));
    return mix(current, depthAware, clamp(w, 0.0f, 1.0f));
}

// The local veil's broad light without the photo's subjects (SubjectMask). mode 0 gives the source
// times (1 - mask), mode 1 the weight (1 - mask) alone; RestorationEngine.restore blurs both.
[[stitchable]] float4 UnderBlueSubjectWeight(coreimage::sample_t source, coreimage::sample_t mask, float mode) {
    const float w = 1.0f - clamp(mask.r, 0.0f, 1.0f);
    return mode > 0.5f ? float4(w, w, w, 1.0f) : float4(max(source.rgb, float3(0.0f)) * w, 1.0f);
}

// Weighted blur over blurred weight, outside the subject. Inside it, and where little background
// is near, the plain broad light stays (so a subject's own restoration is unchanged).
[[stitchable]] float4 UnderBlueSubjectFreeLight(coreimage::sample_t weighted, coreimage::sample_t weight,
                                                coreimage::sample_t broad, coreimage::sample_t mask) {
    const float w = weight.r;
    const float t = smoothstep(0.02f, 0.2f, w) * (1.0f - smoothstep(0.1f, 0.6f, mask.r));
    const float3 out = mix(broad.rgb, weighted.rgb / max(w, 1e-3f), t);
    return all(isfinite(out)) ? float4(out, broad.a) : broad;
}

// Video has no photo subject mask. A pixel darker than the wide light around it (a dark fish or shark)
// is lifted to that light, so the broad light for the local veil follows the water, not the subject.
// Without it, water next to a dark subject kept more veil and showed a bright halo.
// Bright pixels stay as they are. See RestorationEngine.restore.
[[stitchable]] float4 UnderBlueLiftToWide(coreimage::sample_t near, coreimage::sample_t wide) {
    return float4(max(near.rgb, wide.rgb), near.a);
}

// How much of an object's contrast survives the water in front of it: the plan's direct
// transmission at the pixel's depth, by luminance. Seen against water, apparent contrast falls as
// exp(-beta z) (Duntley's law), whatever the object's own brightness. 1 is no water in front. The
// subject lift splits its tiers by it and scales its sharpening by it (docs/SubjectEmphasis.md, E17).
[[stitchable]] float4 UnderBlueContrastTransmission(coreimage::sample_t depthSample, float4 betaDirect) {
    const float z = clamp(depthSample.r, 0.0f, 1.0f);
    const float3 t = exp(-max(betaDirect.rgb, float3(0.0f)) * z);
    const float f = clamp(dot(t, float3(0.2126f, 0.7152f, 0.0722f)), 0.0f, 1.0f);
    return float4(f, f, f, 1.0f);
}

// Object colour (RestorationEngine.objectColour, photos; docs/RestorationExperiments.md, A2). Two steps, in linear
// sRGB (toSRGB0-2 and fromSRGB0-2 are the rows of the Rec.2020 <-> sRGB matrices; the working space is linear Rec.2020):
// 1. gains.rgb take the water's tint off objects that carry it (one gain set for the frame, no mask, so no seam).
// 2. Red made from the green excess above the water's own (fade.z), max(0, G - (R + B) / 2 - fade.z), times gains.w
//    (k x redLoss), on near pixels only: full from fade.x, none from fade.y (depth 0 near, 1 far). Luminance is kept.
//    A neutral surface has no green excess and the water has none above its own, so both stay. FinishingMath.objectColour
//    is the CPU mirror.
[[stitchable]] float4 UnderBlueObjectColour(coreimage::sample_t source, coreimage::sample_t depthSample,
                                            float4 toSRGB0, float4 toSRGB1, float4 toSRGB2,
                                            float4 fromSRGB0, float4 fromSRGB1, float4 fromSRGB2,
                                            float4 gains, float4 fade) {
    const float3 c = source.rgb;
    float3 s = float3(dot(toSRGB0.rgb, c), dot(toSRGB1.rgb, c), dot(toSRGB2.rgb, c)) * gains.rgb;
    const float3 luma = float3(0.2126f, 0.7152f, 0.0722f);
    const float near = 1.0f - smoothstep(fade.x, fade.y, clamp(depthSample.r, 0.0f, 1.0f));
    const float excess = max(0.0f, s.g - 0.5f * (s.r + s.b) - fade.z);
    const float l0 = dot(s, luma);
    float3 r = s + float3(gains.w * excess * near, 0.0f, 0.0f);
    const float l1 = dot(r, luma);
    r = l1 > 1e-6f ? r * (l0 / l1) : s;
    const float3 out = float3(dot(fromSRGB0.rgb, r), dot(fromSRGB1.rgb, r), dot(fromSRGB2.rgb, r));
    return all(isfinite(out)) ? float4(out, source.a) : source;
}

/// Object colour for video (docs/RestorationExperiments.md, A2 for video): step 2 only, red from the green excess.
/// A video frame has no depth map, so a pixel's weight is how far its colour is from the scene's water (OKLab a,b
/// distance, none at water.z, full at water.w). water.xy is the water's a,b; extra.x the water's own green excess;
/// extra.y is k x redLoss. Works in linear sRGB; luminance is kept. FinishingMath.objectColourVideo is the CPU mirror.
[[stitchable]] float4 UnderBlueObjectColourVideo(coreimage::sample_t source,
                                                 float4 toSRGB0, float4 toSRGB1, float4 toSRGB2,
                                                 float4 fromSRGB0, float4 fromSRGB1, float4 fromSRGB2,
                                                 float4 water, float4 extra) {
    const float3 c = source.rgb;
    const float3 s = float3(dot(toSRGB0.rgb, c), dot(toSRGB1.rgb, c), dot(toSRGB2.rgb, c));
    const float3 lms = float3(dot(float3(0.4122214708f, 0.5363325363f, 0.0514459929f), s),
                              dot(float3(0.2119034982f, 0.6806995451f, 0.1073969566f), s),
                              dot(float3(0.0883024619f, 0.2817188376f, 0.6299787005f), s));
    const float3 q = pow(max(lms, float3(0.0f)), float3(1.0f / 3.0f));
    const float a = 1.9779984951f * q.x - 2.4285922050f * q.y + 0.4505937099f * q.z;
    const float b = 0.0259040371f * q.x + 0.7827717662f * q.y - 0.8086757660f * q.z;
    const float weight = smoothstep(water.z, water.w, length(float2(a, b) - water.xy));
    const float excess = max(0.0f, s.g - 0.5f * (s.r + s.b) - extra.x);
    const float3 luma = float3(0.2126f, 0.7152f, 0.0722f);
    const float l0 = dot(s, luma);
    float3 r = s + float3(extra.y * excess * weight, 0.0f, 0.0f);
    const float l1 = dot(r, luma);
    r = l1 > 1e-6f ? r * (l0 / l1) : s;
    const float3 out = float3(dot(fromSRGB0.rgb, r), dot(fromSRGB1.rgb, r), dot(fromSRGB2.rgb, r));
    return all(isfinite(out)) ? float4(out, source.a) : source;
}
