#if !defined(EMISSION_SHARED)
#define EMISSION_SHARED

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

float GetMetallic(Interpolators i) {
    #if defined(_METALLIC_MAP)
    // Metallic textures are assumed to be greyscale. The Standard shader uses the R channel
    // in this case, but it's arbitrary. Also, mind that uv is float4, to store both
    // the main texture and the detail texture UVs, transformed by the respective Tile
    // and Scale settings. X and Y corresponds to the main texture UVs, so we pick those.
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
    // We are assuming _MetallicMap being a metallic + smoothness texture, where RGB channels
    // store the metallic value (greyscale) and the A channel stores the smoothness value.
    smoothness = tex2D(_MetallicMap, i.uv.xy).a;
    #endif
    return smoothness * _Smoothness;
}

float3 GetEmission(Interpolators i) {
    // We still check if we are in the base pass, although the check on _EmissionMap
    // would be enough, because returning explicitly 0 outside the base pass allows the
    // compiler to optimize the shader further.
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
    #endif

    return indirectLight;
}

void InitializeFragmentNormal(inout Interpolators i) {
    // Bump mapping: applied normal map
    float3 mainNormal = UnpackScaleNormal(tex2D(_NormalMap, i.uv.xy), _BumpScale);
    float3 detailNormal = UnpackScaleNormal(tex2D(_DetailNormalMap, i.uv.zw), _DetailBumpScale);
    float3 tangentSpaceNormal = BlendNormals(mainNormal, detailNormal);

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

    // Applied Normal mapping
    InitializeFragmentNormal(i);

    float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
    float3 albedo = tex2D(_MainTex, i.uv.xy).rgb * _Tint.rgb;

    // Detail texture
    albedo *= tex2D(_DetailTex, i.uv.zw) * unity_ColorSpaceDouble;

    // Metallic flow logic
    float3 specularTint;
    float oneMinusReflectivity;
    albedo = DiffuseAndSpecularFromMetallic(
        albedo,
        GetMetallic(i),
        specularTint,
        oneMinusReflectivity
    );

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
    return color;
}

#endif