#if !defined(TRIPLANAR_MAPPING_TRIPLANAR_MAPPING_INCLUDED)
#define TRIPLANAR_MAPPING_TRIPLANAR_MAPPING_INCLUDED

#define NO_DEFAULT_UV

#include "TriplanarMappingInputIncludedShared.cginc"

sampler2D _MOHSMap;
float _MapScale;
float _BlendOffset;
float _BlendExponent;
float _BlendHeightStrength;

sampler2D _TopMainTex, _TopMOHSMap, _TopNormalMap;

struct TriplanarUV {
    float2 x, y, z;
};

TriplanarUV GetTriplanarUV (SurfaceParameters parameters) {
    TriplanarUV triUV;
    float3 p = parameters.position * _MapScale;
    triUV.x = p.zy; // yz would provide a rotation in the unwanted direction
    triUV.y = p.xz;
    triUV.z = p.xy;

    // Assuming that we are using the normal vector to weight our uv
    // projections (see both usage and implementation of GetTriplanarWeights)
    // we should invert some axis values in case based on the sign of the normal
    // components.
    if (parameters.normal.x < 0) {
        triUV.x.x = -triUV.x.x;
    }
    if (parameters.normal.y < 0) {
        triUV.y.x = -triUV.y.x;
    }
    if (parameters.normal.z >= 0) {
        triUV.z.x = -triUV.z.x;
    }

    // We apply a shift of 0.5 to restore the correct alignment of the test
    // texture on not-axis-aligned meshes such as spheres (although, this way
    // it doesn't seem so much more aligned than before to me...). Anyway, these
    // values are specific of the test texture and should be changed if using a
    // different texture that requires precise alignment (such as when texts appear
    // in the texture). However, since triplanar mapping is usually used with terrains,
    // we won't need to worry about this issue.
    triUV.x.y += 0.5;
    triUV.z.x += 0.5;

    return triUV;
}

float3 GetTriplanarWeights (
    SurfaceParameters parameters, float heightX, float heightY, float heightZ
    ) {
    // The best orientation is most likely the one most oriented toward
    // the normal. So each world axis would be weighted by their
    // corresponding normal coordinate.
    // Normals can be negative so we use their absolute value.
    // Of course, when normals are negative we would end up with mirrored
    // textures, but we took that into account in GetTriplanarUV.
    // Also the sum of the weights must be 1, so we normalize them
    // by dividing them by their sum.
    float3 triW = abs(parameters.normal);

    // Using an offset we can tweak the weights composition.
    // The higher the weight, the smaller the blend region becomes.
    triW = saturate(triW - _BlendOffset);

    triW *= lerp(1, float3(heightX, heightY, heightZ), _BlendHeightStrength);

    // Raising the resulting weights to a user-defined exponent is another
    // way to compress smaller values and highlight higher values. Same
    // goal as the offset approach, but with a smoother behaviour.
    triW = pow(triW, _BlendExponent);

    return triW / (triW.x + triW.y + triW.z);
}

float3 BlendTriplanarNormal (float3 mappedNormal, float3 surfaceNormal) {
    float3 n;
    // Whiteout blending: blending tweak the exaggerates X and Y components,
    // thus producting more pronunced bumps along steep slopes. See Bumpiness
    // Tutorial for the first application of this method.
    n.xy = mappedNormal.xy + surfaceNormal.xy;
    n.z = mappedNormal.z * surfaceNormal.z;
    return n;
}

void MyTriplanarSurfaceFunction (
    inout SurfaceData surface, SurfaceParameters parameters
) {
    TriplanarUV triUV = GetTriplanarUV(parameters);

    float3 albedoX = tex2D(_MainTex, triUV.x).rgb;
    float3 albedoY = tex2D(_MainTex, triUV.y).rgb;
    float3 albedoZ = tex2D(_MainTex, triUV.z).rgb;

    float4 mohsX = tex2D(_MOHSMap, triUV.x);
    float4 mohsY = tex2D(_MOHSMap, triUV.y);
    float4 mohsZ = tex2D(_MOHSMap, triUV.z);

    float3 tangentNormalX = UnpackNormal(tex2D(_NormalMap, triUV.x));
    float4 rawNormalY = tex2D(_NormalMap, triUV.y);
    float3 tangentNormalZ = UnpackNormal(tex2D(_NormalMap, triUV.z));

    #if defined(_SEPARATE_TOP_MAPS)
        if (parameters.normal.y > 0) {
            albedoY = tex2D(_TopMainTex, triUV.y).rgb;
            mohsY = tex2D(_TopMOHSMap, triUV.y);
            rawNormalY = tex2D(_TopNormalMap, triUV.y);
        }
    #endif
    float3 tangentNormalY = UnpackNormal(rawNormalY);

    // Fixing mirroring. Same as for UVs (see GetTriplanarUV).
    if (parameters.normal.x < 0) {
        tangentNormalX.x = -tangentNormalX.x;
    }
    if (parameters.normal.y < 0) {
        tangentNormalY.x = -tangentNormalY.x;
    }
    if (parameters.normal.z >= 0) {
        tangentNormalZ.x = -tangentNormalZ.x;
    }

    // Need to swap axis for X and Y normal to rotate the tangent space so
    // that they match their axis. Z is fine as it is.
    // It's a bit confusing: theoretically we want to convert
    // parameters.normal (which is in world space) to the tangent space
    // of the given axis, blend it with the sampled normal (already in tangent space)
    // and then rotate back to world space. I know that the "tangent space
    // of the given axis" thing is a little foggy, but it makes sense somehow.
    float3 worldNormalX = 
        BlendTriplanarNormal(tangentNormalX, parameters.normal.zyx).zyx;
    float3 worldNormalY = 
        BlendTriplanarNormal(tangentNormalY, parameters.normal.xzy).xzy;
    float3 worldNormalZ = 
        BlendTriplanarNormal(tangentNormalZ, parameters.normal);

    float3 triW = GetTriplanarWeights(parameters, mohsX.z, mohsY.z, mohsZ.z);

    surface.albedo = albedoX * triW.x + albedoY * triW.y + albedoZ * triW.z;

    float4 mohs = mohsX * triW.x + mohsY * triW.y + mohsZ * triW.z;
    surface.metallic = mohs.x;
    surface.occlusion = mohs.y;
    surface.smoothness = mohs.a;

    surface.normal = normalize(
        worldNormalX * triW.x + worldNormalY * triW.y + worldNormalZ * triW.z
    );
}

#define SURFACE_FUNCTION MyTriplanarSurfaceFunction

#endif