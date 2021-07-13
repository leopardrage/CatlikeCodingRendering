// Upgrade NOTE: upgraded instancing buffer 'InstanceProperties' to new syntax.

#if !defined(PARALLAX_SHARED)
#define PARALLAX_SHARED

#include "UnityPBSLighting.cginc"
#include "AutoLight.cginc"

#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
    #if !defined(FOG_DISTANCE)
        #define FOG_DEPTH 1
    #endif
    #define FOG_ON 1
#endif

#if !defined(LIGHTMAP_ON) && defined(SHADOWS_SCREEN)
    #if defined(SHADOWS_SHADOWMASK) && !defined(UNITY_NO_SCREENSPACE_SHADOWS)
        #define ADDITIONAL_MASKED_DIRECTIONAL_SHADOWS 1
    #endif
#endif

#if defined(LIGHTMAP_ON) && defined(SHADOWS_SCREEN)
    #if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK)
        #define SUBTRACTIVE_LIGHTING 1
    #endif
#endif

UNITY_INSTANCING_BUFFER_START(InstanceProperties)
    UNITY_DEFINE_INSTANCED_PROP(float4, _Color)
#define _Color_arr InstanceProperties
UNITY_INSTANCING_BUFFER_END(InstanceProperties)
sampler2D _MainTex;
float4 _MainTex_ST;

sampler2D _MetallicMap;
float _Metallic;
float _Smoothness;

sampler2D _NormalMap;
float _BumpScale;

sampler2D _DetailTex;
float4 _DetailTex_ST;

sampler2D _DetailNormalMap;
float _DetailBumpScale;

sampler2D _EmissionMap;
float3 _Emission;

sampler2D _ParallaxMap;
float _ParallaxStrength;

sampler2D _OcclusionMap;
float _OcclusionStrength;

sampler2D _DetailMask;

float _Cutoff;

struct VertexData {
    UNITY_VERTEX_INPUT_INSTANCE_ID
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 uv : TEXCOORD0;
    // Baked Lightmap uv coordinates
    float2 uv1 : TEXCOORD1;
    // Realtime Lightmap uv coordinates
    float2 uv2 : TEXCOORD2;
};

// Different interpolators are used for vertex program and fragment program,
// because we need screen coordinates when dealing with cross-fading LODs.
struct InterpolatorsVertex {
    UNITY_VERTEX_INPUT_INSTANCE_ID
    float4 pos : SV_POSITION;
    float4 uv : TEXCOORD0;
    float3 normal : TEXCOORD1;

    #if defined(BINORMAL_PER_FRAGMENT)
        float4 tangent : TEXCOORD2;
    #else
        float3 tangent : TEXCOORD2;
        float3 binormal : TEXCOORD3;
    #endif
    #if FOG_DEPTH
        float4 worldPos : TEXCOORD4;
    #else
        float3 worldPos : TEXCOORD4;
    #endif

    UNITY_SHADOW_COORDS(5)

    #if defined(VERTEXLIGHT_ON)
        float3 vertexLightColor : TEXCOORD6;
    #endif

    #if defined(LIGHTMAP_ON) || ADDITIONAL_MASKED_DIRECTIONAL_SHADOWS
        float2 lightmapUV : TEXCOORD6;
    #endif

    #if defined(DYNAMICLIGHTMAP_ON)
        float2 dynamicLightmapUV : TEXCOORD7;
    #endif

    #if defined(_PARALLAX_MAP)
        float3 tangentViewDir : TEXCOORD8;
    #endif
};

struct Interpolators {
    UNITY_VERTEX_INPUT_INSTANCE_ID

    #if defined(LOD_FADE_CROSSFADE)
        UNITY_VPOS_TYPE vpos : VPOS;
    #else
        float4 pos : SV_POSITION;
    #endif
    float4 uv : TEXCOORD0;
    float3 normal : TEXCOORD1;

    #if defined(BINORMAL_PER_FRAGMENT)
        float4 tangent : TEXCOORD2;
    #else
        float3 tangent : TEXCOORD2;
        float3 binormal : TEXCOORD3;
    #endif
    #if FOG_DEPTH
        float4 worldPos : TEXCOORD4;
    #else
        float3 worldPos : TEXCOORD4;
    #endif

