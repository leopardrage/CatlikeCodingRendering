#if !defined(FOG_SHARED)
#define FOG_SHARED

#include "UnityPBSLighting.cginc"
#include "AutoLight.cginc"

#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
    #if !defined(FOG_DISTANCE)
        #define FOG_DEPTH 1
    #endif
    #define FOG_ON 1
#endif

float4 _Tint;
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

sampler2D _OcclusionMap;
float _OcclusionStrength;

sampler2D _DetailMask;

float _AlphaCutoff;

struct VertexData {
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 uv : TEXCOORD0;
};

struct Interpolators {
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
        // in case of fog we use a float4 to store the clip-space depth value
        // in the w coordinate
        float4 worldPos : TEXCOORD4;
    #else
        float3 worldPos : TEXCOORD4;
    #endif

    // Shadow coordinates definition through AutoLight.cginc macro
    SHADOW_COORDS(5)

    #if defined(VERTEXLIGHT_ON)
    float3 vertexLightColor : TEXCOORD6;
    #endif
};

void ComputeVertexLightColor (inout Interpolators i) {
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

Interpolators MyVertexProgram (VertexData v) {
    Interpolators i;
    i.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
    i.uv.zw = TRANSFORM_TEX(v.uv, _DetailTex);
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

    // Shadow calculation using AutoLight.cginc.
    // it assumes specific VertexData and Interpolators variable names
    TRANSFER_SHADOW(i);
    
    ComputeVertexLightColor(i);
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
    float3 albedo = tex2D(_MainTex, i.uv.xy).rgb * _Tint.rgb;
    #if defined(_DETAIL_ALBEDO_MAP)
        float3 details = tex2D(_DetailTex, i.uv.zw) * unity_ColorSpaceDouble;
        albedo = lerp(albedo, albedo * details, GetDetailMask(i));
    #endif
    return albedo;
}

float GetAlpha(Interpolators i) {
    float alpha = _Tint.a;
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
            // i.worldPos.w containt the clip space depth.
            // UNITY_Z_0_FAR_FROM_CLIPSPACE convert the depth value in case of
            // reversed clip-space Z dimensions, depending on the graphic libraries
            viewDistance = UNITY_Z_0_FAR_FROM_CLIPSPACE(i.worldPos.w);
        #endif
        // This macro creates and assign the unityFogFactor variable based on
        // the fog mode set in the Lighting settings of the current scene. If fog is
        // disabled, it assign 0.0.
        UNITY_CALC_FOG_FACTOR_RAW(viewDistance);
        float3 fogColor = 0;
        // unity_FogColor is defined in ShaderVariables
        // we only use it in the base pass to apply the real fog only once.
        // For all other lights we use a black fog to avoid that the each other light
        // brightens the fragment too much.
        #if defined(FORWARD_BASE_PASS)
            fogColor = unity_FogColor.rgb;
        #endif
        color.rgb = lerp(fogColor, color.rgb, saturate(unityFogFactor));
    #endif
    return color;
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

    #if defined(DEFERRED_PASS)
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
        light.color = _LightColor0.rgb * attenuation;
    #endif
    // UnityLight.ndotl field and DotClamped function have been deprecated by Unity
    // and are not needed anymore
    //light.ndotl = DotClamped(i.normal, light.dir);
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
    indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));

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

    // During the deferred pass, if the deferred reflections are enabled
    // a dedicated Internal-DeferredReflection shader computes reflections.
    // In that case, reflections provided by probes in our shader are black,
    // negating thier contribute. In that case, setting specular to 0 here (I think...)
    // allows the compiler to optimize the shader so that no reflection
    // probe logic is performed at all.
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
        // During the deferred pass we have to output to 4 rendering targets:
        // Albedo + Occlusion (ARGB32, 8 bit for each channel)
        // Albedo -> RGB, Occlusion -> Alpha
        float4 gBuffer0 : SV_Target0;
        // Specular + Smoothness (ARGB32, 8 bit for each channel)
        // Specular -> RGB, Smoothness -> Alpha
        float4 gBuffer1 : SV_Target1;
        // World space normals (ARGB2101010, 10 bit for RGB, 2 bit for Alpha)
        // World space normals -> RGB, Alpha is not used
        float4 gBuffer2 : SV_Target2;
        // Accumulated lighting of the scene
        // ARGB2101010, 10 bit for RGB, 2 bit for Alpha, if LDR
        // ARGBHalf, 16 bit for each channel, if HDR
        float4 gBuffer3 : SV_Target3;
    #else
        // Otherwise we output to the regular rendering target.
        // Note that SV_Target is different from the previously used SV_TARGET
        // but it's fine, since this and other semantics are not case-sensitive.
        // However, this is not true for all semantics (e.g.: POSITION and SV_POSITION)
        float4 color : SV_Target;
    #endif
};

FragmentOutput MyFragmentProgram (Interpolators i) {

    // Simple clip of all alpha value below 0.5
    float alpha = GetAlpha(i);
    #if defined(_RENDERING_CUTOUT)
        // Since clip is very expansive ofr mobile GPU, do it only when needed
        clip(alpha - _AlphaCutoff);
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
    // Since emission is on top of all other light sources, we add it to the final color.
    color.rgb += GetEmission(i);

    #if defined(_RENDERING_FADE) || defined(_RENDERING_TRANSPARENT)
        color.a = alpha;
    #endif

    FragmentOutput output;
    #if defined(DEFERRED_PASS)
        #if !defined(UNITY_HDR_ON)
            // When in LDR, Unity expects gBuffer3 to be logarithmically encoded
            // using log2(color), which is the same as 2^(-color).
            color.rgb = exp2(-color.rgb);
        #endif
        output.gBuffer0.rgb = albedo;
        output.gBuffer0.a = GetOcclusion(i);
        output.gBuffer1.rgb = specularTint;
        output.gBuffer1.a = GetSmoothness(i);
        // Normal components are converted from [-1, -1] to [0, 1]
        // to be stored in a texture.
        output.gBuffer2 = float4(i.normal * 0.5 + 0.5, 1);
        output.gBuffer3 = color;
    #else
        // Apply forward fog before assignment
        output.color = ApplyFog(color, i);
    #endif
    return output;
}

#endif