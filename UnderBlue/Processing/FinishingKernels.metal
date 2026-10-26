// The finishing kernels. FilterEngine loads them from the app's Metal library.
// Scene-level colour stage: cast gains, water tone, hue-gated red rebuild, mid-tone lift, luminance S-curve.
// Every argument comes from one ColorCorrection, so video frames share one curve.
// FinishingMath.color is the CPU mirror.
#include <CoreImage/CoreImage.h>
using namespace metal;

[[stitchable]] float4 UnderBlueFinishColor(coreimage::sample_t source, coreimage::sample_t referenceInput, float4 gains, float4 water, float4 shape, float4 red, float4 tone, float4 neutral, float4 waterLit, float4 subjectTone, float4 reference) {
    const float3 input = max(source.rgb, float3(0.0f));
    float3 c = input * max(gains.rgb, float3(0.0f));
    // A pale pixel whose red already reaches green carries no water cast (surface light): it keeps
    // its own colour at the gains' luminance. FinishingMath.uncast mirrors the weight.
    {
        const float sourceTop = max(input.r, max(input.g, input.b));
        const float sourceChroma = sourceTop > 1e-4f ? (sourceTop - min(input.r, min(input.g, input.b))) / sourceTop : 0.0f;
        const float uncast = smoothstep(0.92f, 1.0f, input.r / max(input.g, 1e-4f)) * (1.0f - smoothstep(0.15f, 0.3f, sourceChroma));
        const float3 luma = float3(0.2126f, 0.7152f, 0.0722f);
        c = mix(c, input * (dot(c, luma) / max(dot(input, luma), 1e-5f)), uncast);
    }
    // Redder subjects stay protected, with a broad transition through similar water colours.
    // Only strongly coloured water (shape.y) reliably separates silver subjects by chroma.
    // In murky water, fading that test avoids amplifying compressed colour steps into patches.
    const float redness = c.r / max(c.g + c.b, 1e-4f);
    const float top = max(c.r, max(c.g, c.b));
    const float pixelChroma = top > 1e-4f ? (top - min(c.r, min(c.g, c.b))) / top : 0.0f;
    const float chromaConfidence = smoothstep(0.55f, 0.8f, shape.y);
    const float chromaMatch = smoothstep(shape.y * 0.5f, max(shape.y * 0.85f, shape.y * 0.5f + 1e-5f), pixelChroma);
    const float waterLike = (1.0f - smoothstep(water.w, water.w + max(0.3f, water.w * 0.6f), redness))
        * (1.0f - (1.0f - chromaMatch) * chromaConfidence);
    // White reference (neutral.rgb): pixels that are not water-like, or clearly brighter than
    // the water (waterLit.rgb) and of another chromaticity, move with the neutral surfaces.
    const float3 lw = max(waterLit.rgb, float3(0.0f));
    const float waterLum = dot(lw, float3(0.2126f, 0.7152f, 0.0722f));
    const float total = c.r + c.g + c.b;
    float bright = 0.0f;
    if (waterLum > 1e-4f && total > 1e-5f) {
        const float3 d = abs(c / total - lw / (lw.r + lw.g + lw.b));
        // waterLit.w is ColorCorrection.lightGradient: 2.2-3.2 times the water, or 2.5-8 with a strong
        // light source (FinishingMath.brightLow/High, lightBrightLow/High).
        const float g = clamp(waterLit.w, 0.0f, 1.0f);
        bright = smoothstep(mix(2.2f, 2.5f, g), mix(3.2f, 8.0f, g), dot(c, float3(0.2126f, 0.7152f, 0.0722f)) / waterLum)
            * smoothstep(0.08f, 0.2f, d.r + d.g + d.b);
    }
    c *= mix(float3(1.0f), max(neutral.rgb, float3(0.0f)), 1.0f - waterLike * (1.0f - bright));
    // A bright pixel that the white reference made nearly grey is a pale surface, not water:
    // the water saturation and the water tone below skip it. FinishingMath.color mirrors it.
    const float paleTop = max(c.r, max(c.g, c.b));
    const float paleChroma = paleTop > 1e-4f ? (paleTop - min(c.r, min(c.g, c.b))) / paleTop : 0.0f;
    const float waterShare = waterLike * (1.0f - bright * (1.0f - smoothstep(0.15f, 0.35f, paleChroma)));
    // Light removal on subjects (subjectTone.rgb): pixels that are not water-like lose part of the
    // water's colour, at their own luminance. Green and blue never fall below the pixel's red, so
    // a grey subject is not made warm. FinishingMath.color mirrors it.
    {
        float3 removed = c * mix(float3(1.0f), max(subjectTone.rgb, float3(0.0f)), 1.0f - waterLike);
        removed.gb = max(removed.gb, min(c.gb, float2(c.r)));
        // The removal never makes a pixel greener: blue keeps at least its share of green.
        removed.b = max(removed.b, removed.g * min(1.0f, c.b / max(c.g, 1e-4f)));
        const float kept = dot(c, float3(0.2126f, 0.7152f, 0.0722f));
        const float left = dot(removed, float3(0.2126f, 0.7152f, 0.0722f));
        if (left > 1e-6f) { c = removed * (kept / left); }
    }
    // In a blue pixel, red above green reads violet: gains may not lift red past green or the
    // pixel's own red. In water-like pixels (weighted by shape.w) red stops at green.
    const float blue = smoothstep(1.3f, 2.0f, c.b / max(max(c.r, c.g), 1e-4f));
    const float limit = mix(max(input.r, c.g), c.g, clamp(waterLike * shape.w, 0.0f, 1.0f));
    c.r = mix(c.r, min(c.r, limit), blue);
    // Water chroma scale (shape.x) around luminance calms neon water; then the water gains.
    const float y0 = dot(c, float3(0.2126f, 0.7152f, 0.0722f));
    c = max(float3(y0) + (c - float3(y0)) * mix(1.0f, max(shape.x, 0.0f), waterShare), float3(0.0f));
    c *= mix(float3(1.0f), max(water.rgb, float3(0.0f)), waterShare);
    // Rebuild red from green only where green is near blue. Blue water gets almost none,
    // so it cannot drift to violet. Strongly green pixels also get little, so green
    // water and weed do not turn yellow. Pixels redder than the water get a little more.
    const float greenBlue = c.g / max(c.b, 1e-4f);
    const float hue = smoothstep(red.y, red.z, greenBlue) * (1.0f - smoothstep(1.35f, 2.2f, greenBlue));
    const float subject = smoothstep(red.w, red.w + 0.3f, c.r / max(c.g, 1e-4f));
    // Rebuilt red stops at shape.z times green, so grey subjects stay grey.
    // Where green and blue both clip in the source, their ratio reads 1 whatever the colour was, so the gate opened
    // fully on the blown-out disc around the sun and drew a sharp ring where the clipping ended (hammerhead clips,
    // 26 Oct 2026). The rebuild fades out as both near clipping, which follows the light's own soft fall-off. Blue
    // alone clipping (deep blue water) keeps it: fading on the brightest channel put new steps into that water.
    const float unclipped = 1.0f - smoothstep(0.7f, 1.0f, min(input.g, input.b));
    c.r += min(max(red.x, 0.0f) * c.g * hue * (0.6f + 0.4f * subject) * unclipped, max(0.0f, c.g * shape.z - c.r));
    float surface = (1.0f - waterLike * (1.0f - bright))
        * smoothstep(0.04f, 0.16f, dot(input, float3(0.2126f, 0.7152f, 0.0722f)));
    surface *= 1.0f - smoothstep(0.8f, 0.9f, dot(input, float3(-0.124550f, 1.132900f, -0.008349f)));
    if (reference.w > 0.0f) {
        float3 shown = float3(dot(referenceInput.rgb, float3(1.660491f, -0.587641f, -0.072850f)),
                              dot(referenceInput.rgb, float3(-0.124550f, 1.132900f, -0.008349f)),
                              dot(referenceInput.rgb, float3(-0.018151f, -0.100579f, 1.118730f)));
        shown = max(shown, float3(0.0f)) * reference.rgb;
        const float shownTop = max(shown.r, max(shown.g, shown.b));
        const float shownChroma = shownTop > 1e-4f ? (shownTop - min(shown.r, min(shown.g, shown.b))) / shownTop : 0.0f;
        surface *= 1.0f - smoothstep(0.5f, 0.8f, dot(input, float3(0.2126f, 0.7152f, 0.0722f)))
            * (1.0f - smoothstep(0.15f, 0.45f, shownChroma));
        const float3 adapted = float3(dot(shown, float3(0.627404f, 0.329283f, 0.043313f)),
                                      dot(shown, float3(0.069097f, 0.919540f, 0.011362f)),
                                      dot(shown, float3(0.016391f, 0.088013f, 0.895595f)));
        c = mix(c, adapted, reference.w * surface);
    }
    // Mid-tone lift, then an S-curve around the scene median, both on gamma luminance.
    // Zero and one stay fixed.
    const float l = dot(c, float3(0.2126f, 0.7152f, 0.0722f));
    if (l > 1e-5f && l < 1.0f) {
        float x = pow(l, 1.0f / 2.2f);
        // A negative lift (Brightness down) darkens; -0.25 is ColorCorrection.minimumMidLift.
        x += max(tone.z, -0.25f) * x * (1.0f - x);
        // A negative curve (Custom Contrast down) bends the tones above the pivot. It fades out between 0.6x and 1.4x
        // the pivot, so dark tones are not lifted.
        const float fade = tone.x < 0.0f ? smoothstep(0.6f * tone.y, 1.4f * tone.y, x) : 1.0f;
        const float bend = 4.0f * tone.x * (x - tone.y) * x * (1.0f - x) * fade;
        const float y = clamp(x + bend, 0.0f, 1.0f);
        const float peak = max(c.r, max(c.g, c.b));
        // Cap the gain so no channel crosses one, and HDR peaks above one never grow.
        c *= min(pow(y, 2.2f) / l, max(1.0f, peak) / max(peak, 1e-5f));
    }
    if (reference.w > 0.0f) {
        const float3 linear = c * max(0.0f, neutral.w) + tone.w;
        float3 soft = linear;
        if (tone.w < 0.0f) {
            const float floor = 0.5f * (tone.w + sqrt(tone.w * tone.w + 0.0004f));
            soft = max(float3(0.0f), 0.5f * (linear + sqrt(linear * linear + 0.0004f)) - floor);
        }
        c = mix(c, mix(linear, soft, surface), reference.w);
    }
    if (!all(isfinite(c))) { c = input; }
    return float4(c, source.a);
}

