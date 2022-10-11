#if !defined(WIREFRAME_GEOMETRY_SHADER)
#define WIREFRAME_GEOMETRY_SHADER

// This macro adds a the barycentric coordinates to the Interpolators struct
// defined in the FlatWireframeShared.cginc.
// We also use it in the our InterpolatorsGeometry in this file.
#define CUSTOM_GEOMETRY_INTERPOLATORS \
    float2 barycentricCoordinates : TEXCOORD9; 

#include "WireframeInputIncludedShared.cginc"

float3 _WireframeColor;
float _WireframeSmoothing;
float _WireframeThickness;

// We define a custom albedo function using the ALBEDO_FUNCTION macro
// This is possible because we moved the GetAlbedo function in a separate file
// (WireframeInputIncludedShared.cginc) and making the rest of the lighting code
// (WireframeShared.cginc) using a generic ALBEDO_FUNCTION macro to access albedo.
float3 GetAlbedoWithWireframe (Interpolators i) {
    float3 albedo = GetAlbedo(i);
    float3 barys;
    barys.xy = i.barycentricCoordinates;
    // retrieveing the third barycentric coordinate
    barys.z = 1 - barys.x - barys.y;
    // As range for the smoothstep function we provide the rate of change of the
    // baricentric coordinates in screen space. This allows us to have a fixed width for
    // the wireframe. Since that range must be a positive contribution of the rate of
    // change on both the X and the Y screen coordinates, we return the sum of the
    // absolute partial screen space derivatives of the barycentric coordinates.
    // fwidth is defined exactly as the commented expression right below.
    float3 deltas = fwidth(barys);
    // float3 deltas = abs(ddx(barys) + abs(ddy(barys)));

    // Both smoothing and thickness value depends by deltas, to keep the same visual
    // appearance of the wire everywhere on the screen.
    float3 smoothing = deltas * _WireframeSmoothing;
    float3 thickness = deltas * _WireframeThickness;
    
    // The smoothstep function is like a linear interpolation with sort of an S-like
    // progression: it starts slowly, rise up quickly in the middle and finishes slowly
    // again. The fact that the rise up quicly allow us to have a quick fade at the sides
    // of the wires.
    // By translating ahead the smoothing interval, we increase the thickness of the wire,
    // because we increase the threshold below which the smoothstep returns 0.
    // To steer the fading part of the wire, we add the smoothing factor to the second
    // parameter, thus increasing the range where the smoothstep function returns value
    // in (0, 1).
    barys = smoothstep(thickness, thickness + smoothing, barys);
    // barys = smoothstep(0, deltas, barys);

    // we use the minimum barycentric coordinate to the one more close
    // to the border.
    // Also note that we perform the smoothstep on all barycentric coordinates before
    // getting the minimum instead of otherwise (which would have been cheaper). This
    // is to avoid aliasing that we would have in places where edges changes to quickly.
    float minBary = min(barys.x, min(barys.y, barys.z));

    // Lerping between the wireframe color and the albedo based on the resulting
    // minimum barycentric coordinate.
    return lerp(_WireframeColor, albedo, minBary);
}

#define ALBEDO_FUNCTION GetAlbedoWithWireframe

#include "WireframeShared.cginc"

struct InterpolatorsGeometry {
    InterpolatorsVertex data;
    CUSTOM_GEOMETRY_INTERPOLATORS
};

[maxvertexcount(3)]
void MyGeometryProgram (triangle InterpolatorsVertex i[3],
inout TriangleStream<InterpolatorsGeometry> stream) {

    // Calculating and assigning triangle normal
    float3 p0 = i[0].worldPos.xyz;
    float3 p1 = i[1].worldPos.xyz;
    float3 p2 = i[2].worldPos.xyz;

    float3 triangleNormal = normalize(cross(p1 - p0, p2 - p1));

    i[0].normal = triangleNormal;
    i[1].normal = triangleNormal;
    i[2].normal = triangleNormal;

    InterpolatorsGeometry g0, g1, g2;
    g0.data = i[0];
    g1.data = i[1];
    g2.data = i[2];

    // See the tutorial for a quick reminder about barycentric coordinates.
    // Anyway, assigning the coordinates this way for each vertex (we are taking
    // advantage of dealing with triangles, of course) the interpolators will
    // automatically give us the correct barycentric coordinates for any fragment.
    // Regarding our wireframe goal: in the fragment shader, barycentric coordinates
    // with a component close to zero means that we are on the edge.
    // (No need of three coordinates, see later)
    // g0.barycentricCoordinates = float3(1, 0, 0);
    // g1.barycentricCoordinates = float3(0, 1, 0);
    // g2.barycentricCoordinates = float3(0, 0, 1);
    // Also: barycentric coordinates has the peculiarity of having their sum equal to 1.
    // This means that we can just interpolate 2 coordinates and derive the third
    // by subtructing the other 2 from 1 (z = 1 - (x + y)), avoiding interpolating
    // an additional value (better performance).
    g0.barycentricCoordinates = float2(1, 0);
    g1.barycentricCoordinates = float2(0, 1);
    g2.barycentricCoordinates = float2(0, 0);

    stream.Append(g0);
    stream.Append(g1);
    stream.Append(g2);
}

#endif