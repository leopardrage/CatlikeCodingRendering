#if !defined(BUMPINESS_NORMAL_MAP_SHADER_INCLUDED)
#define BUMPINESS_NORMAL_MAP_SHADER_INCLUDED

#include "AutoLight.cginc"
#include "UnityPBSLighting.cginc"

float4 _Tint;
sampler2D _MainTex;
float4 _MainTex_ST;
float _Metallic;
float _Smoothness;

sampler2D _NormalMap;
float _BumpScale;

struct VertexData {
    float4 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
};

struct Interpolators {
    float4 position : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float3 worldPos : TEXCOORD2;

    #if defined(VERTEXLIGHT_ON)
    float3 vertexLightColor : TEXCOORD3;
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

Interpolators MyVertexProgram (VertexData v) {
    Interpolators i;
    i.uv = TRANSFORM_TEX(v.uv, _MainTex);
    i.position = UnityObjectToClipPos(v.position);
    i.worldPos = mul(unity_ObjectToWorld, v.position);
    i.normal = UnityObjectToWorldNormal(v.normal);
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

    // Normal Maps in Unity are compressed with the DXT5nm format,
    // which stores only X and Y coordinates of the normal in G and A channels
    // respectively
    i.normal.xy = tex2D(_NormalMap, i.uv).wy;

    // Since normal maps are just textures, and colors are non-negative vectors,
    // normal vectors in normal maps are stored as (N + 1) / 2, thus changing
    // them from their original [-1,1] range to [0,1]. Therefore, they must now
    // brought back to their original [0,1] range
    i.normal.xy = i.normal.xy * 2 - 1;

    // Increasing the X and Y coordinates will result in shorter Z coordinate
    // (see next statement), and thus in a normal less orthogonal to the ground,
    // thus increasing the bumpiness. The opposite also is true.
    i.normal.xy *= _BumpScale;

    // The third component is inferred by the other two because we are working with
    // unit vectors. Nx^2 + Ny^2+ Nz^2 = 1, thus: Nz = SQRT(1 - Nx^2 - Ny^2).
    // Saturate is needed to handle possible out of bound values due to limited precision.
    i.normal.z = sqrt(1 - saturate(dot(i.normal.xy, i.normal.xy)));

    // By standard, normal maps consider X and Y are the surface plane, and Z the axis
    // that go away from the surface. However Unity consider X and Z as the surface plane
    // Y the outgoing axis, so they must be swapped.
    i.normal = i.normal.xzy;
    
    i.normal = normalize(i.normal);
}

void InitializeFragmentNormalWithUnityUtils(inout Interpolators i) {
    // Bump mapping: applied normal map

    // Utility function of UnityStandardUtils that does all the stuff we performed
    // in InitializeFragmentNormal, plus handling mobile platforms, where DXT5nm
    // is not supported, and so regular RGB values must used and bump scale is not
    // available
    float3 mainNormal = UnpackScaleNormal(tex2D(_NormalMap, i.uv), _BumpScale);

    // By standard, normal maps consider X and Y are the surface plane, and Z the axis
    // that go away from the surface. However Unity consider X and Z as the surface plane
    // Y the outgoing axis, so they must be swapped.
    i.normal = i.normal.xzy;
    
    i.normal = normalize(i.normal);
}

float4 MyFragmentProgram (Interpolators i) : SV_TARGET {

    // Applied Normal mapping using Unity utility function
    InitializeFragmentNormalWithUnityUtils(i);
    // Applied Normal mapping plainly (does not handle bump scale on mobile)
    // InitializeFragmentNormal(i);

    // Linerarly interpolating unit vectors doesn't produce unit vectors
    // The difference is very small, though, so not normalizing at this stage
    // is a common optimization, typical of mobile devices
    float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
    float3 albedo = tex2D(_MainTex, i.uv.xy).rgb * _Tint.rgb;

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