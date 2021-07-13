#if !defined(SHADOW_SHARED)
#define SHADOW_SHARED

#include "UnityCG.cginc"

float4 _Tint;
sampler2D _MainTex;
float4 _MainTex_ST;
float _AlphaCutoff;
// Dither pattern atlas to achieve semitransparent shadows. All the different
// patterns are stored in layers of a 3D texture.
sampler3D _DitherMaskLOD;

#if defined(_RENDERING_FADE) || defined(_RENDERING_TRANSPARENT)
    // Since semitransparent shadows have strong visual limitations, only use
    // them if a specific _SEMITRANSPARENT_SHADOWS shader feature is set from
    // the material inspector. Otherwise use the cutout shadows, which are less
    // accurate but support receiving shadows and might work just fine in many cases.
    #if defined(_SEMITRANSPARENT_SHADOWS)
        #define SHADOWS_SEMITRANSPARENT 1
    #else
        #define _RENDERING_CUTOUT
    #endif
#endif

// We only need to calculate and pass the UV coordinates to the fragment
// shader (and use them to handle transparency) only when we are in one of the
// transparent rendering modes (cutout, fade or transparent)
// and we are NOT using albedo alpha for smoothness
#if SHADOWS_SEMITRANSPARENT || defined(_RENDERING_CUTOUT)
    #if !defined(_SMOOTHNESS_ALBEDO)
        #define SHADOWS_NEED_UV 1
    #endif
#endif

struct VertexData {
    float4 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
};

// A separated InterpolatorsVertex struct is needed because SV_POSITION and VPOS
// semantics, on same platforms, are mapped to the same value (not sure if it's still
// true, though). To workaround this, SV_POSITION is used in a dedicated struct for
// the vertex shader, and VPOS (if needed) is used in a different dedicated struct
// as input to the fragment shader.
struct InterpolatorsVertex {
    float4 position : SV_POSITION;
    #if SHADOWS_NEED_UV
        float2 uv : TEXCOORD0;
    #endif
    #if defined(SHADOWS_CUBE)
        float3 lightVec : TEXCOORD1;
    #endif
};

struct Interpolators {
    #if SHADOWS_SEMITRANSPARENT
        // UNITY_VPOS_TYPE macro is defined in HLSLSupport, and it's usually float4
        // except for in Direct3D 9 where is a float2
        // VPOS is a semantic that allows us to retrieve the fragment screen position,
        // needed to sample the dither pattern.
        UNITY_VPOS_TYPE vpos : VPOS;
    #else
        // This variable is not currently used in our fragment shader. However it
        // could happen that all other variables are skipped, since they are all conditioned,
        // and the compiler can't always handle empty structs. So this variable is left
        // to avoid that scenario.
        float4 position : SV_POSITION;
    #endif
    #if SHADOWS_NEED_UV
        float2 uv : TEXCOORD0;
    #endif
    #if defined(SHADOWS_CUBE)
        float3 lightVec : TEXCOORD1;
    #endif
};

float GetAlpha(Interpolators i) {
    float alpha = _Tint.a;
    #if SHADOWS_NEED_UV
        alpha *= tex2D(_MainTex, i.uv.xy).a;
    #endif
    return alpha;
}

InterpolatorsVertex MyShadowVertexProgram (VertexData v) {
    InterpolatorsVertex i;
    #if defined(SHADOWS_CUBE)
        i.position = UnityObjectToClipPos(v.position);
        i.lightVec = mul(unity_ObjectToWorld, v.position).xyz - _LightPositionRange.xyz;
    #else
        i.position = UnityClipSpaceShadowCasterPos(v.position.xyz, v.normal);
        i.position = UnityApplyLinearShadowBias(i.position);
    #endif

    #if SHADOWS_NEED_UV
        i.uv = TRANSFORM_TEX(v.uv, _MainTex);
    #endif

    return i;
}

float4 MyShadowFragmentProgram (Interpolators i) : SV_TARGET {
    float alpha = GetAlpha(i);
    #if defined(_RENDERING_CUTOUT)
        clip(alpha - _AlphaCutoff);
    #endif

    #if SHADOWS_SEMITRANSPARENT
        // To handle semitransparent shadows we sample a dither pattern texture
        // provided by Unity, which is formed by 16 4x4 patterns stored in a 3D texture.
        // to sample it we use a float3, where the first 2 coordinates are the uv
        // coordinate of a single 4x4 pattern (we use the screen space coordinate
        // for those) and the last coordinate is the index of the pattern expressed
        // as levelOfDither * (1 / 16) -> [0 (fully transparent), 9.9375 (fully opaque)].
        // 0.25 is a scaling factor for the dither pattern and it's the value used by
        // Unity Standard Shader.
        float dither = tex3D(_DitherMaskLOD, float3(i.vpos.xy * 0.25, alpha * 0.9375)).a;
        // A dither sample has alpha == 0 when a pixel should be skipped, but to
        // take possible accuracy issues we subtract 0.01.
        clip(dither - 0.01);
    #endif

    #if defined(SHADOWS_CUBE)
        float depth = length(i.lightVec) + unity_LightShadowBias.x;
        depth *= _LightPositionRange.w;
        return UnityEncodeCubeShadowDepth(depth);
    #else
        return 0;
    #endif
}

#endif