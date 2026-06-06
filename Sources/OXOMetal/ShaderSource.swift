// Metal shaders compiled at runtime — no .metal file needed (plain swift build).

let metalShaderSource = """
#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// Pass 1 — Geometry (phosphor elements rendered to an offscreen texture)
// ─────────────────────────────────────────────────────────────────────────────

struct VertexIn {
    float2 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.color    = in.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pass 2 — CRT post-process (barrel distortion · scanlines · vignette)
// ─────────────────────────────────────────────────────────────────────────────

struct CRTVertexIn {
    float2 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
};

struct CRTVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex CRTVertexOut vertex_crt(CRTVertexIn in [[stage_in]]) {
    CRTVertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.uv       = in.uv;
    return out;
}

fragment float4 fragment_crt(CRTVertexOut   in   [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              sampler          smp [[sampler(0)]]) {
    float2 uv = in.uv;

    float2 cc = uv * 2.0 - 1.0;   // [-1, 1] centred

    // ── Circular CRT tube boundary (round oscilloscope screen) ───────────────
    float screenR = length(cc);
    const float boundary = 0.84;

    if (screenR > boundary) {
        // Dark machine casing
        float3 bezel = float3(0.095, 0.100, 0.075);
        float  lit   = max(0.0, 1.0 - (screenR - boundary) * 5.0);
        bezel *= (0.65 + 0.35 * lit);
        // Faint blue-white bleed from phosphor screen onto bezel
        float bleed = exp(-(screenR - boundary) * (screenR - boundary) * 80.0) * 0.05;
        bezel += float3(bleed * 0.5, bleed * 0.7, bleed);
        return float4(bezel, 1.0);
    }

    // ── Barrel distortion inside screen ──────────────────────────────────────
    float r2   = dot(cc, cc);
    float2 dcc = cc * (1.0 + 0.10 * r2);
    float2 dUV = clamp(dcc * 0.5 + 0.5, 0.001, 0.999);

    float4 col = tex.sample(smp, dUV);

    // Phosphor ambient — faint blue tint in dark areas (tube never fully dark)
    float darkness = 1.0 - saturate(col.r * 0.3 + col.g * 0.5 + col.b * 0.2);
    col.rgb += float3(0.0008, 0.0015, 0.006) * darkness;

    // Scanlines
    float scan = 0.87 + 0.13 * sin(in.position.y * 3.14159265);
    col.rgb *= scan;

    // Vignette (round-tube feel — edges fade strongly)
    float normR = screenR / boundary;
    float vig   = 1.0 - pow(normR, 2.2) * 0.65;
    col.rgb    *= max(vig, 0.06);

    // Blue-white rim glow at screen edge
    float rim = exp(-pow(screenR - boundary * 0.965, 2.0) * 900.0);
    col.rgb  += float3(0.03, 0.05, 0.14) * rim;

    return float4(col.rgb, 1.0);
}
"""
