#if !defined(TESSELLATION_TESSELLATION_SHARED)
#define TESSELLATION_TESSELLATION_SHARED

// This struct allows the vertex program to forward VertexData to the tessellation
// stage. This is needed because the tessellation stage expects an INTERNALTESSPOS
// semantic for the vertex position. The other fields can stay the same as VertexData
struct TessellationControlPoint {
    float4 vertex : INTERNALTESSPOS;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 uv : TEXCOORD0;
    float2 uv1 : TEXCOORD1;
    float2 uv2 : TEXCOORD2;
};

// This struct contains the info to instruct the tessellation stage on how
// to subdivide the patch.
struct TessellationFactors {
    float edge[3] : SV_TessFactor;
    float inside : SV_InsideTessFactor;
};

float _TessellationUniform;
float _TessellationEdgeLength;

// This is an alternative version of the TessellationEdgeFactor function right below
// which uses the view distance tessellation edge logic, but using control points
// already converted to world space (needed to workaround an OpenGL Core bug. See later)
float TessellationEdgeFactor(float3 p0, float3 p1) {
    #if defined(_TESSELLATION_EDGE)
        float edgeLength = distance(p0, p1);
        float3 edgeCenter = (p0 + p1) * 0.5;
        float viewDistance = distance(edgeCenter, _WorldSpaceCameraPos);
        return (edgeLength * _ScreenParams.y) / (_TessellationEdgeLength * viewDistance);
    #else
        return _TessellationUniform;
    #endif
}

float TessellationEdgeFactor (
    TessellationControlPoint cp0,
    TessellationControlPoint cp1
) {
    #if defined(_TESSELLATION_EDGE)

        //
        // VIEW DISTANCE
        //

        // This method solve the current problem of the "screen space" method below:
        // if a long edge is close to the camera but lies almost orthogonally to the
        // camera direction, it won't be subdivided (and it should be). Using the
        // distance of the edge from the camera instead of the screen space edge length
        // help to solve this problem.

        // Calculate the edge length in world space
        float3 p0 = mul(unity_ObjectToWorld, float4(cp0.vertex.xyz, 1)).xyz;
        float3 p1 = mul(unity_ObjectToWorld, float4(cp1.vertex.xyz, 1)).xyz;
        float edgeLength = distance(p0, p1);

        // Calculate the midpoint of the edge
        float3 edgeCenter = (p0 + p1) * 0.5;
        // Calculate the distance between the camera and the edge (represented by
        // its midpoint) in world space
        float viewDistance = distance(edgeCenter, _WorldSpaceCameraPos);

        // Divide the edge by the threshold factor, scaled by the distance between
        // the edge and the camera. To keep tessellation dependent on the display size,
        // we scale the edge length by the screen height (it doesn't take display
        // width into account, but it's enough to create kind of dependency to the
        // screen size)
        return (edgeLength * _ScreenParams.y) / (_TessellationEdgeLength * viewDistance);
        
        //
        // SCREEN SPACE
        //
/* 
        // Convert vertex position to clip space
        float4 p0 = UnityObjectToClipPos(cp0.vertex);
        float4 p1 = UnityObjectToClipPos(cp1.vertex);
        // Divide them by the W, to project them to the screen
        float2 screenSpacePoint0 = p0.xy / p0.w;
        float2 screenSpacePoint1 = p1.xy / p1.w;
        // Multiply the screen space point by the screen size to convert it to pixels.
        screenSpacePoint0.x = screenSpacePoint0.x * _ScreenParams.x;
        screenSpacePoint0.y = screenSpacePoint0.y * _ScreenParams.y;
        screenSpacePoint1.x = screenSpacePoint1.x * _ScreenParams.x;
        screenSpacePoint1.y = screenSpacePoint1.y * _ScreenParams.y;

        // Calculate the edge length as distance in pixels
        float edgeLength = distance(screenSpacePoint0, screenSpacePoint1);

        // Divide the edge by the threshold factor
        return edgeLength / _TessellationEdgeLength; */

        //
        // WORLD SPACE
        //
/* 
        // Calculate the edge length in world space
        float3 p0 = mul(unity_ObjectToWorld, float4(cp0.vertex.xyz, 1)).xyz;
        float3 p1 = mul(unity_ObjectToWorld, float4(cp1.vertex.xyz, 1)).xyz;
        float edgeLength = distance(p0, p1);

        // Divide the edge by the threshold factor
        return edgeLength / _TessellationEdgeLength; */
    #else
        return _TessellationUniform;
    #endif
}

