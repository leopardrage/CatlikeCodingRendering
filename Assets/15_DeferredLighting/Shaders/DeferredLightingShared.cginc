#if !defined(DEFERRED_LIGHTING_SHARED)
#define DEFERRED_LIGHTING_SHARED

#include "UnityPBSLighting.cginc"

// I've checked that vertex values of the input quad are just:
// top-left: (0, 1, 0)
// top-right: (1, 1, 0)
// bottom-left: (0, 0, 0)
// bottom-right: (1, 0, 0)
// X and Y components of these vertices are de-facto valid UV to
// sample the GBuffer, so, as an alternative to all the object-to-clip-space
// conversion and clip-space-to-uv conversion explained in the tutorial, I added
// these alternative that simply assigns the vertices' X and Y components to the
// uv in the Interpolators and use their interopolated values directly in the
// fragment shader. Tested in Direct3D and OpenGL Core. It's working so far.
// #define PLAIN_VERTEX_AS_UV

struct VertexData {
    float4 vertex : POSITION;
    // For reasons I cannot currently fathom these "normals" are view-space rays
    // going from the camera position to the four corner of the screen and
    // reaching as far as the near plane.
    float3 normal : NORMAL;
};

struct Interpolators {
    float4 pos : SV_POSITION;
    float4 uv : TEXCOORD0;
    float3 ray : TEXCOORD1;
};

// Catlikecoding does not explain why it uses this macro, which is
// even more weird since it just used a plain "sampler2D _CameraDepthTexture;"
// declaration in the DeferredFog shader. Elsewhere I found that this macro
// takes care of platform differences but, again, this doesn't explain why it's
// not used in the DeferredFog shader and why it works fine there even without it.
// However, since it uses the SAMPLE_DEPTH_TEXTURE macro to sample this texture
// which takes care of the different types that _CameraDepthTexture might have on
// based on the current platform, it's more likely that this is the correct approach
// and a plain "sampler2D _CameraDepthTexture;" declaration is wrong but works on
// Windows by a lucky chance.
UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);

sampler2D _CameraGBufferTexture0;
sampler2D _CameraGBufferTexture1;
sampler2D _CameraGBufferTexture2;

float4 _LightColor, _LightDir, _LightPos;

// This is 1 when dealing with a quad (directional lights) and 0 when dealing
// with a pyramid (spotlights)
float _LightAsQuad;

// PREMISE: in forward rendering we used macros from AutoLight.cginc to handle
// shadows and light cookies, calculating their attenuation factor to the light.
// But since AutoLight.cginc doesn't work in deferred rendering,
// we have to do deal with shadows and light cookies manually.

// _ShadowMapTexture can be used to access the current light's screen-space shadow map,
// but since it is already defined in UnityShadowLibrary (which we indirectly include)
// for point lights and spotlight, we have to declare it only when dealing with directional
// shadows, which can be done using the SHADOW_SCREEN keyword.
#if defined (SHADOWS_SCREEN)
    sampler2D _ShadowMapTexture;
#endif

#if defined (POINT_COOKIE)
// Light cookie texture for point lights (it's a cubemap)
samplerCUBE _LightTexture0;
#else
// Light cookie texture for spotlights
sampler2D _LightTexture0;
#endif
// world to light conversion matrix
float4x4 unity_WorldToLight;
// Attenuation lookup texture for spotlights
sampler2D _LightTextureB0;

