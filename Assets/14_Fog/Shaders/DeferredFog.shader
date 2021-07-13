Shader "Custom/Deferred Fog"
{
    Properties
    {
        _MainTex ("Source", 2D) = "white" {}
    }
    SubShader
    {
        // This shader will draw to a full-screen quad that will cover everythis
        // so we must ignore cull (actually I think it's more an optional optimization),
        // make sure that depth tests always succeed (so it covers everything)
        // and nothing is written on the depth buffer (to allow further rendering passes
        // to stack on top of the fog. Not entirely sure, though).
        Cull Off
        ZTest Always
        ZWrite Off
        
        Pass
        {
            CGPROGRAM

            #pragma vertex VertexProgram
			#pragma fragment FragmentProgram

            #pragma multi_compile_fog

            //#define FOG_DISTANCE
            // Enable/Disable fog over skybox
            //#define FOG_SKYBOX

            #include "UnityCG.cginc"

            sampler2D _MainTex;
            // The Deferred Path fills a depth buffer as one of its initial steps,
            // need by the light passes to work. We can take advantage of it
            // to create Depth-Based fog by declaring the following sampler2D.
            // NOTE: this seems to be not valid for all platform and using
            // the UNITY_DECLARE_DEPTH_TEXTURE macro seems the correct approach
            // (see DeferredLightingShared.cginc for more details)
            sampler2D _CameraDepthTexture;

            // Corner rays used to calculate all rays through the screen-pixels
            // to the far plane.
            // Note that, even if they are passed as a Vector4 array we can just
            // declare a float3 array, since it's what we need.
            // Also note that there is no need to declare any property for this
            // since we don't need to edit them in the Inspector.
            float3 _FrustumCorners[4];

            struct VertexData {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Interpolators {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;

                #if defined(FOG_DISTANCE)
                    float3 ray : TEXCOORD1;
                #endif
            };

            Interpolators VertexProgram(VertexData v) {
                Interpolators i;
                i.pos = UnityObjectToClipPos(v.vertex);
                i.uv = v.uv;
                #if defined(FOG_DISTANCE)
                    i.ray = _FrustumCorners[v.uv.x + 2 * v.uv.y];
                #endif
                return i;
            }

            float4 FragmentProgram(Interpolators i) : SV_Target {
                // The exact syntax to sample the depth buffer depends on the target
                // platform. Therefore we use the SAMPLE_DEPTH_TEXTURE of HLSLSupport
                // to sample the depth value for the current UV.
                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
                // Raw depth values are in clip-space. So we have to convert them to
                // world space coordinates. We can use Linear01Depth of UnityCG which
                // performs a simple conversion to linear world space coordinates in
                // [0-1] where 0 is the camera position and 1 is the far plane.
                depth = Linear01Depth(depth);
                // Next we have to convert the depth value from [0, 1]
                // to [nearPlan, farPlane].
                // _ProjectionParams is a float4 containing the clip space settings,
                // defined in UnityShaderVariables. The Z component is the far plane's
                // distance while the Y component is the near plane's distance.
                // Since we are working in a converted space, this calculation won't
                // produce exact results, but it's accetpable and that's also the way
                // the standard shader behaves.
                float viewDistance = depth * _ProjectionParams.z - _ProjectionParams.y;
                #if defined(FOG_DISTANCE)
                    viewDistance = length(i.ray * depth);
                #endif

                // Calculate fog factor based on view distance
                // and fog type (linear, exp or exp2)
                UNITY_CALC_FOG_FACTOR_RAW(viewDistance);
                unityFogFactor = saturate(unityFogFactor);
                #if !defined(FOG_SKYBOX)
                    // This is to avoid the skybox to be covered by full strength fog
                    if (depth > 0.9999) {
                        unityFogFactor = 1;
                    }
                #endif
                #if !defined(FOG_LINEAR) && !defined(FOG_EXP) && !defined(FOG_EXP2)
                    unityFogFactor = 1;
                #endif

                float3 sourceColor = tex2D(_MainTex, i.uv).rgb;
                float3 foggedColor = lerp(unity_FogColor.rgb, sourceColor, unityFogFactor);

                return float4(foggedColor, 1);
            }

            ENDCG
        }
    }
}
