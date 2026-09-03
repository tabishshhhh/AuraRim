/// Metal source for the rim shader, compiled at runtime (`makeLibrary(source:)`)
/// so no offline metallib build step is required. Kept as source-of-truth text;
/// the fragment logic follows spec §65 (core + bloom), §66 (perimeter gradient)
/// and §67 (notch mask).
enum RimShaderSource {
    static let metal = """
    #include <metal_stdlib>
    using namespace metal;

    struct RimUniforms {
        float4 primaryColor;
        float4 secondaryColor;
        float2 resolution;
        float  time;
        float  rimThickness;   // pixels
        float  glowRadius;     // pixels
        float  brightness;     // ~0..1.6
        float  opacity;        // 0..1
        float  gradientMix;    // 0..1 balance
        float  pulseStrength;  // beat envelope 0..1
        float  beatPhase;
        float  idlePhase;
        float  silence;        // 0 loud … 1 silent
        float  notchCenterX;   // pixels from left
        float  notchWidth;     // pixels
        float  notchHeight;    // pixels
        float  cornerRadius;   // pixels
        float  gradientRotation;
        int    animationMode;  // 0 music, 1 idle, 2 static
        int    notchEnabled;
    };

    struct VOut { float4 pos [[position]]; float2 uv; };

    // Full-screen triangle. uv (0,0) top-left → (1,1) bottom-right.
    vertex VOut rim_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
        VOut o;
        o.pos = float4(p, 0.0, 1.0);
        o.uv = float2((p.x + 1.0) * 0.5, 1.0 - (p.y + 1.0) * 0.5);
        return o;
    }

    // Signed distance to a rounded box (negative inside).
    static float sdRoundBox(float2 p, float2 halfSize, float r) {
        float2 q = abs(p) - (halfSize - r);
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    fragment float4 rim_fragment(VOut in [[stage_in]],
                                 constant RimUniforms &u [[buffer(0)]]) {
        float2 res = u.resolution;
        float2 pixel = in.uv * res;
        float2 center = res * 0.5;
        float2 halfRes = center;

        // Distance from the screen boundary, growing inward (rounded corners).
        float sd = sdRoundBox(pixel - center, halfRes, max(u.cornerRadius, 1.0));
        float dist = max(-sd, 0.0);

        // Animation modulation.
        float pulse = 1.0;
        float thick = u.rimThickness;
        float glowR = max(u.glowRadius, 1.0);
        float rot = u.gradientRotation;
        if (u.animationMode == 0) {                 // Music Sync
            float p = u.pulseStrength;
            pulse = 1.0 + p * 0.85;
            thick *= 1.0 + p * 0.55;
            glowR *= 1.0 + p * 0.45;
            // When audio goes quiet, settle into gentle breathing (spec §16/§17).
            float b = 0.5 + 0.5 * sin(u.idlePhase);
            pulse += u.silence * b * 0.12;
            glowR *= 1.0 + u.silence * b * 0.15;
            rot += u.idlePhase * 0.02 * u.silence;
        } else if (u.animationMode == 1) {          // Idle breathing
            float b = 0.5 + 0.5 * sin(u.idlePhase);
            pulse = 1.0 + b * 0.14;
            glowR *= 1.0 + b * 0.22;
            rot += u.idlePhase * 0.03;
        }                                           // Static: unchanged

        // Rim core + soft bloom (spec §65).
        float core = 1.0 - smoothstep(0.0, max(thick, 0.5), dist);
        float bloom = exp(-dist / glowR);
        float intensity = core + bloom * 0.85;

        // Perimeter gradient (spec §66): two-color periodic blend around the loop.
        float2 d = (pixel - center) / max(halfRes, float2(1.0));
        float ang = atan2(d.y, d.x);
        float pos = ang / (2.0 * M_PI_F) + 0.5;
        float w = 0.5 + 0.5 * cos(2.0 * M_PI_F * (pos + rot));
        w = clamp(mix(w, u.gradientMix, 0.35), 0.0, 1.0);
        float3 grad = mix(u.secondaryColor.rgb, u.primaryColor.rgb, w);

        // Notch mask (spec §67): carve the notch out of the top edge, feathered.
        float notchMask = 1.0;
        if (u.notchEnabled == 1 && u.notchHeight > 0.0) {
            float nx = abs(pixel.x - u.notchCenterX) - u.notchWidth * 0.5;
            float ny = pixel.y - u.notchHeight;
            notchMask = smoothstep(0.0, 10.0, max(nx, ny));
        }

        float alpha = clamp(intensity, 0.0, 1.0) * u.opacity * notchMask;
        float3 rgb = grad * u.brightness * pulse;
        // Premultiplied alpha output.
        return float4(rgb * alpha, alpha);
    }
    """
}
