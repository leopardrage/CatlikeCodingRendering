#if !defined(BUMPINESS_TANGENT_SPACE_SHADER_INCLUDED)
#define BUMPINESS_TANGENT_SPACE_SHADER_INCLUDED

#include "AutoLight.cginc"
#include "UnityPBSLighting.cginc"

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
    float4 position : POSITION;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 uv : TEXCOORD0;
};

struct Interpolators {
    float4 position : SV_POSITION;
    float4 uv : TEXCOORD0;
    float3 normal : TEXCOORD1;

    #if defined(BINORMAL_PER_FRAGMENT)
    float4 tangent : TEXCOORD2;
    #else
    float3 tangent : TEXCOORD2;
    float3 binormal : TEXCOORD3;
    #endif
    float3 worldPos : TEXCOORD4;

    #if defined(VERTEXLIGHT_ON)
    float3 vertexLightColor : TEXCOORD5;
    #endif
};

void ComputeVertexLightColor (inout Interpolators i) {
    #if defined(VERTEXLIGHT_ON)
    // Since there can be up to 4 vertex light at the same time
    // This computation should be performed 4 times
    /* float3 lightPos = float3(
        unity_4LightPosX0.x, unity_4LightPosY0.x, unity_4LightPosZ0.x
    );
    float3 lightVec = lightPos - i.worldPos;
    float3 lightDir = normalize(lightVec);
    float ndotl = DotClamped(i.normal, lightDir);
    // In this situation we cannot use UNITY_LIGHT_ATTENUATION, so attenuation
    // must be computed manually. But we can use the unity_4LightAtten0 variable
    // To achieve better results.
    float attenuation = (1 / (1 + dot(lightVec, lightVec)) * unity_4LightAtten0.x);
    i.vertexLightColor = unity_LightColor[0].rgb * ndotl * attenuation; */

    // The Shade4PointLights function of UnityCG does the previous computation 4 times
    i.vertexLightColor = Shade4PointLights(
        unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
        unity_LightColor[0].rgb, unity_LightColor[1].rgb,
        unity_LightColor[2].rgb, unity_LightColor[3].rgb,
        unity_4LightAtten0, i.worldPos, i.normal);
    #endif
}

float3 CreateBinormal (float3 normal, float3 tangent, float binormalSign) {
    // calculating binormal from normal and tangent vertex info.
    // Regarding the role of the binormalSign, check the tutorial for details
    float3 binormal = cross(normal, tangent.xyz) * binormalSign;

    // When the game object is scaled with negative values on ad odd number of dimensions
    // (1 or 3 dimensions, then), binormals should be flipped. UnityShaderVariables variable
    // unity_WorldTransformParams helps us providing the fourth component as -1 when
    // we need to flip the binormals
    binormal *= unity_WorldTransformParams.w;

    return binormal;
}

Interpolators MyVertexProgram (VertexData v) {
    Interpolators i;
    i.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
    i.uv.zw = TRANSFORM_TEX(v.uv, _DetailTex);
    i.position = UnityObjectToClipPos(v.position);
    i.worldPos = mul(unity_ObjectToWorld, v.position);
    i.normal = UnityObjectToWorldNormal(v.normal);
    #if defined(BINORMAL_PER_FRAGMENT)
    i.tangent = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
    #else
    i.tangent = UnityObjectToWorldDir(v.tangent.xyz);
    i.binormal = CreateBinormal(i.normal, i.tangent, v.tangent.w);
    #endif
    ComputeVertexLightColor(i);
    return i;
}

UnityLight CreateLight (Interpolators i) {
    UnityLight light;
    // _WorldSpaceLightPos0 is the position of the current pass' light
    // in homogeneous coordinates (if it'a point light),
    // or its direction (if it's a directional light)

    // _LightColor0 is defined in UnityLightingCommon 
    // and is the color of the current pass' light

    //
    // Point Light
    //

    #if defined(POINT) || defined(POINT_COOKIE) || defined(SPOT)
    // Point Light
    light.dir = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
    #else
    // Directional Light
    light.dir = _WorldSpaceLightPos0.xyz;
    #endif

    // Defining attenuation manually (only for point light, of course)
    //float3 lightVec = _WorldSpaceLightPos0.xyz - i.worldPos;
    //float3 attenuation = 1 / (1 + dot(lightVec, lightVec));

    // Defining attenuation using macro contained in AutoLight.cginc
    // Besides doing the same as above, it also handles shadows and performs
    // a sample on an attenuation texture to smooth transitions of objects
    // in and out of range.
    // If POINT or SPOT keywords are not defined (directional light),
    // attenuation is always 1.0
    UNITY_LIGHT_ATTENUATION(attenuation, 0, i.worldPos);
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
    // This is moved directly in the space conversion step
    // tangentSpaceNormal = tangentSpaceNormal.xzy;

    #if defined(BINORMAL_PER_FRAGMENT)
    float3 binormal = CreateBinormal(i.normal, i.tangent.xyz, i.tangent.w);
    #else
    float3 binormal = i.binormal;
    #endif

    // Space conversion (change of basis). normal and binormal are swapped
    // to handle the XY swap directly in this conversion
    i.normal = normalize(
        tangentSpaceNormal.x * i.tangent +
        tangentSpaceNormal.y * binormal +
        tangentSpaceNormal.z * i.normal
    );
}

float4 MyFragmentProgram (Interpolators i) : SV_TARGET {

    // Applied Normal mapping
    InitializeFragmentNormal(i);

    // Linerarly interpolating unit vectors doesn't produce unit vectors
    // The difference is very small, though, so not normalizing at this stage
    // is a common optimization, typical of mobile devices
    float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
    float3 albedo = tex2D(_MainTex, i.uv.xy).rgb * _Tint.rgb;

    // Detail texture
    albedo *= tex2D(_DetailTex, i.uv.zw) * unity_ColorSpaceDouble;

    //
    // Metallic flow logic
    //

    // Oversemplification: metal has specular but no albedo, dielectries the other way around
    // float3 specularTint = albedo * _Metallic;
    // float oneMinusReflectivity = 1 - _Metallic;
    // albedo *= oneMinusReflectivity;

    // More realistic approach, using a utility function of UnityStandardUtils
    float3 specularTint;
    float oneMinusReflectivity;
    albedo = DiffuseAndSpecularFromMetallic(albedo, _Metallic, specularTint, oneMinusReflectivity);

    //
    // -----
    //

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