UnityLight CreateLight(float2 uv, float3 worldPos, float viewZ) {
    UnityLight light;
    float attenuation = 1;
    float shadowAttenuation = 1;
    bool shadowed = false;

    #if defined(DIRECTIONAL) || defined(DIRECTIONAL_COOKIE)
        // UnityLight.dir expects the surface->lightSource vector, while _LightDir
        // is the direction of the current directional light. So we must set the opposite.
        light.dir = -_LightDir;

        // Light cookies
        #if defined(DIRECTIONAL_COOKIE)
            // UV coordinates are the X and Y coordinates of the fragment position in
            // the current directional light space. We use the unity_WolrdToLight matrix
            // for the conversion.
            float2 uvCookie = mul(unity_WorldToLight, float4(worldPos, 1)).xy;
            // Remember that only the Alpha channel of the cookie texture is used.
            // The other channels don't matter.
            // Moreover, sometimes (it never occurred to me) there might be artifacts on
            // geometry edges that occurs when there is large difference between the
            // cookie coordinates of adiacient fragment. In those cases, the GPU chooses
            // a mipmap level for the cookie that is too low for the closest surface.
            // We use the tex2Dbias function to add a bias when sampling mip maps.
            // We use -8 for this bias, an experimental value used by Unity to overcame
            // this artifact.
            attenuation *= tex2Dbias(_LightTexture0, float4(uvCookie, 0, -8)).w;
        #endif

        // Shadows
        #if defined (SHADOWS_SCREEN)
            shadowed = true;
            shadowAttenuation = tex2D(_ShadowMapTexture, uv).r;
        #endif
    #else
        float3 lightVec = _LightPos.xyz - worldPos;
        light.dir = normalize(lightVec);

        // Distance Attenuation
        // The Attenuation Lookup texture is designed to be sampled with
        // the squared light distance, scaled by the light's range (stored in _LightPos.w).
        // Since the specific channel containing the attenuation value varies per
        // platform, we use the UNITY_ATTEN_CHANNEL for that.
        attenuation *= tex2D(_LightTextureB0,
            (dot(lightVec, lightVec) * _LightPos.w).rr
        ).UNITY_ATTEN_CHANNEL;

        #if defined(SPOT)
            // Spotlight cookies

            // In case of spotlights, cookies got a perspective transformation (got
            // larger the further away from the light's position you go), so their
            // coordinates must be regularly assumed to be in 4D homogeneus coordinates
            // and, thus, we need to perform a perspective division
            float4 uvCookie = mul(unity_WorldToLight, float4(worldPos, 1));
            uvCookie.xy /= uvCookie.w;
            attenuation *= tex2Dbias(_LightTexture0, float4(uvCookie.xy, 0, -8)).w;
            // We have two cones of light, right now. One forward and one backward. To
            // get rid of the backward, discard all light when W is positive.
            attenuation *= uvCookie.w < 0;

            #if defined(SHADOWS_DEPTH)
                shadowed = true;
                // Spotlight shadows are sampled with the UnitySampleShadowmap function,
                // which takes care of details regarding hard or soft shadows sampling.
                // It takes the fragment position in shadows space. The transformation
                // matrix to perform that conversion is the first element of the
                // unity_WorldToShadow array.
                shadowAttenuation = UnitySampleShadowmap(
                    mul(unity_WorldToShadow[0], float4(worldPos, 1))
                );
            #endif
        #else
            // Point lights cookies

            #if defined(POINT_COOKIE)
                float4 uvCookie = mul(unity_WorldToLight, float4(worldPos, 1));
                // The perspective division is omitted, according to the tutorial,
                // and I think that it's because W can be seen as a scaling factor for
                // the corresponding euclidian vector, and, since we are using this
                // vector to sample a cubemap (so only the direction is important)
                // the actual length of the vector is irrelevant.
                // To demonstrate this, the following scaling doesn't alter the
                // sampling.
                // uvCookie.xyz *= 100.0;
                attenuation *= texCUBEbias(_LightTexture0, float4(uvCookie.xyz, -8)).w;
            #endif

            #if defined(SHADOWS_CUBE)
                // Shadowmap for point lights are stored in cubemaps. The correct
                // sampling is done automatically via the UnitySampleShadowmap function.
                shadowed = true;
                shadowAttenuation = UnitySampleShadowmap(-lightVec);
            #endif
        #endif
    #endif

    // Since the assignment of shadowed is based on a pre-compiler defined
    // the entire shadow code is kept or removed based on the variable at compile
    // time. No performance loss.
    if (shadowed) {
        // Shadow Fade:
        // Shadows are calculated as far from the camera as the Shadow Distance
        // value in Quality Settings. To avoid cutoff, Unity standard shader fades the
        // shadows while approaching that limit. Here we do the same.
        // UnityComputeShadowFadeDistance returns the distance of the cutoff point from
        // a given fragment world position, according to the current Shadow Projection
        // type (Stable Fit or Close Fit).
        // UnityComputeShadowFade takes that distance and returns a [0, 1] range, based
        // on internal offset and scaling values.
        float shadowFadeDistance = UnityComputeShadowFadeDistance(worldPos, viewZ);
        float shadowFade = UnityComputeShadowFade(shadowFadeDistance);
        // Since shadowAttuenuation is 1 for no shadow and 0 for full shadow, the shadow
        // fade factor should left the shadowAttenuation unaltered when close to 1 and
        // progressively bringing it to 1 when it's less than one. So we add the
        // shadowFade to the shadowAttuenuation, clamping it to [0, 1].
        shadowAttenuation = saturate(shadowAttenuation + shadowFade);

        // Optimization: if we are outside the shadow distance we can skip the shadow
        // calculation (the expansive shadow sampling in particular) completely.
        // UNITY_BRANCH allows this and, I assume, this is working even if we are putting
        // it here, after all calculations, thanks to the compiler, which is smart enough
        // to calculate shadow fade before sampling and to skip shadow calculations
        // if they are not necessary.
        // However, branches would be expansive, but in this case they help optimizing
        // because, except for the edge of the shadow, all fragments either fall inside
        // or outside of it. But not all GPU can take advantage of this so called
        // 'Coherent branching', so we use the UNITY_FAST_COHERENT_DYNAMIC_BRANCHING
        // keyword to make sure that the target platform supports it.
        // Lastly, we only do this for point lights and spot lights with soft shadows
        // (described by the SHADOWS_SOFT keyword), because in those cases multiple shadow
        // map samples are involved. Direactional soft shadows use only one sample so
        // they are cheap.
        #if defined(UNITY_FAST_COHERENT_DYNAMIC_BRANCHING) && defined (SHADOWS_SOFT)
            UNITY_BRANCH
            if (shadowFade > 0.99) {
                shadowAttenuation = 1;
            }
        #endif
    }

    light.color = _LightColor.rgb * shadowAttenuation * attenuation;

    return light;
}