    UNITY_SHADOW_COORDS(5)

    #if defined(VERTEXLIGHT_ON)
        float3 vertexLightColor : TEXCOORD6;
    #endif

    #if defined(LIGHTMAP_ON) || ADDITIONAL_MASKED_DIRECTIONAL_SHADOWS
        float2 lightmapUV : TEXCOORD6;
    #endif

    #if defined(DYNAMICLIGHTMAP_ON)
        float2 dynamicLightmapUV : TEXCOORD7;
    #endif

    #if defined(_PARALLAX_MAP)
        float3 tangentViewDir : TEXCOORD8;
    #endif
};

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

    i.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
    i.uv.zw = TRANSFORM_TEX(v.uv, _DetailTex);

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
    #if defined(BINORMAL_PER_FRAGMENT)
    i.tangent = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
    #else
    i.tangent = UnityObjectToWorldDir(v.tangent.xyz);
    i.binormal = CreateBinormal(i.normal, i.tangent, v.tangent.w);
    #endif

    UNITY_TRANSFER_SHADOW(i, v.uv1);
    
    ComputeVertexLightColor(i);

    #if defined(_PARALLAX_MAP)

        #if defined(PARALLAX_SUPPORT_SCALED_DYNAMIC_BATCHING)
            // Normalize tangent and normal in case dynamic batching is used which,
            // causes those vectors to be not already normalized as they should be,
            // most likely due to performance reasons in the dynamic batching logic.
            // Note that this seems to be an issue only in older versions of Unity,
            // since in Unity 2020.2.1f the expected warp issue for close overlapping
            // meshes doesn't show up.
            // Remember that we actually need unit vectors to form a transformation
            // matrix...
            v.tangent.xyz = normalize(v.tangent.xyz);
            v.normal = normalize(v.normal);
        #endif

        // To calculate parallax we need to make tangent-space view-direction available
        // in the fragment shader.
        // To achieve this in an optimized way, we calculate the object-to-tangent
        // transformation matrix with tangent, normal and the derived binormal
        // and we convert the view direction here, so we can avoid to calculate it
        // per-fragment.
        // However, we cannot avoid to normalize it in the fragment shader before use,
        // due to linear interpolation.
        float3x3 objectToTangent = float3x3(
            v.tangent.xyz,
            // Remember, v.tangent.w is the sign for the binormal (has 1 or -1 values)
            cross(v.normal, v.tangent.xyz) * v.tangent.w,
            v.normal
        );
        // ObjSpaceViewDir, defined in UnityCG, returns the direction vector (in object
        // space) from a given point (in object space) to the camera (it just converts
        // the camera position into object space and subtract the given position).
        // By giving it our vertex position (in object space by definition) we get
        // the direction from the current vertex to the camera position in object space.
        i.tangentViewDir = mul(objectToTangent, ObjSpaceViewDir(v.vertex));
    #endif

    return i;
}

float GetDetailMask(Interpolators i) {
    #if defined(_DETAIL_MASK)
        return tex2D(_DetailMask, i.uv.xy).a;
    #else
        return 1;
    #endif
}

float3 GetAlbedo(Interpolators i) {
    float3 albedo = tex2D(_MainTex, i.uv.xy).rgb * UNITY_ACCESS_INSTANCED_PROP(InstanceProperties, _Color).rgb;
    #if defined(_DETAIL_ALBEDO_MAP)
        float3 details = tex2D(_DetailTex, i.uv.zw) * unity_ColorSpaceDouble;
        albedo = lerp(albedo, albedo * details, GetDetailMask(i));
    #endif
    return albedo;
}

float GetAlpha(Interpolators i) {
    float alpha = UNITY_ACCESS_INSTANCED_PROP(InstanceProperties, _Color).a;
    #if !defined(_SMOOTHNESS_ALBEDO)
        alpha *= tex2D(_MainTex, i.uv.xy).a;
    #endif
    return alpha;
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
    #if defined(FORWARD_BASE_PASS) || defined(DEFERRED_PASS)
        #if defined(_EMISSION_MAP)
            return tex2D(_EmissionMap, i.uv.xy) * _Emission;
        #else
            return _Emission;
        #endif
    #else
        return 0;
    #endif
}

