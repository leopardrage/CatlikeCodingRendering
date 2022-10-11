#if !defined(TRIPLANAR_MAPPING_SURFACE_SHARED)
#define TRIPLANAR_MAPPING_SURFACE_SHARED

struct SurfaceData {
    float3 albedo, emission, normal;
    float alpha, metallic, occlusion, smoothness;
};

struct SurfaceParameters {
    float3 normal, position;
    float4 uv;
};

#endif