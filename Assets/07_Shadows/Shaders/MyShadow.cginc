#if !defined(MY_SHADOW_INCLUDED)
#define MY_SHADOW_INCLUDED

#include "UnityCG.cginc"

struct VertexData {
    float4 position : POSITION;
    float3 normal : NORMAL;
};

// Specific behaviour for point lights: since point lights have to render their
// shadow maps in all 6 directions and Unity doesn't support depth cubemaps,
// Unity provides a way to store the depth value in a texture
#if defined(SHADOWS_CUBE)
struct Interpolators {
    float4 position : SV_POSITION;
    float3 lightVec : TEXCOORD0;
};

Interpolators MyShadowVertexProgram (VertexData v) {
    Interpolators i;
    i.position = UnityObjectToClipPos(v.position);
    // _LightPositionRange contains the light position in xyz and the inverse of
    // the light range in w.
    i.lightVec = mul(unity_ObjectToWorld, v.position).xyz - _LightPositionRange.xyz;
    return i;
}

float4 MyShadowFragmentProgram (Interpolators i) : SV_TARGET {
    // Bias helps dealing with shadow acne and is embedded in the light settings
    float depth = length(i.lightVec) + unity_LightShadowBias.x;
    // To ensure that the depth value fits in 0-1 range, we multiply it by
    // _LightPositionRange.w, which is the inverse of the light range (max distance
    // of the light)
    depth *= _LightPositionRange.w;
    // store the depth value in each channel or encode it using a dedicated algorithm
    return UnityEncodeCubeShadowDepth(depth);
}
#else
float4 MyShadowVertexProgram (VertexData v) : SV_POSITION {
    float4 position = UnityClipSpaceShadowCasterPos(v.position.xyz, v.normal);
    // Bias helps dealing with shadow acne and is embedded in the light settings
    return UnityApplyLinearShadowBias(position);
}

half4 MyShadowFragmentProgram () : SV_TARGET {
    return 0;
}
#endif

#endif