// Fine detail layer, after the unsharp masks. FinishingMath.detail is the CPU mirror.
// source = the pixel after the unsharp masks, blurred = its blur at detailRadius, reference = the
// finishing input (what the colour kernel judged as water). gains = castGains,
// water = (waterRedness, waterChroma), waterLit = the water after the gains, detail = (strength,
// floor, edgeLow, edgeHigh), shadow = (shadowLow, shadowHigh). Luminance only, in a band, where the
// white reference lands (the colour kernel's neutral weight): subjects and pale surfaces brighter
// than the water. Open water gets nothing.
// calm.b is the subject weight of the unrestored source (UnderBlueCalmWeight); 1 without a source.
[[stitchable]] float4 UnderBlueDetail(coreimage::sample_t source, coreimage::sample_t blurred, coreimage::sample_t reference, coreimage::sample_t calm, float4 gains, float4 water, float4 waterLit, float4 detail, float4 shadow) {
    const float3 c = source.rgb;
    const float3 luma = float3(0.2126f, 0.7152f, 0.0722f);
    const float l = dot(max(c, float3(0.0f)), luma), lb = dot(max(blurred.rgb, float3(0.0f)), luma);
    if (!isfinite(l) || !isfinite(lb) || !(l > 1e-5f) || !(l < 1.0f) || !(detail.x > 0.0f)) { return source; }
    const float x = pow(l, 1.0f / 2.2f), d = x - pow(lb, 1.0f / 2.2f), a = fabs(d);
    const float band = smoothstep(detail.y, max(3.0f * detail.y, detail.y + 1e-5f), a) * (1.0f - smoothstep(detail.z, detail.w, a));
    const float lit = smoothstep(shadow.x, shadow.y, l);
    // The colour kernel's water-like test, on the finishing input after the cast gains.
    const float3 r = max(reference.rgb, float3(0.0f)) * max(gains.rgb, float3(0.0f));
    const float redness = r.r / max(r.g + r.b, 1e-4f);
    const float top = max(r.r, max(r.g, r.b));
    const float pixelChroma = top > 1e-4f ? (top - min(r.r, min(r.g, r.b))) / top : 0.0f;
    const float chromaConfidence = smoothstep(0.55f, 0.8f, water.y);
    const float chromaMatch = smoothstep(water.y * 0.5f, max(water.y * 0.85f, water.y * 0.5f + 1e-5f), pixelChroma);
    const float waterLike = (1.0f - smoothstep(water.x, water.x + max(0.3f, water.x * 0.6f), redness))
        * (1.0f - (1.0f - chromaMatch) * chromaConfidence);
    const float3 lw = max(waterLit.rgb, float3(0.0f));
    const float waterLum = dot(lw, luma);
    const float total = r.r + r.g + r.b;
    float bright = 0.0f;
    if (waterLum > 1e-4f && total > 1e-5f) {
        const float3 diff = abs(r / total - lw / (lw.r + lw.g + lw.b));
        bright = smoothstep(2.2f, 3.2f, dot(r, luma) / waterLum) * smoothstep(0.08f, 0.2f, diff.r + diff.g + diff.b);
    }
    const float subject = 1.0f - waterLike * (1.0f - bright);
    const float weight = max(detail.x, 0.0f) * band * min(subject, clamp(calm.b, 0.0f, 1.0f)) * lit;
    const float y = max(0.0f, x + weight * d);
    const float peak = max(c.r, max(c.g, c.b));
    const float3 out = c * min(pow(y, 2.2f) / l, max(1.0f, peak) / max(peak, 1e-5f));
    return all(isfinite(out)) ? float4(out, source.a) : source;
}

