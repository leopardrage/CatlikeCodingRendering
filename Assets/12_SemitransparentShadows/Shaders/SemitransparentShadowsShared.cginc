#if !defined(SEMITRANSPARENT_SHADOWS_SHARED)
#define SEMITRANSPARENT_SHADOWS_SHARED

#include "UnityPBSLighting.cginc"
#include "AutoLight.cginc"

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
    float3 worldPos : TEXCOORD4;

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
        unity_4LightAtten0, i.worldPos, i.normal);
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
    i.worldPos = mul(unity_ObjectToWorld, v.vertex);
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
        // Take the alpha channel of the albedo texture into account only if the
        // material is not set to use the albedo alpha for smoothness.
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
    #if defined(FORWARD_BASE_PASS)
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
        // Occlusion values are stored in the G channel of the Occlusion Map by convention.
        return lerp(1, tex2D(_OcclusionMap, i.uv.xy).g, _OcclusionStrength);
    #else
        return 1;
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
    #if defined(POINT) || defined(POINT_COOKIE) || defined(SPOT)
    // Point Light
    light.dir = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
    #else
    // Directional Light
    light.dir = _WorldSpaceLightPos0.xyz;
    #endif
    
    UNITY_LIGHT_ATTENUATION(attenuation, i, i.worldPos)
    light.color = _LightColor0.rgb * attenuation;
    light.ndotl = DotClamped(i.normal, light.dir);
    return light;
}

UnityIndirect CreateIndirectLight (Interpolators i, float3 viewDir) {
    UnityIndirect indirectLight;
    indirectLight.diffuse = 0;
    indirectLight.specular = 0;

    #if defined(VERTEXLIGHT_ON)
    indirectLight.diffuse = i.vertexLightColor;
    #endif

    #if defined(FORWARD_BASE_PASS)
    indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));

    float3 reflectionDir = reflect(-viewDir, i.normal);
    Unity_GlossyEnvironmentData envData;
    envData.roughness = 1 - GetSmoothness(i);
    envData.reflUVW = BoxProjection(
        reflectionDir, i.worldPos,
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
            reflectionDir, i.worldPos,
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

float4 MyFragmentProgram (Interpolators i) : SV_TARGET {

    // Simple clip of all alpha value below 0.5
    float alpha = GetAlpha(i);
    #if defined(_RENDERING_CUTOUT)
        // Since clip is very expansive ofr mobile GPU, do it only when needed
        clip(alpha - _AlphaCutoff);
    #endif

    // Applied Normal mapping
    InitializeFragmentNormal(i);

    float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
    
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
        // For transparent objects, albedo is reduced based on alpha (premultiplied alpha).
        // This compensate the BlendMode One OneMinusSrcAlpha, where the material color
        // as a whole would be added over the background color, while we want that only
        // for the specular component and not for the diffuse component.
        albedo *= alpha;
        // Energy conservation: for transpareny object, the amount of light that
        // bounces away from the surface (specular term) reduces the diffuse term.
        // This is obtained by the formula alpha = 1 (1 - A)*(1- r), where A is
        // the original alpha and r is the reflectivity. This is the semplified formula.
        // NOTE: this is a semplification of physically realistic transparent object
        // since it does not take the object volume into account, only the surface.
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

    return color;
}

#endif