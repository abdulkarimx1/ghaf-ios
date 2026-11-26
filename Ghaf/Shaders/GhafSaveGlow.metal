#include <metal_stdlib>
using namespace metal;

static float ghafHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float ghafNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(ghafHash(i), ghafHash(i + float2(1, 0)), f.x),
               mix(ghafHash(i + float2(0, 1)), ghafHash(i + float2(1, 1)), f.x), f.y);
}

static float ghafFbm(float2 p) {
    float value = 0.0, amplitude = 0.5;
    // This full-screen shader runs every frame. Three octaves preserve the layered texture
    // while reducing the per-pixel work for mobile GPUs.
    for (int i = 0; i < 3; ++i) {
        value += amplitude * ghafNoise(p);
        p = p * 2.03 + float2(1.7, 9.2);
        amplitude *= 0.5;
    }
    return value;
}

[[ stitchable ]]
half4 ghafSaveGlow(float2 position, half4 sourceColor, float4 bounds,
                   float flowTime, float timelineTime, float rise, float surge, float fade,
                   float glowHeight, float energy, float lightMode,
                   float4 c1, float4 c2, float4 c3, float4 c4) {
    float2 uv = float2(position.x / max(bounds.z, 1.0),
                       1.0 - position.y / max(bounds.w, 1.0));
    float aspect = bounds.z / max(bounds.w, 1.0);
    float2 p = float2(uv.x * aspect, uv.y) * 2.4;
    // The reference keeps the animation timeline uniform separate from the boiling flow clock.
    float t = flowTime + timelineTime * 0.0;

    float2 q = float2(ghafFbm(p + float2(0.0, t * 0.35)),
                      ghafFbm(p + float2(5.2, 1.3) - t * 0.3));
    float2 r = float2(ghafFbm(p + 3.0 * q + float2(1.7, 9.2) + 0.18 * t),
                      ghafFbm(p + 3.0 * q + float2(8.3, 2.8) - 0.15 * t));
    float f = ghafFbm(p + 3.0 * r);

    float front = rise * glowHeight + surge * (1.25 - glowHeight)
        + 0.025 * sin(t * 2.1) * rise * (1.0 - surge);
    front += 0.10 * (ghafFbm(float2(uv.x * 2.6 + t * 0.45, t * 0.25)) - 0.5)
        * (1.0 + surge);
    float d = 1.0 - smoothstep(front - 0.30, front + 0.10, uv.y);
    float lowEdge = mix(-1.0, front - 0.42, surge * surge);
    d *= smoothstep(lowEdge, lowEdge + 0.32, uv.y);

    float3 col = mix(c1.rgb, c2.rgb, clamp(f * f * 3.2, 0.0, 1.0));
    col = mix(col, c3.rgb, clamp(length(q) * 0.9 - 0.15, 0.0, 1.0));
    col = mix(col, c4.rgb, clamp(r.x * r.x * 1.4 - 0.1, 0.0, 1.0) * 0.85);
    float rim = exp(-pow((uv.y - front + 0.06) * 8.0, 2.0));
    col += (0.35 + 1.1 * surge) * energy * rim * mix(c4.rgb, float3(1.0), 0.5)
        * smoothstep(0.25, 0.75, f);
    col += float3(1.0, 0.97, 0.93) * pow(f, 3.0) * 1.3 * energy * d;
    float alpha = d * (0.5 + 0.65 * f) * clamp(energy, 0.6, 1.3);

    float2 g = float2(uv.x * aspect, uv.y - t * 0.06) * 30.0;
    float2 cellID = floor(g), fp = fract(g) - 0.5;
    float h1 = ghafHash(cellID);
    float2 offset = float2(ghafHash(cellID + 1.3), ghafHash(cellID + 7.1)) - 0.5;
    float sparkle = (1.0 - smoothstep(0.0, 0.09, length(fp - offset * 0.6)))
        * step(0.88, h1) * (0.5 + 0.5 * sin(t * 7.0 + h1 * 40.0));
    sparkle *= (1.0 - smoothstep(0.0, 0.28, abs(uv.y - front + 0.05)))
        * (0.35 + surge) * energy;
    col += float3(sparkle);
    alpha = max(alpha, sparkle);

    col = mix(col, col * 0.85, lightMode);
    alpha = clamp(alpha * fade, 0.0, 1.0);
    return half4(half3(col * alpha), half(alpha)) * sourceColor.a;
}