// Contrast gain and black offset (tone = gain, offset), as CIColorControls computes them, with a
// shadow toe instead of a clip. FinishingMath.blackOffset is the CPU mirror.
[[stitchable]] float4 UnderBlueBlackOffset(coreimage::sample_t source, float4 tone) {
    const float3 x = source.rgb * tone.x;
    float3 out = x + tone.y;
    if (tone.y < 0.0f) {
        // Below twice the offset, a quadratic toe: zero stays zero, and it meets the straight line
        // with the same slope. Without it, everything darker than the offset clipped to black.
        const float knee = -2.0f * tone.y;
        const float3 toe = max(x, float3(0.0f)) * max(x, float3(0.0f)) / (2.0f * knee);
        out = select(out, toe, x < knee);
        // tone.z is the shadow floor (video only): no pixel below the knee falls under tone.z times its own value.
        out = max(out, min(max(x, float3(0.0f)), float3(knee)) * tone.z);
    }
    return all(isfinite(out)) ? float4(out, source.a) : source;
}

// Highlight shoulder, the last finishing step. FinishingMath.shoulder is the CPU mirror.
// The peak is read in BT.709 primaries; the ceiling is white or the reference's own (HDR) peak.
// shape: x = shoulder width, y and z = the overshoot range, w = the start of the pale range.
// pale.x = the end of the pale range. Both ranges move a pixel toward white.
[[stitchable]] float4 UnderBlueHighlightShoulder(coreimage::sample_t source, coreimage::sample_t reference, float4 shape, float4 pale) {
    const float3x3 display = float3x3(float3(1.660491f, -0.124550f, -0.018151f),
                                      float3(-0.587641f, 1.132900f, -0.100579f),
                                      float3(-0.072850f, -0.008349f, 1.118730f));
    const float3 c = source.rgb;
    const float3 d = display * c, r = display * reference.rgb;
    const float peak = max(d.r, max(d.g, d.b));
    const float ceiling = max(1.0f, max(r.r, max(r.g, r.b)));
    const float width = max(shape.x, 1e-4f), knee = ceiling - width;
    if (!(peak > knee) || !isfinite(peak)) { return source; }
    const float rolled = knee + width * (1.0f - exp(-(peak - knee) / width));
    const float white = max(smoothstep(shape.y, shape.z, peak / ceiling),
                            smoothstep(shape.w, pale.x, min(d.r, min(d.g, d.b)) / ceiling));
    const float3 out = mix(c * (rolled / peak), float3(rolled), white);
    return all(isfinite(out)) ? float4(out, source.a) : source;
}

