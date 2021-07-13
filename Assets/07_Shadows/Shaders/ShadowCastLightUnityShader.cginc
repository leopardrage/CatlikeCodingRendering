#if !defined(SHADOW_CAST_LIGHT_UNITY_SHADER)
#define SHADOW_CAST_LIGHT_UNITY_SHADER

// Including UnityPBSLighting.cginc before AutoLight.cginc ensures that
// UnityCG.cginc is included (fix UnityDecodeCubeShadowDepth undefined in
// case of point lights with shadows)
#include "UnityPBSLighting.cginc"
#include "AutoLight.cginc"

float4 _Tint;
sampler2D _MainTex;
float4 _MainTex_ST;
float _Metallic;
float _Smoothness;

sampler2D _NormalMap;
float _BumpScale;

sampler2D _DetailTex;
float4 _DetailTex_ST;

sampler2D _DetailNormalMap;
float _DetailBumpScale;

struct VertexData {
    // vertex variable name is required when using TRANSFER_SHADOW macro
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 uv : TEXCOORD0;
};

struct Interpolators {
    // pos variable name is required when using SHADOW_ATTENUATION macro
    // or when using UNITY_LIGHT_ATTENUATION when shadow variants are active
    // because, in those variants, UNITY_LIGHT_ATTENUATION uses SHADOW_ATTENUATION
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

    // Manual definition of shadowCoordinates
    /* #if defined(SHADOWS_SCREEN)
    float4 shadowCoordinates : TEXCOORD5;
    #endif */
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

    

    // Manual shadow coordinates calculation
    //

    //#if defined(SHADOWS_SCREEN)
    // Flipped Y to handle Direct3D API
    //float2 shadowCoordinatesXY = float2(i.pos.x, -i.pos.y);
    // Conversion from Clip Space to Screen space, using W component
    // to handle projection camera.
    //i.shadowCoordinates.xy = (shadowCoordinatesXY + i.pos.w) * 0.5;
    //i.shadowCoordinates.zw = i.pos.zw;
    //#endif

    // Shadow calculation using UnityCG.cginc
    //

    //#if defined(SHADOWS_SCREEN)
    // ComputeScreenPos from UnityCG.cginc takes care of Y flipping depending
    // on the graphics API in use and perform special logic when doing
    // single-pass steroscopic rendering
    //i.shadowCoordinates = ComputeScreenPos(i.pos);
    //#endif

    // Shadow calculation using AutoLight.cginc.
    // it assumes specific VertexData and Interpolators variable names
    TRANSFER_SHADOW(i);
    
    ComputeVertexLightColor(i);
    return i;
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

    // Manual attenuation calculation when dealing with shadows
    //

    //#if defined(SHADOWS_SCREEN)
    // Since the shadow coordinates are homogeneous, they must be divided by W
    // But we couldn't do it in the vertex shader because division is not a linear
    // operation and the vertex to fragment interpolation would have given uncorrect
    // values.
    //float2 shadowCoordinatesXY = i.shadowCoordinates.xy / i.shadowCoordinates.w;
    // The screen space shadow map is sampled and used as attenuation to allow
    // the object to receive shadows. _ShadowMapTexture is the screen space shadow map
    // for the current light provided by AutoLight.cginc
    //float attenuation = tex2D(_ShadowMapTexture, shadowCoordinatesXY);
    //#else
    //UNITY_LIGHT_ATTENUATION(attenuation, 0, i.worldPos)
    //#endif

    // Attenuation calculation using SHADOW_ATTENUATION from AutoLight.cginc directly
    //#if defined(SHADOWS_SCREEN)
    //float attenuation = SHADOW_ATTENUATION(i);
    //#else
    //UNITY_LIGHT_ATTENUATION(attenuation, 0, i.worldPos)
    //#endif

    // Attenuation calculation using UNITY_LIGHT_ATTENUATION, providing interpolators
    // which uses SHADOW_ATTENUATION when shadow variants are used
    UNITY_LIGHT_ATTENUATION(attenuation, i, i.worldPos)

    light.color = _LightColor0.rgb * attenuation;

    light.ndotl = DotClamped(i.normal, light.dir);
    return light;
}

UnityIndirect CreateIndirectLight (Interpolators i) {
    UnityIndirect indirectLight;
    indirectLight.diffuse = 0;
    indirectLight.specular = 0;

    #if defined(VERTEXLIGHT_ON)
    indirectLight.diffuse = i.vertexLightColor;
    #endif

    #if defined(FORWARD_BASE_PASS)
    indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));
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
    albedo = DiffuseAndSpecularFromMetallic(albedo, _Metallic, specularTint, oneMinusReflectivity);

    return UNITY_BRDF_PBS(
        albedo,
        specularTint,
        oneMinusReflectivity,
        _Smoothness,
        i.normal,
        viewDir,
        CreateLight(i),
        CreateIndirectLight(i)
    );
}

#endif