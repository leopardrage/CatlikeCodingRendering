#if !defined(REFLECTION_SHARED)
#define REFLECTION_SHARED

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

float3 BoxProjection (
    float3 direction,
    float3 position,
    float4 cubemapPosition,
    float3 boxMin,
    float3 boxMax) {
        
        // Top note: all the following code could be performed by the
        // BoxProjectedCubemapDirection function of UnityStandardUtils, but,
        // since it also needlessly normalizes the reflection direction, we do not use it.

        // The UNITY_SPECCUBE_BOX_PROJECTION Unity macro is 1 when box projection is supported
        // on the target platform, 0 otherwise.
        #if UNITY_SPECCUBE_BOX_PROJECTION
        // Perform box projection only if Box Projection is enabled of the current
        // Reflection probe (cubemapPosition.w > 0)
        // The UNITY_BRANCH macro ensure that an actual branch is created in the
        // derivated shaders, so we can actually skip all the logic when box projection
        // is disabled. This is needed in this case, because (at least) both OpenGl Core
        // and Direct3D 11 end up performing always all the box projection logic and
        // return the correct value based on cubemapPosition.w only at the end.
        // Apart for this specific kind of needs, UNITY_BRANCH should be avoided.
        UNITY_BRANCH
        if (cubemapPosition.w > 0) {

            // The goal is to find the intersection point between the
            // cubemap box and the reflection direction vector applied on the
            // surface position. When we find that intersection point, we can
            // subtract the cubemap position to find the vector we need to
            // sample the cubemap.

            // Long story
            /*
            
            // Make boxMin and BoxMax relative to the surface position
            boxMin -= position;
            boxMax -= position;
            // Then we want to find the all possible intersection point of the direction vector
            // with each plane where the box bounds lies on to.
            // To achieve that, for each dimension we pick the corresponding value
            // from boxMax or boxMin, based on the direction component sign. Then we divide
            // that value by the direction component itself, thus getting the scale that,
            // should we use it to scale the direction vector uniformely (for each component),
            // we'd get the intersection point with that plane of the bound of the box.
            float x = (direction.x > 0 ? boxMax.x : boxMin.x) / direction.x;
            float y = (direction.y > 0 ? boxMax.y : boxMin.y) / direction.y;
            float z = (direction.z > 0 ? boxMax.z : boxMin.z) / direction.z;

            // Then we choose the smaller scale factor, which will correspond to
            // the actual box intersection point.
            // The direction vector cannot be (0, 0, 0). At least 1 component
            // will be not 0. The min function handles undefined values and
            // a defined value will win between the two. So this always works.
            float scalar = min(min(x, y), z);
            */

            // Short Story
            float3 factors = ((direction > 0 ? boxMax : boxMin) - position) / direction;
            float scalar = min(min(factors.x, factors.y), factors.z);

            // direction * scalar = intersection point of the direction with the cubemap box,
            // relative to the surface position
            // direction * scalar + position = same as before but relative to the world
            // direction * scalar + position - cubemapPosition = same as before
            // but relative to the cubemap position, which is the sampling vector we need.
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

#define REFLECTION_BLENDING_PROBES // That is the most complete procedure
#define REFLECTION_USING_UNITY_MACRO
#define REFLECTION_MANUAL

UnityIndirect CreateIndirectLight (Interpolators i, float3 viewDir) {
    UnityIndirect indirectLight;
    indirectLight.diffuse = 0;
    indirectLight.specular = 0;

    #if defined(VERTEXLIGHT_ON)
    indirectLight.diffuse = i.vertexLightColor;
    #endif

    #if defined(FORWARD_BASE_PASS)
    indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));

    // 
    // Reflections from environment cube map
    //
    float3 reflectionDir = reflect(-viewDir, i.normal);

    #if defined(REFLECTION_BLENDING_PROBES)
    // Blending reflection probes is done between two reflection probes.
    // unity_SpecCube0 and unity_SpecCube1. We simply calculate everything for
    // both of them and then lerp based on unity_SpecCube0_BoxMin.w, which is
    // the contribute of the first probe, provided by Unity based on multiple factors.

    Unity_GlossyEnvironmentData envData;
    envData.roughness = 1 - _Smoothness;
    envData.reflUVW = BoxProjection(
        reflectionDir, i.worldPos,
        unity_SpecCube0_ProbePosition,
        unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax
    );
    float3 probe0 = Unity_GlossyEnvironment(
        UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData
    );

    // The UNITY_SPECCUBE_BLENDING Unity macro is 1 when blending is supported on the
    // target platform, 0 otherwise.
    #if UNITY_SPECCUBE_BLENDING
    float interpolator = unity_SpecCube0_BoxMin.w;
    // Only perform blending when unity_SpecCube0_BoxMin.w is less then 1.
    UNITY_BRANCH
    if (interpolator < 0.99999) {
        envData.reflUVW = BoxProjection(
            reflectionDir, i.worldPos,
            unity_SpecCube1_ProbePosition,
            unity_SpecCube1_BoxMin, unity_SpecCube1_BoxMax
        );
        // UNITY_PASS_TEXCUBE_SAMPLER (which takes both unity_SpecCube1 and unity_SpecCube0)
        // must be used to sample unity_SpecCube1. This is needed for specific Unity macro
        // logics and requirements and get rid of the samplerunity_SpecCube1 missing variable
        // compile error.
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
    #elif defined(REFLECTION_USING_UNITY_MACRO)
    // Unity_GlossyEnvironment perform the same code manually written below.
    // It needs a Unity_GlossyEnvironmentData instance (which contains roughness
    // and reflection direction), unity_SpecCube0_HDR decode info to decode from HDR to RGB
    // and the cubemap texture, passed through the UNITY_PASS_TEXCUBE macro, which
    // takes care of the type differences.
    // Also Unity_GlossyEnvironment takes care of more platform differences and
    // optimize things.
    Unity_GlossyEnvironmentData envData;
    envData.roughness = 1 - _Smoothness;
    // Handling box projection
    envData.reflUVW = BoxProjection(
        reflectionDir, i.worldPos,
        unity_SpecCube0_ProbePosition,
        unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax
    );
    // envData.reflUVW = reflectionDir;
    indirectLight.specular = Unity_GlossyEnvironment(
        UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData);
    #elif defined(REFLECTION_MANUAL)
    // With Roughness
    // unity_SpecCube0 contains the environment cube map. Its type depend on
    // the target platform, and the UNITY_SAMPLE_TEXCUBE_LOD macro takes care of that for us.
    // Additionally, UNITY_SAMPLE_TEXCUBE_LOD require to specify a LOD value to
    // pick a sample based on trilinear filtering. UNITY_SPECCUBE_LOD_STEPS contains
    // The number of mipmap levels

    float roughness = 1 - _Smoothness;
    // The relation between roughness and mipmap levels is not linear.
    // Unity uses this conversion formula
    roughness *= 1.7 - 0.7 * roughness;
    float4 envSample = UNITY_SAMPLE_TEXCUBE_LOD(
        unity_SpecCube0, reflectionDir, roughness * UNITY_SPECCUBE_LOD_STEPS);

    // Without Roughness
    // unity_SpecCube0 contains the environment cube map. Its type depend on
    // the target platform, and the UNITY_SAMPLE_TEXCUBE macro takes care of that for us

    // float4 envSample = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflectionDir);

    // The skybox cubemap contains HDR colors, where RGB value might be greater then 1.
    // Therefore they are provided in the RGBM format, which the DecodeHDR function
    // converts to the regular RGB format by using the sampled value and the information
    // contained in unity_SpecCube0_HDR, meta data for this cubemap that instruct the
    // function to how to decode HDR values.
    // NOTE: Both the default skybox and a custom HDR skybox seem not to need
    // the decode step, appearently because UNITY_SAMPLE_TEXCUBE already output RBG values
    // and unity_SpecCube0_HDR meta data are set to make DecodeHDR output the input data
    // unaltered. But this seems to be the correct flow even now, so I'll leave it here.
    indirectLight.specular = DecodeHDR(envSample, unity_SpecCube0_HDR);
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
    albedo = DiffuseAndSpecularFromMetallic(albedo, _Metallic, specularTint, oneMinusReflectivity);

    return UNITY_BRDF_PBS(
        albedo,
        specularTint,
        oneMinusReflectivity,
        _Smoothness,
        i.normal,
        viewDir,
        CreateLight(i),
        CreateIndirectLight(i, viewDir)
    );
}

#endif