Interpolators VertexProgram (VertexData v) {
    Interpolators i;
    i.pos = UnityObjectToClipPos(v.vertex);
    #if defined (PLAIN_VERTEX_AS_UV)
        i.uv = v.vertex;
    #else
        // Conversion from Clip-space to Screen-space in homogeneous coordinates
        // See chapter on shadows for full details
        i.uv = ComputeScreenPos(i.pos);
    #endif
    // i.ray = v.normal;
    i.ray = lerp(
        // The specific meaning of this is obscure to me... spotlights.. tsk...
        UnityObjectToViewPos(v.vertex) * float3(-1, -1, 1),
        v.normal,
        _LightAsQuad
    );
    return i;
}

float4 FragmentProgram (Interpolators i) : SV_Target {

    // ---
    // Calculating UV

    #if defined (PLAIN_VERTEX_AS_UV)
        float2 uv = i.uv;
    #else
        // Conversion from Screen-space in homogeneous coordinates
        // to Screen-space in Euclidian coordinates.
        // Again: see chapter on shadows for full details
        float2 uv = i.uv.xy / i.uv.w;
    #endif
    
    // ---
    // Calculating Fragment World Position

    float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
    depth = Linear01Depth(depth);

    // Since rays are in view space (camera local space)
    // and reach the near plane, we devide them by Z to scale them till they have Z = 1,
    // then we multiply them by the far plane distance from camera (_ProjectionParams.z)
    // to scale them till they reach the far plane
    float3 rayToFarPlane = i.ray * _ProjectionParams.z / i.ray.z;
    // Then, by scaling them by the current fragment depth value,
    // we obtain the position of the fragment in view space.
    float3 viewPos = rayToFarPlane * depth;
    // Lastly, to get to fragment world position, we convert from view space to
    // world space using the unity_CameraToWorld matrix defined in ShaderVariables.
    // Note that we supply viewPos in homogeneous coordinates by appending 1, since
    // it's a position and we want to take translations into account.
    float3 worldPos = mul(unity_CameraToWorld, float4(viewPos, 1)).xyz;

    // ---
    // Calculating View Direction

    float3 viewDir = normalize(_WorldSpaceCameraPos - worldPos);
    
    // ---
    // GBuffer

    float3 albedo = tex2D(_CameraGBufferTexture0, uv).rgb;
    float3 specularTint = tex2D(_CameraGBufferTexture1, uv).rgb;
    float3 smoothness = tex2D(_CameraGBufferTexture1, uv).a;
    // Remember: normal decoding from having being stored in [0, 1]
    float3 normal = tex2D(_CameraGBufferTexture2, uv).rgb * 2 - 1;

    // ---
    // One-Minus-Reflectivity

    // Basically, reflectivity is the strongest component of the specular tint
    // which can be retrieved with the SpecularStrength function. Note that this is
    // the same way that the EnergyConservationBetweenDiffuseAndSpecular function
    // uses to calculate the oneMinusReflectivity. Actually, since we use that function
    // to calculate both albedo and oneMinusReflectivity when assigning the GBuffer, we
    // could also pass that value in the GBuffer to avoid to recalulate it now, but I
    // assume that there is simply no room left for that in the GBuffer.
    float oneMinusReflectivity = 1 - SpecularStrength(specularTint);

    // ---
    // Direct and Indirect Lights

    UnityLight light = CreateLight(uv, worldPos, viewPos.z);

    // Indirect light is not applicable in the deferred lighting (it is already
    // calculated in the GBuffer), so it remains always black here.
    UnityIndirect indirectLight;
    indirectLight.diffuse = 0;
    indirectLight.specular = 0;

    // ---
    // PBS

    float4 color = UNITY_BRDF_PBS(
        albedo,
        specularTint,
        oneMinusReflectivity,
        smoothness,
        normal,
        viewDir,
        light,
        indirectLight
    );

    #if !defined(UNITY_HDR_ON)
        // Logarithmically encode colors, when we work in LDR.
        color = exp2(-color);
    #endif

    return color;
}

#endif