// Luminance-only sharpening (FilterEngine.finishing). The unsharp masks run on RGB, so they also
// sharpen colour noise. The pixel keeps its unsharpened colour and takes the sharpened luminance.
[[stitchable]] float4 UnderBlueLumaTransfer(coreimage::sample_t base, coreimage::sample_t sharp) {
    const float3 w = float3(0.2126f, 0.7152f, 0.0722f);
    const float before = dot(base.rgb, w), after = dot(sharp.rgb, w);
    if (!(before > 1e-5f)) { return float4(sharp.rgb, base.a); }
    const float3 out = base.rgb * max(0.0f, after / before);
    return all(isfinite(out)) ? float4(out, base.a) : sharp;
}

// Light detail: inside bright broad light, the pixel's difference from its blur (gamma luminance)
// grows, so light rays stay apart. Large differences (edges) get none. FinishingMath.lightDetail
// mirrors it. sharp = the unsharp mask at intensity 1 (pixel + (pixel - blur)), so the blur is
// 2 * pixel - sharp. shape = (amount, bright low, bright high, unused), edge = (edge low, edge high).
[[stitchable]] float4 UnderBlueLightDetail(coreimage::sample_t source, coreimage::sample_t sharp, coreimage::sample_t grain, float4 shape, float4 edge) {
    const float3 luma = float3(0.2126f, 0.7152f, 0.0722f);
    const float l = dot(source.rgb, luma), lb = dot(2.0f * source.rgb - sharp.rgb, luma);
    if (!(l > 1e-5f) || !(lb > 0.0f)) { return source; }
    const float y = pow(l, 1.0f / 2.2f), b = pow(lb, 1.0f / 2.2f), d = y - b;
    // Light rays sit in smooth water; bright sand also passes the brightness test, and its texture turned into
    // blotches (r03, r14). So the detail fades where the local grain (UnderBlueGrain) runs from edge.z to edge.w.
    // Grain level, 1920 px, 25 Oct 2026: IMG_7400 rays 0.003, sand 0.013 to 0.015.
    const float smooth = 1.0f - smoothstep(edge.z, edge.w, max(grain.r, 0.0f));
    const float w = smoothstep(shape.y, shape.z, b) * (1.0f - smoothstep(edge.x, edge.y, fabs(d))) * smooth;
    const float shaped = min(max(y + d * shape.x * w, 0.0f), max(1.0f, y));
    const float3 out = source.rgb * (pow(shaped, 2.2f) / l);
    return all(isfinite(out)) ? float4(out, source.a) : source;
}

// Grain (FilterEngine.finishing, before the light detail): the gamma-luminance difference between a pixel and its
// small blur. Blurred wide, it is the local grain level. The light detail fades where it is high (bright sand;
// docs/RestorationExperiments.md, 25 Oct 2026).
[[stitchable]] float4 UnderBlueGrain(coreimage::sample_t source, coreimage::sample_t blurred) {
    const float3 luma = float3(0.2126f, 0.7152f, 0.0722f);
    const float l = dot(max(source.rgb, float3(0.0f)), luma), lb = dot(max(blurred.rgb, float3(0.0f)), luma);
    const float d = fabs(pow(l, 1.0f / 2.2f) - pow(lb, 1.0f / 2.2f));
    return float4(isfinite(d) ? d : 0.0f, 0.0f, 0.0f, 1.0f);
}