float GetOcclusion(Interpolators i) {
    #if defined(_OCCLUSION_MAP)
        return lerp(1, tex2D(_OcclusionMap, i.uv.xy).g, _OcclusionStrength);
    #else
        return 1;
    #endif
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

float GetParallaxHeight (float2 uv) {
    // Height data is supposed to be stored in the G channel (just like
    // occlusion maps).
    return tex2D(_ParallaxMap, uv).g;
}

// Simple Parallax Offset algorithm. Pretty fast but unsuitable for parallax
// maps with large and/or quick height variations. It's the only parallax offset
// algorithm supported in Unity Standard Shader.
float2 ParallaxOffset (float2 uv, float2 viewDir) {
    // The lowest and highest areas would be 0 and 1 respectively on the parallax
    // map. However we want lower parts to go below the surface level, and higher
    // parts to go above it. To achieve that, we translate to a [-0.5, 0.5] range.
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
    // We could multiply _ParallaxStrength for each height sample, as we do for
    // the simple offset algorith, but multiply it for the UV delta has the same
    // effect and we have to do it only once (little cheaper).
    uvDelta *= _ParallaxStrength;
    float stepHeight = 1;
    float surfaceHeight = GetParallaxHeight(uv);

    // These are for an optimization variant. Check the for loop for details.
    float2 prevUVOffset = uvOffset;
    float prevStepHeight = stepHeight;
    float prevSurfaceHeight = surfaceHeight;

    // For simplicity, assuming that we are working with physically correct offset
    // viewDir vectors, so we are working with X and Y coordinates of a viewDir vector
    // which has been scaled to have Z == 1 (it "touches" the bottom of the height map).
    // Therefore, stepping on the height by stepSize == 0.1, and by viewDir.xy * stepSize
    // on the uv, allows us to raymarch till the bottom of the heightmap along the
    // viewDir vector.
    // We have to use a for loop instead of a while loop, because the compiler
    // need a deterministic flow to know which mipmap to use for the sampling of 
    // the parallax map, and with a while loop it doesn't know that the max number of
    // loop is finite. However, this also means that, by unrolling the loop, we'll
    // end up by sampling PARALLAX_RAYMARCHING_STEPS times always,
    // even if we could have stopped earlier (which is even more expansive).
    for (int i = 1; i < PARALLAX_RAYMARCHING_STEPS && stepHeight > surfaceHeight; i++) {
        // Keeping track of the previous step data for optimization purposes.
        // See later within the for loop body.
        prevUVOffset = uvOffset;
        prevStepHeight = stepHeight;
        prevSurfaceHeight = surfaceHeight;

        // we subtract uvDelta because the viewDir vector points towards the camera,
        // not towards the surface.
        uvOffset -= uvDelta;
        stepHeight -= stepSize;
        surfaceHeight = GetParallaxHeight(uv + uvOffset);
    }

    #if !defined(PARALLAX_RAYMARCHING_SEARCH_STEPS)
        // If the PARALLAX_RAYMARCHING_SEARCH_STEPS is not defined, define it with 0,
        // effectively disabling the variant that uses binary search.
        #define PARALLAX_RAYMARCHING_SEARCH_STEPS 0
    #endif

    #if PARALLAX_RAYMARCHING_SEARCH_STEPS > 0
        // The idea is to apply the binary search, with a fixed amount of steps,
        // to the whole process. This matches the Relief Mapping approach.
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
        // The idea is to keep track of the previous step data so that, when the step
        // where the stepHeight is below the surface height, we find the intersection
        // between the segment made by the last and the previous UV/stepHeiht 
        // and the segment made by the last and the previous UV/surfaceHeight.
        // See the tutorial for a clear graphical explanation.
        // This optimzation variant resambles the Parallax Occlusion Mapping algorithm.
        float prevDifference = prevStepHeight - prevSurfaceHeight;
        float difference = surfaceHeight - stepHeight;
        float t = prevDifference / (prevDifference + difference);
        uvOffset = prevUVOffset - uvDelta * t;
    #endif

    return uvOffset;
}

void ApplyParallax (inout Interpolators i) {
    #if defined(_PARALLAX_MAP)
        // Normalize view dire to have a unit-vector after interpolation
        i.tangentViewDir = normalize(i.tangentViewDir);
        // Perform the following code only if we want to use the physically correct
        // offset, not the limited offset (see later)
        #if !defined(PARALLAX_OFFSET_LIMITING)
            // Currently we are using what is called "limited offset", because
            // the tangent view direction vector is a unit vector. The physically correct
            // offset is different and it's hard to explain here (see the tutorial for
            // a full explanation). Anyway, to get it we have to scale it for its own
            // Z component.
            // Moreover, since for steep view angles the z component gets close to 0,
            // creating a too severe warp of the texture, the standard shader adds a bias
            // to reduce the effect.
            #if !defined(PARALLAX_BIAS)
                // Use the default (standard shader) bias value is none has been previously
                // defined.
                #define PARALLAX_BIAS 0.42
            #endif
            i.tangentViewDir.xy /= (i.tangentViewDir.z + PARALLAX_BIAS);
        #endif

        #if !defined(PARALLAX_FUNCTION)
            // If no parallax function is defined, fallback to the simple
            // Parallax offset algorithm.
            #define PARALLAX_FUNCTION ParallaxOffset
        #endif
        float2 uvOffset = PARALLAX_FUNCTION(i.uv.xy, i.tangentViewDir.xy);
        i.uv.xy += uvOffset;
        // Also apply displacement to the detail map UVs (stored in the Z and W components
        // of the UV vector). To support tiling, however, we must also strenghten the
        // displacement for the amount of tiling. Lastly, it must be relative to the
        // main UV tiling, in case it's set to something else than 1x1.
        // Note: we don't scale the main UVs with tiling because we typically want a
        // weaker parallax effect when increasing the tiling of the main maps. So, since
        // that it's what already happens, we simply don't compensate for it.
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

UnityIndirect CreateIndirectLight (Interpolators i, float3 viewDir) {
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
        envData.roughness = 1 - GetSmoothness(i);
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
        float occlusion = GetOcclusion(i);
        indirectLight.diffuse *= occlusion;
        indirectLight.specular *= occlusion;
        #if defined(DEFERRED_PASS) && UNITY_ENABLE_REFLECTION_BUFFERS
            indirectLight.specular = 0;
        #endif
    #endif

    return indirectLight;
}

float3 GetTangentSpaceNormal(Interpolators i) {
    float3 normal = float3(0, 0, 1);
    #if defined(_NORMAL_MAP)
        normal = UnpackScaleNormal(tex2D(_NormalMap, i.uv.xy), _BumpScale);
    #endif
    #if defined(_DETAIL_NORMAL_MAP)
        float3 detailNormal = UnpackScaleNormal(
            tex2D(_DetailNormalMap, i.uv.zw),
            _DetailBumpScale
        );
        detailNormal = lerp(float3(0, 0, 1), detailNormal, GetDetailMask(i));
        normal = BlendNormals(normal, detailNormal);
    #endif
    return normal;
}

void InitializeFragmentNormal(inout Interpolators i) {
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

    // Apply Parallax modifies the Interpolator instance, so it must
    // be done before that instance is used (vpos won't be changed
    // so modifications can be made after LOD cross fade logics.)
    ApplyParallax(i);

    float alpha = GetAlpha(i);
    #if defined(_RENDERING_CUTOUT)
        clip(alpha - _Cutoff);
    #endif

    // Applied Normal mapping
    InitializeFragmentNormal(i);

    float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos.xyz);
    
    // Metallic flow logic
    float3 specularTint;
    float oneMinusReflectivity;
    float3 albedo = DiffuseAndSpecularFromMetallic(
        GetAlbedo(i),
        GetMetallic(i),
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
        GetSmoothness(i),
        i.normal,
        viewDir,
        CreateLight(i),
        CreateIndirectLight(i, viewDir)
    );
    color.rgb += GetEmission(i);

    #if defined(_RENDERING_FADE) || defined(_RENDERING_TRANSPARENT)
        color.a = alpha;
    #endif

    FragmentOutput output;
    #if defined(DEFERRED_PASS)
        #if !defined(UNITY_HDR_ON)
            color.rgb = exp2(-color.rgb);
        #endif
        output.gBuffer0.rgb = albedo;
        output.gBuffer0.a = GetOcclusion(i);
        output.gBuffer1.rgb = specularTint;
        output.gBuffer1.a = GetSmoothness(i);
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