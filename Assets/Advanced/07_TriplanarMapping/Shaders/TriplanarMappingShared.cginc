﻿// Upgrade NOTE: upgraded instancing buffer 'InstanceProperties' to new syntax.

#if !defined(TRIPLANAR_MAPPING_SHARED)
#define TRIPLANAR_MAPPING_SHARED

#include "TriplanarMappingInputIncludedShared.cginc"

#if !defined(ALBEDO_FUNCTION)
    #define ALBEDO_FUNCTION GetAlbedo
#endif

void ComputeVertexLightColor (inout InterpolatorsVertex i) {
    #if defined(VERTEXLIGHT_ON)
    i.vertexLightColor = Shade4PointLights(
        unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
        unity_LightColor[0].rgb, unity_LightColor[1].rgb,
        unity_LightColor[2].rgb, unity_LightColor[3].rgb,
        unity_4LightAtten0, i.worldPos.xyz, i.normal);
    #endif
}

float3 CreateBinormal (float3 normal, float3 tangent, float binormalSign) {
    float3 binormal = cross(normal, tangent.xyz) * binormalSign;
    binormal *= unity_WorldTransformParams.w;
    return binormal;
}

InterpolatorsVertex MyVertexProgram (VertexData v) {
    InterpolatorsVertex i;
    // GPU Instancing stuff
    UNITY_INITIALIZE_OUTPUT(InterpolatorsVertex, i);
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_TRANSFER_INSTANCE_ID(v, i);

    // Must skip all uv-related logic when standard uvs are not available.
    #if !defined(NO_DEFAULT_UV)
        // Since we are about to sample the displacement map to apply surface
        // displacement, uvs must be tranformed here, before they are use, if
        // we want to support texture scaling and offsetting.
        i.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
        i.uv.zw = TRANSFORM_TEX(v.uv, _DetailTex);

        // If we are applying surface displacement
        #if VERTEX_DISPLACEMENT
            // We are obviously applying vertex displacement in object space.
            // Just to remind you that.

            // Since we are in the vertex program, no screen space derivatives are
            // availables (they are only availables in the fragment program), so
            // the GPU cannot know which MipMap level to use. So we cannot use the
            // regular tex2D function for sampling, but we must use tex2Dlod, which
            // additionally takes an unused third coordinate value and a lod value.
            // Setting the letter to 0 tells the GPU not to use any mipmap.
            // We read the Green channel, because it was the channel used by the
            // underlying parallax map.
            float displacement = tex2Dlod(_DisplacementMap, float4(i.uv.xy, 0, 0)).g;
            // By offsetting the original value by 0.5, we are setting the "no change"
            // value to 0.5, allowing us to move up and down for values greater and lesser
            // than 0.5, respectively.
            // We also apply the displacement strength property
            displacement = (displacement - 0.5) * _DisplacementStrength;
            // Since we assume that this function is called after tessellation,
            // we cannot be sure that the current normal is a unit vector (it can
            // be a newly created vertex resulting the interpolation of vertices that
            // have different normals, like what happens for spheres), so we have to
            // normalize the normal vector.
            v.normal = normalize(v.normal);
            // We displace the vertex along its normal, as a valid displacement orientation
            // for all mesh orientations.
            v.vertex.xyz += v.normal * displacement;
        #endif
    #endif

    #if defined(LIGHTMAP_ON) || ADDITIONAL_MASKED_DIRECTIONAL_SHADOWS
        i.lightmapUV = v.uv1 * unity_LightmapST.xy + unity_LightmapST.zw;
    #endif

    #if defined(DYNAMICLIGHTMAP_ON)
        i.dynamicLightmapUV = 
            v.uv2 * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
    #endif

    i.pos = UnityObjectToClipPos(v.vertex);
    i.worldPos.xyz = mul(unity_ObjectToWorld, v.vertex);
    #if FOG_DEPTH
        i.worldPos.w = i.pos.z;
    #endif
    i.normal = UnityObjectToWorldNormal(v.normal);

    #if REQUIRES_TANGENT_SPACE
        #if defined(BINORMAL_PER_FRAGMENT)
        i.tangent = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
        #else
        i.tangent = UnityObjectToWorldDir(v.tangent.xyz);
        i.binormal = CreateBinormal(i.normal, i.tangent, v.tangent.w);
        #endif
    #endif

    UNITY_TRANSFER_SHADOW(i, v.uv1);
    
    ComputeVertexLightColor(i);

    #if defined(_PARALLAX_MAP)

        #if defined(PARALLAX_SUPPORT_SCALED_DYNAMIC_BATCHING)
            v.tangent.xyz = normalize(v.tangent.xyz);
            v.normal = normalize(v.normal);
        #endif
        
        float3x3 objectToTangent = float3x3(
            v.tangent.xyz,
            cross(v.normal, v.tangent.xyz) * v.tangent.w,
            v.normal
        );
        i.tangentViewDir = mul(objectToTangent, ObjSpaceViewDir(v.vertex));
    #endif

    return i;
}