// The size of the light detail's difference (gamma luminance), the input of its edge guard in
// FilterEngine.finishing. Same pixel and blur as UnderBlueLightDetail.
[[stitchable]] float4 UnderBlueLightEdge(coreimage::sample_t source, coreimage::sample_t sharp) {
    const float3 luma = float3(0.2126f, 0.7152f, 0.0722f);
    const float l = dot(source.rgb, luma), lb = dot(2.0f * source.rgb - sharp.rgb, luma);
    const float d = l > 1e-5f && lb > 0.0f ? fabs(pow(l, 1.0f / 2.2f) - pow(lb, 1.0f / 2.2f)) : 0.0f;
    return float4(isfinite(d) ? d : 0.0f, 0.0f, 0.0f, 1.0f);
}

// Water calm (FilterEngine.waterCalmWeight and finishing). FinishingMath.calmShare, calmFlatness and
// waterCalm are the CPU mirrors. Water noise and the sharpening on it rise with the correction; open
// water has no detail to keep, so it is smoothed before the colour stage and gets no sharpening.

// The water share of a pixel: 1 - the colour kernel's neutral weight (FinishingMath.neutralWeight).
static float calmWaterShare(float3 c, float4 gains, float4 water, float4 waterLit) {
    const float3 luma = float3(0.2126f, 0.7152f, 0.0722f);
    const float3 r = max(c, float3(0.0f)) * max(gains.rgb, float3(0.0f));
    const float redness = r.r / max(r.g + r.b, 1e-4f);
    const float top = max(r.r, max(r.g, r.b));
    const float pixelChroma = top > 1e-4f ? (top - min(r.r, min(r.g, r.b))) / top : 0.0f;
    const float chromaConfidence = smoothstep(0.55f, 0.8f, water.y);
    const float chromaMatch = smoothstep(water.y * 0.5f, max(water.y * 0.85f, water.y * 0.5f + 1e-5f), pixelChroma);
    const float waterLike = (1.0f - smoothstep(water.x, water.x + max(0.3f, water.x * 0.6f), redness))
        * (1.0f - (1.0f - chromaMatch) * chromaConfidence);
    const float3 lw = max(waterLit.rgb, float3(0.0f));
    const float waterLum = dot(lw, luma);
    const float total = r.r + r.g + r.b;
    float bright = 0.0f;
    if (waterLum > 1e-4f && total > 1e-5f) {
        const float3 diff = abs(r / total - lw / (lw.r + lw.g + lw.b));
        // waterLit.w is ColorCorrection.lightGradient, as in the colour kernel (FinishingMath.neutralWeight).
        const float g = clamp(waterLit.w, 0.0f, 1.0f);
        bright = smoothstep(mix(2.2f, 2.5f, g), mix(3.2f, 8.0f, g), dot(r, luma) / waterLum) * smoothstep(0.08f, 0.2f, diff.r + diff.g + diff.b);
    }
    return waterLike * (1.0f - bright);
}

static float calmGamma(float3 c) {
    return pow(max(dot(c, float3(0.2126f, 0.7152f, 0.0722f)), 0.0f), 1.0f / 2.2f);
}

// basis = the blurred source. Gamma luminance times the water share, and the share in alpha.
[[stitchable]] float4 UnderBlueCalmShare(coreimage::sample_t basis, float4 gains, float4 water, float4 waterLit) {
    const float s = calmWaterShare(basis.rgb, gains, water, waterLit);
    const float y = calmGamma(basis.rgb) * s;
    return float4(y, y, y, s);
}

// The distance of the luminance from its water-only mean, times the water share.
[[stitchable]] float4 UnderBlueCalmSpread(coreimage::sample_t basis, coreimage::sample_t mean, coreimage::sample_t share) {
    const float m = mean.a > 1e-3f ? mean.r / mean.a : calmGamma(basis.rgb);
    const float d = fabs(calmGamma(basis.rgb) - m) * share.a;
    return float4(d, d, d, share.a);
}

// weight (r) = share x flatness; the share (g) for the water-only blur; the subject weight of the
// unblurred source pixel (b) for the fine detail. flat = (low, high).
[[stitchable]] float4 UnderBlueCalmWeight(coreimage::sample_t share, coreimage::sample_t spread, coreimage::sample_t basis, float4 gains, float4 water, float4 waterLit, float4 flat) {
    const float s = spread.a > 1e-3f ? spread.r / spread.a : 1.0f;
    const float w = share.a * (1.0f - smoothstep(flat.x, max(flat.y, flat.x + 1e-5f), s));
    return float4(w, share.a, 1.0f - calmWaterShare(basis.rgb, gains, water, waterLit), 1.0f);
}

// The pixel times its water share, share in alpha, for a blur of water pixels only.
[[stitchable]] float4 UnderBlueCalmPremultiply(coreimage::sample_t source, coreimage::sample_t weight) {
    return float4(source.rgb * weight.g, weight.g);
}

