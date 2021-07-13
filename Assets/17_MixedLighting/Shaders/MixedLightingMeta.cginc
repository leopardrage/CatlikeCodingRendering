#if !defined(MIXED_LIGHTING_META)
#define MIXED_LIGHTING_META

#include "UnityPBSLighting.cginc"
#include "UnityMetaPass.cginc"

float4 _Color;
sampler2D _MainTex;
float4 _MainTex_ST;

sampler2D _MetallicMap;
float _Metallic;
float _Smoothness;

sampler2D _DetailTex;
float4 _DetailTex_ST;

sampler2D _EmissionMap;
float3 _Emission;

sampler2D _DetailMask;

struct VertexData {
    // Since we overright this variable's components, I think that the POSITION
    // Semantic is kept just for shader compilation requirements.
    float4 vertex : POSITION;
    float2 uv : TEXCOORD0;
    // Lightmap uv coordinates
    float2 uv1 : TEXCOORD1;
};

struct Interpolators {
    float4 pos : SV_POSITION;
    float4 uv : TEXCOORD0;
};

float GetDetailMask(Interpolators i) {
    #if defined(_DETAIL_MASK)
        return tex2D(_DetailMask, i.uv.xy).a;
    #else
        return 1;
    #endif
}

float3 GetAlbedo(Interpolators i) {
    float3 albedo = tex2D(_MainTex, i.uv.xy).rgb * _Color.rgb;
    #if defined(_DETAIL_ALBEDO_MAP)
        float3 details = tex2D(_DetailTex, i.uv.zw) * unity_ColorSpaceDouble;
        albedo = lerp(albedo, albedo * details, GetDetailMask(i));
    #endif
    return albedo;
}

float GetMetallic(Interpolators i) {
    #if defined(_METALLIC_MAP)
    return tex2D(_MetallicMap, i.uv.xy).r;
    #else
    return _Metallic;
    #endif
}

float GetSmoothness(Interpolators i) {
    float smoothness = 1;
    #if defined(_SMOOTHNESS_ALBEDO)
    smoothness = tex2D(_MainTex, i.uv.xy).a;
    #elif defined(_SMOOTHNESS_METALLIC) && defined(_METALLIC_MAP)
    smoothness = tex2D(_MetallicMap, i.uv.xy).a;
    #endif
    return smoothness * _Smoothness;
}

float3 GetEmission(Interpolators i) {
    #if defined(_EMISSION_MAP)
        return tex2D(_EmissionMap, i.uv.xy) * _Emission;
    #else
        return _Emission;
    #endif
}

Interpolators MyLightmappingVertexProgram(VertexData v) {
    Interpolators i;
    // We aren't rendering for the camera, but for the lightmap. So the goal
    // is to associate colors with an object's texture unwrap (lightmap-subregion)
    // in the lightmap. This means we have to replace the vertex value with the
    // lightmap "absolute" uvs for the object, so that we render on a quad representing
    // the lightmap.
    v.vertex.xy = v.uv1 * unity_LightmapST.xy + unity_LightmapST.zw;
    // The z value won't be used, but to make this work on all machine we have
    // to provide dummy values for values greater then zero. Here we are using the
    // same values used by Unity Standard Shader (the specific need of the > 0
    // branch is a mystery, but also a not-so-interesting mystery, so
    // let's just get over it)
    v.vertex.z = v.vertex.z > 0 ? 0.0001 : 0;
    i.pos = UnityObjectToClipPos(v.vertex);

    i.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
    i.uv.zw = TRANSFORM_TEX(v.uv, _DetailTex);

    return i;
}

float4 MyLightmappingFragmentProgram(Interpolators i) : SV_TARGET {
    // We have to output on the lightmap both the Albedo and the Emissive values.
    // Unity does this with two separate passes, in which we fill both values to
    // a specific UnityMetaInput structure and use the UnityMetaFragment to allow
    // Unity to pick the relevant value for the corresponding pass and encode it
    // appropriately (sounds low performance, but since we are rendering offline
    // I think it's fine).
    // UnityMetaInput also need a SpecularColor value, but it's just used for
    // some Editor visualization, not for actual rendering.
    UnityMetaInput surfaceData;
    surfaceData.Emission = GetEmission(i);
    float oneMinusReflectivity;
    surfaceData.Albedo = DiffuseAndSpecularFromMetallic(
        GetAlbedo(i),
        GetMetallic(i),
        surfaceData.SpecularColor,
        oneMinusReflectivity
    );
    // This is meant to fix indirect contribution for very rough metals, which have
    // to produce more indirect light than the originally computed value.
    float roughness = SmoothnessToRoughness(GetSmoothness(i)) * 0.5;
    surfaceData.Albedo += surfaceData.SpecularColor * roughness;
    // NOOOOTTTTEEE: Indirect light can be completely cut off if in some weird scenarios.
    // A painful example is having a building with a roof where, if the roof is 6.25 x 6.25
    // indirect light is fine, while if it is 7x7 indirect light vanishes. This at least
    // is how it goes for the deprecated Enlighten mode, used by the tutorial. Progressive
    // CPU, the current standard, works BAD in both cases (at least is consistent... :().
    return UnityMetaFragment(surfaceData);
}

#endif