float4 ApplyFog(float4 color, Interpolators i) {
    #if FOG_ON
        float viewDistance = length(_WorldSpaceCameraPos - i.worldPos.xyz);
        #if FOG_DEPTH
            viewDistance = UNITY_Z_0_FAR_FROM_CLIPSPACE(i.worldPos.w);
        #endif
        UNITY_CALC_FOG_FACTOR_RAW(viewDistance);
        float3 fogColor = 0;
        #if defined(FORWARD_BASE_PASS)
            fogColor = unity_FogColor.rgb;
        #endif
        color.rgb = lerp(fogColor, color.rgb, saturate(unityFogFactor));
    #endif
    return color;
}

float FadeShadows(Interpolators i, float attenuation) {
    #if HANDLE_SHADOWS_BLENDING_IN_GI || ADDITIONAL_MASKED_DIRECTIONAL_SHADOWS
        #if ADDITIONAL_MASKED_DIRECTIONAL_SHADOWS
            attenuation = SHADOW_ATTENUATION(i);
        #endif


        float viewZ = dot(_WorldSpaceCameraPos - i.worldPos, UNITY_MATRIX_V[2].xyz);
        float shadowFadeDistance = UnityComputeShadowFadeDistance(i.worldPos, viewZ);
        float shadowFade = UnityComputeShadowFade(shadowFadeDistance);
        float bakedAttenuation = UnitySampleBakedOcclusion(i.lightmapUV, i.worldPos);
        attenuation = UnityMixRealtimeAndBakedShadows(
            attenuation, bakedAttenuation, shadowFade
            );
    #endif
    return attenuation;
}

void ApplySubtractiveLighting (Interpolators i, inout UnityIndirect indirectLight) {
    #if SUBTRACTIVE_LIGHTING
        UNITY_LIGHT_ATTENUATION(attenuation, i, i.worldPos.xyz);
        attenuation = FadeShadows(i, attenuation);
        float ndotl = saturate(dot(i.normal, _WorldSpaceLightPos0.xyz));
        float3 shadowedLightEstimate = ndotl * (1 - attenuation) * _LightColor0.rgb;
        float3 subtractedLight = indirectLight.diffuse - shadowedLightEstimate;
        subtractedLight = max(subtractedLight, unity_ShadowColor.rgb);
        subtractedLight = lerp(subtractedLight, indirectLight.diffuse, _LightShadowData.x);
        indirectLight.diffuse = min(subtractedLight, indirectLight.diffuse);
    #endif
}

float2 ParallaxOffset (float2 uv, float2 viewDir) {
    float height = GetParallaxHeight(uv);
    height -= 0.5;
    height *= _ParallaxStrength;
    return viewDir * height;
}