// The pixel moves toward the water-only blur by the weight. A subject's colour never enters the blur.
[[stitchable]] float4 UnderBlueWaterCalm(coreimage::sample_t source, coreimage::sample_t waterBlur, coreimage::sample_t weight) {
    if (!(waterBlur.a > 1e-3f)) { return source; }
    const float3 out = mix(source.rgb, waterBlur.rgb / waterBlur.a, clamp(weight.r, 0.0f, 1.0f));
    return all(isfinite(out)) ? float4(out, source.a) : source;
}

// Water core (FilterEngine.waterCore, FinishingMath.waterCore): in water the weak part of the band between two blurs
// (fine minus wide) comes off, before colour. The tone stage and the restored path would amplify it into blotches.
// A stronger band (a faint fish or diver) stays. weight.g is the water share; around.g the share blurred wide, so the core
// keeps away from subjects: next to one the wide blur holds the subject, and the water got its light or its dark (an aura
// around m5's coral, a dark rim on the napoleon wrasse, rings around small fish; Jake, 26 Oct 2026).
// core = (low, high, strength, the blurred share where the core starts).
[[stitchable]] float4 UnderBlueWaterCore(coreimage::sample_t source, coreimage::sample_t fine, coreimage::sample_t wide, coreimage::sample_t weight, coreimage::sample_t around, float4 core) {
    const float3 luma = float3(0.2126f, 0.7152f, 0.0722f);
    const float3 band = fine.rgb - wide.rgb;
    const float relative = fabs(dot(band, luma)) / max(dot(wide.rgb, luma), 1e-4f);
    const float weak = 1.0f - smoothstep(core.x, max(core.y, core.x + 1e-5f), relative);
    const float open = smoothstep(core.w, 1.0f, around.g);
    const float3 out = source.rgb - band * (weak * core.z * clamp(weight.g, 0.0f, 1.0f) * open);
    return all(isfinite(out)) ? float4(out, source.a) : source;
}

// The sharpened pixel goes back to the unsharpened one by the weight.
[[stitchable]] float4 UnderBlueCalmKeep(coreimage::sample_t before, coreimage::sample_t after, coreimage::sample_t weight) {
    const float3 out = mix(after.rgb, before.rgb, clamp(weight.r, 0.0f, 1.0f));
    return all(isfinite(out)) ? float4(out, after.a) : after;
}

// Violet calm, on the shown output (FilterEngine.violetCalm). FinishingMath.violetCalm is the CPU mirror.
// The correction can push red into blue pixels until they read violet or magenta: a reef behind blue
// water, sunlit water. A clearly violet pixel (OKLab hue 282 to 340, chroma from 0.015 to 0.03) changes,
// unless the source pixel was violet too (a magenta anemone): water turns back to blue at its own
// chroma, a subject loses its chroma. Lightness stays.
static float3 violetOKLab(float3 c) {
    const float x = dot(c, float3(0.6369580f, 0.1446169f, 0.1688810f));
    const float y = dot(c, float3(0.2627002f, 0.6779981f, 0.0593017f));
    const float z = dot(c, float3(0.0f, 0.0280727f, 1.0609851f));
    const float3 lms = float3(0.8189330101f * x + 0.3618667424f * y - 0.1288597137f * z,
                              0.0329845436f * x + 0.9293118715f * y + 0.0361456387f * z,
                              0.0482003018f * x + 0.2643662691f * y + 0.6338517070f * z);
    const float3 q = sign(lms) * pow(abs(lms), float3(1.0f / 3.0f));
    return float3(dot(q, float3(0.2104542553f, 0.7936177850f, -0.0040720468f)),
                  dot(q, float3(1.9779984951f, -2.4285922050f, 0.4505937099f)),
                  dot(q, float3(0.0259040371f, 0.7827717662f, -0.8086757660f)));
}
static float3 violetLinear(float3 o) {
    const float3 q = float3(o.x + 0.3963377774f * o.y + 0.2158037573f * o.z,
                            o.x - 0.1055613458f * o.y - 0.0638541728f * o.z,
                            o.x - 0.0894841775f * o.y - 1.2914855480f * o.z);
    const float3 lms = q * q * q;
    const float3 xyz = float3(dot(lms, float3(1.2270138511f, -0.5577999807f, 0.2812561490f)),
                              dot(lms, float3(-0.0405801784f, 1.1122568696f, -0.0716766787f)),
                              dot(lms, float3(-0.0763812845f, -0.4214819784f, 1.5861632204f)));
    return float3(dot(xyz, float3(1.7166512f, -0.3556708f, -0.2533663f)),
                  dot(xyz, float3(-0.6666844f, 1.6164812f, 0.0157685f)),
                  dot(xyz, float3(0.0176399f, -0.0427706f, 0.9421031f)));
}
static float violetHue(float3 o) { return fmod(atan2(o.z, o.y) * 57.29578f + 360.0f, 360.0f); }
// water = the water calm weight (g = the source's water share). Water turns back to blue
// (shape.y, OKLab hue) at its own chroma; a subject loses violetCalm (shape.x) of its chroma.
[[stitchable]] float4 UnderBlueVioletCalm(coreimage::sample_t c, coreimage::sample_t source, coreimage::sample_t water, float4 shape) {
    const float3 o = violetOKLab(c.rgb);
    if (!(length(o.yz) > 1e-5f)) { return c; }
    const float h = violetHue(o);
    const float violet = smoothstep(270.0f, 282.0f, h) * (1.0f - smoothstep(340.0f, 352.0f, h))
        * smoothstep(0.015f, 0.03f, length(o.yz));
    if (!(violet > 0.0f)) { return c; }
    const float3 so = violetOKLab(source.rgb);
    const float sh = violetHue(so);
    const float sourceViolet = smoothstep(270.0f, 280.0f, sh) * (1.0f - smoothstep(345.0f, 355.0f, sh))
        * smoothstep(0.01f, 0.025f, length(so.yz));
    const float made = violet * (1.0f - sourceViolet);
    const float share = clamp(water.g, 0.0f, 1.0f);
    const float C = length(o.yz);
    const float keep = 1.0f - clamp(shape.x, 0.0f, 1.0f) * made * (1.0f - share);
    const float hb = (h + (shape.y - h) * made * share) * 0.017453293f;
    const float3 out = violetLinear(float3(o.x, float2(cos(hb), sin(hb)) * C * keep));
    return all(isfinite(out)) ? float4(out, c.a) : c;
}

