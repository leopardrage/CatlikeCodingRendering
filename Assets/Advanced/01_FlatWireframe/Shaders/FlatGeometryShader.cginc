#if !defined(FLAT_GEOMETRY_SHADER)
#define FLAT_GEOMETRY_SHADER

#include "FlatGeometryShared.cginc"

// InterpolatorsVertex is the output type of the vertex shader, but vertices
// are not interpolated yet, so the type name is misleading here, but we'll rename
// it another time in something more meaningful (e.g. VertexProgramOutput).

// Next to it, we need to explicitely declare the number of vertices expected
// as input (we set this to 3, since we are working with model made of triangles).
// Also, before it we have to specify the type of shape in which those vertices are
// arranged (in our case "triangle").

// maxvertexcount declare the number of vertices we plan to output from the
// geometry program.

// Since we will output multiple vertices, we won't return a single instance:
// we'll write to a stream, whose type depend on what we want to output (triangles
// in our case). The stream type also expects a C#-style generic to specify the type
// for each output vertex.
[maxvertexcount(3)]
void MyGeometryProgram (triangle InterpolatorsVertex i[3],
inout TriangleStream<InterpolatorsVertex> stream) {

    // Ahh, this is easy (once in a long while)
    float3 p0 = i[0].worldPos.xyz;
    float3 p1 = i[1].worldPos.xyz;
    float3 p2 = i[2].worldPos.xyz;

    float3 triangleNormal = normalize(cross(p1 - p0, p2 - p1));

    i[0].normal = triangleNormal;
    i[1].normal = triangleNormal;
    i[2].normal = triangleNormal;

    stream.Append(i[0]);
    stream.Append(i[1]);
    stream.Append(i[2]);
}

#endif