float2 ParallaxRaymarching (float2 uv, float2 viewDir) {
    #if !defined(PARALLAX_RAYMARCHING_STEPS)
        #define PARALLAX_RAYMARCHING_STEPS 10
    #endif

    float2 uvOffset = 0;
    float stepSize = 1.0 / PARALLAX_RAYMARCHING_STEPS;
    float2 uvDelta = viewDir * stepSize;
    uvDelta *= _ParallaxStrength;
    float stepHeight = 1;
    float surfaceHeight = GetParallaxHeight(uv);

    float2 prevUVOffset = uvOffset;
    float prevStepHeight = stepHeight;
    float prevSurfaceHeight = surfaceHeight;

    for (int i = 1; i < PARALLAX_RAYMARCHING_STEPS && stepHeight > surfaceHeight; i++) {
        prevUVOffset = uvOffset;
        prevStepHeight = stepHeight;
        prevSurfaceHeight = surfaceHeight;
        uvOffset -= uvDelta;
        stepHeight -= stepSize;
        surfaceHeight = GetParallaxHeight(uv + uvOffset);
    }

    #if !defined(PARALLAX_RAYMARCHING_SEARCH_STEPS)
        #define PARALLAX_RAYMARCHING_SEARCH_STEPS 0
    #endif

    #if PARALLAX_RAYMARCHING_SEARCH_STEPS > 0
        for (int j = 0; j < PARALLAX_RAYMARCHING_SEARCH_STEPS; j++) {
            uvDelta *= 0.5;
            stepSize *= 0.5;

            if (stepHeight < surfaceHeight) {
                uvOffset += uvDelta;
                stepHeight += stepSize;
            } else {
                uvOffset -= uvDelta;
                stepHeight -= stepSize;
            }
            surfaceHeight = GetParallaxHeight(uv + uvOffset);
        }
    #elif defined(PARALLAX_RAYMARCHING_INTERPOLATE)
        float prevDifference = prevStepHeight - prevSurfaceHeight;
        float difference = surfaceHeight - stepHeight;
        float t = prevDifference / (prevDifference + difference);
        uvOffset = prevUVOffset - uvDelta * t;
    #endif

    return uvOffset;
}

void ApplyParallax (inout Interpolators i) {
    // Parallax effect is not applicable if standard UVs are not available.
    #if defined(_PARALLAX_MAP) && !defined(NO_DEFAULT_UV)
        i.tangentViewDir = normalize(i.tangentViewDir);
        #if !defined(PARALLAX_OFFSET_LIMITING)
            #if !defined(PARALLAX_BIAS)
                #define PARALLAX_BIAS 0.42
            #endif
            i.tangentViewDir.xy /= (i.tangentViewDir.z + PARALLAX_BIAS);
        #endif

        #if !defined(PARALLAX_FUNCTION)
            #define PARALLAX_FUNCTION ParallaxOffset
        #endif
        float2 uvOffset = PARALLAX_FUNCTION(i.uv.xy, i.tangentViewDir.xy);
        i.uv.xy += uvOffset;
        i.uv.zw += uvOffset * (_DetailTex_ST.xy / _MainTex_ST.xy);
    #endif
}

float3 BoxProjection (
    float3 direction,
    float3 position,
    float4 cubemapPosition,
    float3 boxMin,
    float3 boxMax) {
        #if UNITY_SPECCUBE_BOX_PROJECTION
        UNITY_BRANCH
        if (cubemapPosition.w > 0) {
            float3 factors = ((direction > 0 ? boxMax : boxMin) - position) / direction;
            float scalar = min(min(factors.x, factors.y), factors.z);
            direction = direction * scalar + position - cubemapPosition;
        }
        #endif
        return direction;
    }

UnityLight CreateLight (Interpolators i) {
    UnityLight light;
    #if defined(DEFERRED_PASS) || SUBTRACTIVE_LIGHTING
        light.dir = float3(0, 1, 0);
        light.color = 0;
    #else
        #if defined(POINT) || defined(POINT_COOKIE) || defined(SPOT)
            // Point Light
            light.dir = normalize(_WorldSpaceLightPos0.xyz - i.worldPos.xyz);
        #else
            // Directional Light
            light.dir = _WorldSpaceLightPos0.xyz;
        #endif
        
        UNITY_LIGHT_ATTENUATION(attenuation, i, i.worldPos.xyz)
        attenuation = FadeShadows(i, attenuation);
        light.color = _LightColor0.rgb * attenuation;
    #endif
    return light;
}