// This function is invoked once per patch and return the info needed by
// the tessellation stage to subdivide the patch.
TessellationFactors MyPatchConstantFunction (InputPatch<TessellationControlPoint, 3> patch) {
    // This variant of the former procedure converts control points to world space
    // before calculating the tessellation factors. This is a workaround for bug in
    // the generation of the OpenGL Core, that causes the execution of the
    // TessellationEdgeFactor (whose original implementation autonomously converted
    // control points to world space) to wrongly assig the inside tessellation factor.
    // This is because code optimizations, that takes place while converting
    // ShaderLab code to OpenGL Core code, caused the trasformed control points to be
    // wrongly accessed (the inside factor used wrong indexes for accessing the
    // correct control points).
    float3 p0 = mul(unity_ObjectToWorld, patch[0].vertex).xyz;
    float3 p1 = mul(unity_ObjectToWorld, patch[1].vertex).xyz;
    float3 p2 = mul(unity_ObjectToWorld, patch[2].vertex).xyz;
    TessellationFactors f;
    f.edge[0] = TessellationEdgeFactor(p1, p2);
    f.edge[1] = TessellationEdgeFactor(p2, p0);
    f.edge[2] = TessellationEdgeFactor(p0, p1);
    f.inside = (
        TessellationEdgeFactor(p1, p2) +
        TessellationEdgeFactor(p2, p0) +
        TessellationEdgeFactor(p0, p1)
    ) * (1 / 3.0);

    // Code affected by the OpenGL Core bug that causes inside factors to be
    // wrongly assigned
    /* TessellationFactors f;
    f.edge[0] = TessellationEdgeFactor(patch[1], patch[2]);
    f.edge[1] = TessellationEdgeFactor(patch[2], patch[0]);
    f.edge[2] = TessellationEdgeFactor(patch[0], patch[1]);
    f.inside = (f.edge[0] + f.edge[1] + f.edge[2]) * (1 / 3.0); */
    return f;
}

// The hull program is the first step of the tessellation stage.
// It can work with triangles, quads or isolines.
// It operates on a surface patch, passed as an InputPatch argument.

// A patch is a collection of vertices. InputPatch needs a generic to specify
// the data format of those vertices (as for the output stream of the geometry shader)
// Moreover, as a second template parameter we have to specify the number of vertices
// contained in wach patch (3, in our case, since we are dealing with triangles)

// A hull program output a single vertex per invocation. So, for triangular patches,
// the hull program will be called 3 times for the same shape. A second argument
// provide the ID for the current vertex of the patch, with the SV_OutputControlPointId
// semantic.

// As outout we specify the data structure to be forwarded to the domain shader.
// Also we have to specify that we are working with triangles and that we will output 3
// control points per patch, on for each triangle corners.
// Moreover, we have to specify whether we want triangles defined clockwise or
// counterclockwise. We want the clockwise-defined, as Unity wants them.
// We also need to specify the partitiong method (see more later)
// Lastly we have to provide a function that returns the number of part in which the
// the patch should be cut.
[UNITY_domain("tri")]
[UNITY_outputcontrolpoints(3)]
[UNITY_outputtopology("triangle_cw")]
// This partioning mode subdivide patches rounding tessellation factors to the
// next integer (ceil)
//[UNITY_partitioning("integer")]
// Same as integer partition mode for odd integer factors. All values between create
// edges, grow, shrink and merge to smoothly translate to the next odd integer factor.
[UNITY_partitioning("fractional_odd")]
// Same as fractional_odd but using even integer number as referring values.
// NOTE: this is less preferred than fractional_odd, because it forces a minimum of
// factor 2, while fractional_odd can deal with factor 1.
//[UNITY_partitioning("fractional_even")]
[UNITY_patchconstantfunc("MyPatchConstantFunction")]
TessellationControlPoint MyHullProgram (
    InputPatch<TessellationControlPoint, 3> patch,
    uint id : SV_OutputControlPointId
) {
    return patch[id];
}

// The domain program generates the vertices of the final triangles
// It uses the UNITY_domain annotation to specify the shape of the output vertices
// (as for the hull shader)
// It takes the tassellation factors, an OutputPatch (with templates identical to the
// hull shader InputPatch) and barycentric coordinates. These last ones allow
[UNITY_domain("tri")]
InterpolatorsVertex MyDomainProgram(
    TessellationFactors factors,
    OutputPatch<TessellationControlPoint, 3> patch,
    float3 barycentricCoordinates : SV_DomainLocation
) {
    VertexData data;

    // This macro perform the linear interpolation of a generic field of the
    // patch result by the tessellation stage, using the given barycentric coordinates.
    #define MY_DOMAIN_PROGRAM_INTERPOLATE(fieldName) data.fieldName = \
        patch[0].fieldName * barycentricCoordinates.x + \
        patch[1].fieldName * barycentricCoordinates.y + \
        patch[2].fieldName * barycentricCoordinates.z;

    // We use our convenient macro to linearly interpolate all fields of the
    // current patch
    MY_DOMAIN_PROGRAM_INTERPOLATE(vertex)
    MY_DOMAIN_PROGRAM_INTERPOLATE(normal)
    MY_DOMAIN_PROGRAM_INTERPOLATE(tangent)
    MY_DOMAIN_PROGRAM_INTERPOLATE(uv)
    MY_DOMAIN_PROGRAM_INTERPOLATE(uv1)
    MY_DOMAIN_PROGRAM_INTERPOLATE(uv2)

    // We have to convert the final VertexData to InterpolatorsVertex, expected
    // by the next stage. This is because the domain shader is taking care of
    // vertex conversion to clip space, while the vertex program simply forward 
    // VertexDatas (see MyTessellationVertexProgram).
    return MyVertexProgram(data);
}

// The domain shader will take care of converting all vertices to clip space
// using the usual MyVertexProgram. Therefore, the vertex stage must simply faceforward
// The original VertexData, unmodified, to the next stage (the Tessellation stage).
// Note that we must use our new TessellationControlPoint struct, because the
// tessellation stage needs a specific semantic for the vertex position.
TessellationControlPoint MyTessellationVertexProgram (VertexData v) {
    TessellationControlPoint p;
    p.vertex = v.vertex;
    p.normal = v.normal;
    p.tangent = v.tangent;
    p.uv = v.uv;
    p.uv1 = v.uv1;
    p.uv2 = v.uv2;
    return p;
}

#endif