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

    // Map uv to [-1, 1] centred coordinates
    float2 cc = uv * 2.0 - 1.0;

    // Barrel distortion — pushes edges outward, crops corners like a CRT tube
    float r2   = dot(cc, cc);
    float2 dcc = cc * (1.0 + 0.16 * r2);
    float2 dUV = dcc * 0.5 + 0.5;

    // Outside the distorted screen boundary → render the machine bezel
    if (dUV.x < 0.0 || dUV.x > 1.0 || dUV.y < 0.0 || dUV.y > 1.0) {
        // Dark olive/grey casing, slightly lighter toward centre of bezel
        float3 bezel = float3(0.10, 0.11, 0.085);
        float  lit   = 1.0 - saturate(dot(cc * 0.55, cc * 0.55));
        bezel *= (0.75 + 0.25 * lit);
        // Faint green bleed from the phosphor screen on the surrounding bezel
        float bleed = exp(-r2 * 3.5) * 0.06;
        bezel += float3(0.0, bleed, bleed * 0.3);
        return float4(bezel, 1.0);
    }

    float4 col = tex.sample(smp, dUV);

    // Scanlines — darken alternating pixel rows (sin is ±1 at half-integer y)
    float scan = 0.82 + 0.18 * sin(in.position.y * 3.14159265);
    col.rgb *= scan;

    // Vignette — edges of the phosphor screen fade to black
    float vig = 1.0 - saturate(dot(dcc * 0.80, dcc * 0.80));
    col.rgb  *= max(vig, 0.05);

    // Inner screen-edge glow — thin bright ring at the rim of the CRT tube
    float rim = saturate(1.0 - (length(dcc) - 0.88) / 0.12);
    col.rgb  += float3(0.0, 0.03, 0.01) * (1.0 - rim);

    return float4(col.rgb, 1.0);
}
"""