// Subject lift (docs/SubjectEmphasis.md). It runs once, on the blended output, after the depth blend
// and before the violet calm: a step inside the finishing kernel runs on both paths, and the blend
// then dilutes it. The highlight shoulder has already run per path, so the lift rolls itself off.
// mask.r is the subject weight. params: x = L gain, y = chroma cap, z = highlight start, w = noise floor.
[[stitchable]] float4 UnderBlueSubjectLift(coreimage::sample_t c, coreimage::sample_t mask, coreimage::sample_t blurred, coreimage::sample_t wide, coreimage::sample_t water, coreimage::sample_t signal, coreimage::sample_t tiers, float4 params, float4 shape, float4 det, float4 hi, float4 tier) {
    float w = clamp(mask.r, 0.0f, 1.0f);
    // Vision builds the mask at 1024 on the long side. Stretched to full size its edge spreads over
    // several pixels, and the lift used to follow that ramp into the water: the water within 4 px of
    // the outline changed by 0.0155 (Jake saw a halo there, 22 Oct 2026). The remap moves the ramp
    // inside the subject, so the weight is zero in the water. hi.z and hi.w are its ends.
    if (hi.w > hi.z) { w = smoothstep(hi.z, hi.w, w); }
    // Tier two. Vision returns object-like things and stops: on five of Jake's photos it gave the
    // diver or the anemone and left the reef or the wreck out (23 Oct 2026). Those are subjects too.
    // The water share already says which pixels are not open water, so its complement carries them,
    // at shape.w of the strength. It is a layer, not an instance, so no picker can offer it.
    // Tier three splits tier two by the water in front, not by a depth cut. `signal` is how much of an
    // object's contrast survives that water (UnderBlueContrastTransmission): 1 for a reef in front, less
    // for one further back. It follows the plan's own water, so clear water keeps a far reef near and
    // murky water sends it back. It replaced a fixed cut at depth 0.4 (E17).
    // tier: x = tier three, y and z are the highlight pulls for tiers two and three, w = 1 when `tiers` holds
    // the tier map (SubjectTierMap: red tier two, green tier three, already outside every Vision group).
    const float f = clamp(signal.r, 0.0f, 1.0f);
    float w2 = 0.0f, w3 = 0.0f;
    if (shape.w > 0.0f || tier.x > 0.0f) {
        if (tier.w > 0.5f) {
            // The map is the picker's outline before its 0.5 cut, so the lift changes what the user sees
            // outlined, and nothing the outline leaves out: sand, the sunlit surface, bubbles (E25).
            // It holds no subject, so (1 - w) takes the picked subjects out. A subject the user excluded
            // is then treated like the scene around it, not left as a hole (Jake, 24 Oct 2026).
            w2 = shape.w * clamp(tiers.r, 0.0f, 1.0f) * (1.0f - w);
            w3 = tier.x * clamp(tiers.g, 0.0f, 1.0f) * (1.0f - w);
        } else {
            // The share is in alpha. Red holds gamma luminance times the share (UnderBlueCalmShare), so
            // reading red put tiers two and three on open water at 0.33 to 0.59 of their weight (E22).
            const float notWater = (1.0f - clamp(water.a, 0.0f, 1.0f)) * (1.0f - w);
            w2 = shape.w * notWater * f;
            w3 = tier.x * notWater * (1.0f - f);
        }
        w = w + w2 + w3;
    }
    if (!(w > 0.0f)) { return c; }
    const float3 o = violetOKLab(c.rgb);
    const float L = o.x;
    if (!(L > 0.0f)) { return c; }
    // The two guards run before any weight is derived from w. A very dark pixel carries little
    // signal, so lifting it lifts its noise. The highlight shoulder is behind us, so the lift lets
    // go before white. Both scale every tier by the same factor, which keeps their proportions.
    // They used to run after wNear and wTex were taken, so the brightness and the sharpening missed
    // them entirely. DSC03687 clipped 0.0557 against 0.0012 today (23 Oct 2026).
    // A guard on the brightest channel was tried here and dropped (23 Oct 2026). It moved DSC03687
    // only from 0.0422 to 0.0338, and it made DSC03656 worse, 0.0714 to 0.0905: cutting the weight
    // also cuts the highlight pull, which was recovering that photo's blown sun.
    const float guard = smoothstep(0.0f, max(params.w, 1e-4f), L) * (1.0f - smoothstep(params.z, 1.0f, L));
    w *= guard; w2 *= guard; w3 *= guard;
    if (!(w > 0.0f)) { return c; }
    // Each tier carries its own highlight pull, weighted by how much of this pixel it owns. A reef
    // clips where a Vision subject does not, so one pull for all three was too weak (23 Oct 2026).
    const float wv = max(0.0f, w - w2 - w3);
    const float pull = (hi.x * wv + tier.y * w2 + tier.z * w3) / max(w, 1e-4f);
    // The tiers do not do the same job. A reference edit brightens the subject and gives the
    // background contrast alone, so the deep blue stays (Jake, 23 Oct 2026). So the brightness and
    // the chroma follow the near weight, while contrast, clarity and sharpening use all three.
    const float wNear = wv + w2;
    // Sharpening follows the same transmission t. The restoration divides by t, so the noise of a far
    // pixel is 1/t times a near one's. Sharpening by t keeps the noise it adds the same at every depth,
    // and a far subject seen through more water gets less (Jake, 23 Oct 2026). It used to fall by a
    // fixed 0.8 x depth (E17).
    const float wTex = w * f;
    // Gamma, not a gain. A gain multiplies L, so a bright pixel passes white by construction
    // (E4, 22 Oct 2026: gain 1.2 clipped 19% of the O4 subject). Gamma cannot pass white, and it
    // lifts the dark part of the subject most, which is the part that needed it.
    float Lnew = pow(L, 1.0f - clamp(params.x, 0.0f, 0.9f) * wNear);
    // Contrast inside the subject, around shape.z. It moves luminance only, so it cannot raise the
    // water cast the way a chroma rule does (E5, 22 Oct 2026). The curve is per pixel, so it draws
    // no halo: the dark outline comes from blur-based methods, not from this.
    Lnew = clamp(Lnew + shape.y * w * (Lnew - shape.z), 0.0f, 1.0f);
    // Sharpening inside the subject. The global detail layer gave up texture on 20 Oct 2026 to stop
    // halos everywhere (ColorAlgorithm.md). Inside the mask the band can be wider, because the mask
    // already says where a subject is. det: x = strength, y = band low, z = band high.
    // Clarity first: a wider blur, so it shapes the big forms before the fine texture goes on top.
    // `clarity` and `definition` were both cut to 0.6 everywhere on 28 Sep 2026 (ColorAlgorithm.md).
    if (det.w > 0.0f) {
        const float wp = L - violetOKLab(wide.rgb).x;
        Lnew = clamp(Lnew + det.w * wTex * wp, 0.0f, 1.0f);
    }
    if (det.x > 0.0f) {
        const float hp = L - violetOKLab(blurred.rgb).x;
        // A strong edge gets nothing, so an outline grows no halo.
        const float edge = 1.0f - smoothstep(det.y, max(det.z, det.y + 1e-4f), fabs(hp));
        Lnew = clamp(Lnew + det.x * wTex * edge * hp, 0.0f, 1.0f);
    }
    // Highlight pull, last, so it tames what the steps above produced. Above the knee the range is
    // compressed toward the knee. Our highlights sit 5 to 10 L* over the market look.
    if (pull > 0.0f && Lnew > hi.y) {
        Lnew = hi.y + (Lnew - hi.y) * (1.0f - clamp(pull, 0.0f, 1.0f) * w);
    }
    // A brighter pixel reads as less saturated, so chroma follows a power of the ratio, capped.
    // shape.x is that power. The cube root alone gave about 3%, against the 56% to 70% the earlier
    // steps take off the subject (E4, 22 Oct 2026), so the power is a knob, not a constant.
    const float scale = min(pow(max(Lnew / L, 1e-4f), max(shape.x, 0.0f)), max(params.y, 1.0f));
    float3 out = violetLinear(float3(Lnew, o.yz * scale));
    // Gamma keeps L under white, but the chroma scale can still push one channel over it.
    // The pull-back lands the brightest channel exactly on white and keeps the hue.
    const float inTop = max(c.r, max(c.g, c.b));
    const float outTop = max(out.r, max(out.g, out.b));
    if (outTop > 1.0f) {
        out = mix(c.rgb, out, clamp((1.0f - inTop) / max(outTop - inTop, 1e-4f), 0.0f, 1.0f));
    }
    return all(isfinite(out)) ? float4(out, c.a) : c;
}

