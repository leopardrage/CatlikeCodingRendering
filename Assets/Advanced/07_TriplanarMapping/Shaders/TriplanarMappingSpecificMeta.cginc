﻿#if !defined(META_SHARED)
#define META_SHARED

#include "TriplanarMappingInputIncludedShared.cginc"
#include "UnityMetaPass.cginc"

Interpolators MyLightmappingVertexProgram(VertexData v) {
    Interpolators i;
    i.pos = UnityMetaVertexPosition(
        v.vertex, v.uv1, v.uv2, unity_LightmapST, unity_DynamicLightmapST
    );

    #if defined(META_PASS_NEEDS_NORMALS)
        i.normal = UnityObjectToWorldNormal(v.normal);
    #else
        i.normal = float3(0, 1, 0);
    #endif

    #if defined(META_PASS_NEEDS_POSITION)
        i.worldPos.xyz = mul(unity_ObjectToWorld, v.vertex);
    #else
        i.worldPos.xyz = 0;
    #endif

    #if !defined(NO_DEFAULT_UV)
        i.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
        i.uv.zw = TRANSFORM_TEX(v.uv, _DetailTex);
    #endif
    
    return i;
}

#if !defined(ALBEDO_FUNCTION)
    #define ALBEDO_FUNCTION GetAlbedo
#endif

float4 MyLightmappingFragmentProgram(Interpolators i) : SV_TARGET {

    SurfaceData surface;
    #if defined(SURFACE_FUNCTION)
        surface.normal = i.normal;
        surface.albedo = 1;
        surface.alpha = 1;
        surface.emission = 0;
        surface.metallic = 0;
        surface.occlusion = 1;
        surface.smoothness = 0.5;

        SurfaceParameters sp;
        sp.normal = i.normal;
        sp.position = i.worldPos.xyz;
        sp.uv = UV_FUNCTION(i);

        SURFACE_FUNCTION(surface, sp);
    #else
        surface.normal = i.normal;
        surface.albedo = ALBEDO_FUNCTION(i);
        surface.alpha = GetAlpha(i);
        surface.emission = GetEmission(i);
        surface.metallic = GetMetallic(i);
        surface.occlusion = GetOcclusion(i);
        surface.smoothness = GetSmoothness(i);
    #endif

    UnityMetaInput surfaceData;
    surfaceData.Emission = surface.emission;
    float oneMinusReflectivity;
    surfaceData.Albedo = DiffuseAndSpecularFromMetallic(
        surface.albedo,
        surface.metallic,
        surfaceData.SpecularColor,
        oneMinusReflectivity
    );
    float roughness = SmoothnessToRoughness(surface.smoothness) * 0.5;
    surfaceData.Albedo += surfaceData.SpecularColor * roughness;
    return UnityMetaFragment(surfaceData);
}

#endif