UnityIndirect CreateIndirectLight (Interpolators i, float3 viewDir, SurfaceData surface) {
    UnityIndirect indirectLight;
    indirectLight.diffuse = 0;
    indirectLight.specular = 0;

    #if defined(VERTEXLIGHT_ON)
        indirectLight.diffuse = i.vertexLightColor;
    #endif

    #if defined(FORWARD_BASE_PASS) || defined(DEFERRED_PASS)
        #if defined(LIGHTMAP_ON)
            indirectLight.diffuse = 
                DecodeLightmap(UNITY_SAMPLE_TEX2D(unity_Lightmap, i.lightmapUV));
            #if defined(DIRLIGHTMAP_COMBINED)
                float4 lightmapDirection = UNITY_SAMPLE_TEX2D_SAMPLER(
                    unity_LightmapInd, unity_Lightmap, i.lightmapUV
                );
                indirectLight.diffuse = DecodeDirectionalLightmap(
                    indirectLight.diffuse, lightmapDirection, i.normal
                );  
            #endif
            ApplySubtractiveLighting(i, indirectLight);
        #endif

        #if defined(DYNAMICLIGHTMAP_ON)
            float3 dynamicLightDiffuse = DecodeRealtimeLightmap(
                UNITY_SAMPLE_TEX2D(unity_DynamicLightmap, i.dynamicLightmapUV)
            );
            #if defined(DIRLIGHTMAP_COMBINED)
                float4 dynamicLightmapDirection = UNITY_SAMPLE_TEX2D_SAMPLER(
                    unity_DynamicDirectionality,
                    unity_DynamicLightmap,
                    i.dynamicLightmapUV
                );
                indirectLight.diffuse += DecodeDirectionalLightmap(
                    dynamicLightDiffuse, dynamicLightmapDirection, i.normal
                );  
            #else
                indirectLight.diffuse += dynamicLightDiffuse;
            #endif
        #endif

        #if !defined(LIGHTMAP_ON) && !defined(DYNAMICLIGHTMAP_ON)
            #if UNITY_LIGHT_PROBE_PROXY_VOLUME
                if (unity_ProbeVolumeParams.x == 1) {
                    indirectLight.diffuse = SHEvalLinearL0L1_SampleProbeVolume(
                        float4(i.normal, 1), i.worldPos
                    );
                    indirectLight.diffuse = max(0, indirectLight.diffuse);
                    #if defined(UNITY_COLORSPACE_GAMMA)
                        indirectLight.diffuse = LinearToGammaSpace(indirectLight.diffuse);
                    #endif
                } else {
                    indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));    
                }
            #else
                indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));
            #endif
        #endif

        float3 reflectionDir = reflect(-viewDir, i.normal);
        Unity_GlossyEnvironmentData envData;
        envData.roughness = 1 - surface.smoothness;
        envData.reflUVW = BoxProjection(
            reflectionDir, i.worldPos.xyz,
            unity_SpecCube0_ProbePosition,
            unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax
        );
        float3 probe0 = Unity_GlossyEnvironment(
            UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData
        );
        #if UNITY_SPECCUBE_BLENDING
            float interpolator = unity_SpecCube0_BoxMin.w;
            UNITY_BRANCH
            if (interpolator < 0.99999) {
                envData.reflUVW = BoxProjection(
                    reflectionDir, i.worldPos.xyz,
                    unity_SpecCube1_ProbePosition,
                    unity_SpecCube1_BoxMin, unity_SpecCube1_BoxMax
                );
                float3 probe1 = Unity_GlossyEnvironment(
                    UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1, unity_SpecCube0),
                    unity_SpecCube1_HDR,
                    envData
                );
                indirectLight.specular = lerp(probe1, probe0, interpolator);
            } else {
                indirectLight.specular = probe0;
            }
        #else
            indirectLight.specular = probe0;
        #endif

        // Self Occlusion
        float occlusion = surface.occlusion;
        indirectLight.diffuse *= occlusion;
        indirectLight.specular *= occlusion;
        #if defined(DEFERRED_PASS) && UNITY_ENABLE_REFLECTION_BUFFERS
            indirectLight.specular = 0;
        #endif
    #endif

    return indirectLight;
}

