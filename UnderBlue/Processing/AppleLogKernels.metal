// The Apple Log decode kernel. AppleLog loads it.
// The curve is the decoding function of the Apple Log white paper (Sept 2023). Apple Log 2 uses the
// same curve (Sept 2025 paper). Both papers are in Apple-log/ at the repository root (not in git).
// Input: the log signal P per channel, 0...1. Output: scene-linear light (0.18 = 18% grey card,
// 12.0 at P = 1), moved into Rec.2020 by the three matrix rows. Negative light is cut to 0.
#include <CoreImage/CoreImage.h>
using namespace metal;

static float appleLogLinear(float p) {
    const float r0 = -0.05641088f, rt = 0.01f, c = 47.28711236f;
    const float beta = 0.00964052f, gamma = 0.08550479f, delta = 0.69336945f;
    const float pt = c * (rt - r0) * (rt - r0);
    if (p >= pt) return exp2((p - delta) / gamma) - beta;
    if (p >= 0.0f) return sqrt(p / c) + r0;
    return r0;
}

[[stitchable]] float4 UnderBlueAppleLogDecode(coreimage::sample_t s, float3 row0, float3 row1, float3 row2) {
    const float3 light = float3(appleLogLinear(s.r), appleLogLinear(s.g), appleLogLinear(s.b));
    return float4(max(float3(dot(row0, light), dot(row1, light), dot(row2, light)), float3(0.0f)), s.a);
}