void InitializeFragmentNormal(inout Interpolators i) {
    #if REQUIRES_TANGENT_SPACE
        float3 tangentSpaceNormal = GetTangentSpaceNormal(i);

        #if defined(BINORMAL_PER_FRAGMENT)
        float3 binormal = CreateBinormal(i.normal, i.tangent.xyz, i.tangent.w);
        #else
        float3 binormal = i.binormal;
        #endif

        i.normal = normalize(
            tangentSpaceNormal.x * i.tangent +
            tangentSpaceNormal.y * binormal +
            tangentSpaceNormal.z * i.normal
        );
    #else
        i.normal = normalize(i.normal);
    #endif
}

struct FragmentOutput {
    #if defined(DEFERRED_PASS)
        float4 gBuffer0 : SV_Target0;
        float4 gBuffer1 : SV_Target1;
        float4 gBuffer2 : SV_Target2;
        float4 gBuffer3 : SV_Target3;
        #if defined(SHADOWS_SHADOWMASK) && (UNITY_ALLOWED_MRT_COUNT > 4)
            float4 gBuffer4 : SV_Target4;
        #endif
    #else
        float4 color : SV_Target;
    #endif
};

FragmentOutput MyFragmentProgram (Interpolators i) {
    UNITY_SETUP_INSTANCE_ID(i);
    #if defined(LOD_FADE_CROSSFADE)
        UnityApplyDitherCrossFade(i.vpos);
    #endif
    
    ApplyParallax(i);

    // Applied Normal mapping
    InitializeFragmentNormal(i);

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
    // Since SURFACE_FUNCTION, if defined, could change the current normal,
    // we write it back to i.normal to keep the normal vector consistent across
    // calculations
    i.normal = surface.normal;

    float alpha = surface.alpha;
    #if defined(_RENDERING_CUTOUT)
        clip(alpha - _Cutoff);
    #endif

    float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos.xyz);
    
    // Metallic flow logic
    float3 specularTint;
    float oneMinusReflectivity;
    float3 albedo = DiffuseAndSpecularFromMetallic(
        surface.albedo,
        surface.metallic,
        specularTint,
        oneMinusReflectivity
    );

    #if defined(_RENDERING_TRANSPARENT)
        albedo *= alpha;
        alpha = 1 - oneMinusReflectivity + alpha * oneMinusReflectivity;
    #endif

    float4 color = UNITY_BRDF_PBS(
        albedo,
        specularTint,
        oneMinusReflectivity,
        surface.smoothness,
        i.normal,
        viewDir,
        CreateLight(i),
        CreateIndirectLight(i, viewDir, surface)
    );
    color.rgb += surface.emission;

    #if defined(_RENDERING_FADE) || defined(_RENDERING_TRANSPARENT)
        color.a = alpha;
    #endif

    FragmentOutput output;
    #if defined(DEFERRED_PASS)
        #if !defined(UNITY_HDR_ON)
            color.rgb = exp2(-color.rgb);
        #endif
        output.gBuffer0.rgb = albedo;
        output.gBuffer0.a = surface.occlusion;
        output.gBuffer1.rgb = specularTint;
        output.gBuffer1.a = surface.smoothness;
        output.gBuffer2 = float4(i.normal * 0.5 + 0.5, 1);
        output.gBuffer3 = color;

        #if defined(SHADOWS_SHADOWMASK) && (UNITY_ALLOWED_MRT_COUNT > 4)
            float2 shadowUV = 0;
            #if defined(LIGHTMAP_ON)
                shadowUV = i.lightmapUV;
            #endif
            output.gBuffer4 = UnityGetRawBakedOcclusions(shadowUV, i.worldPos.xyz);
        #endif
    #else
        output.color = ApplyFog(color, i);
    #endif
    return output;
}

#endif