Shader "Custom/DeferredLighting"
{
    Properties
    {
    }
    SubShader
    {
        Pass
        {
            // Since we want to add the lights contribution on top of each other
            // we use an additive One One Blend Mode.
            // However, with LDR we want to have a multiplicative (DstColor Zero) Blend
            // Mode, because encoded LDR colors have to be multiplied into the light
            // buffer (why... my guess is that this is because it's the way to go
            // when accumulating logarithmically encoded values).
            // To handle both scenarios, we use the _SrdBlend and _DstBlend variables
            // declared and assigned by Unity to have the correct blend mode for both
            // HDR and LDR.
            Blend [_SrcBlend] [_DstBlend]
            // Cull and ZTest are forced to Cull Back and Ztest LessEqual
            // No sense in defining them
            // Cull Off
            // ZTest Always
            ZWrite Off

            CGPROGRAM

            #pragma target 3.0
            #pragma vertex VertexProgram
            #pragma fragment FragmentProgram

            #pragma exclude_renderers nomrt

            // multi_compile_lightpass creates keywords for
            // all possible light configurations
            #pragma multi_compile_lightpass
            #pragma multi_compile _ UNITY_HDR_ON

            #include "DeferredLightingShared.cginc"

            ENDCG
        }

        // The second pass is used for LDR rendering to decode from the LDR
        // logarithmic encoding.
        Pass
        {
            Cull Off
            ZTest Always
            ZWrite Off

            // This is needed to show skybox in LDR
            Stencil {
                // I suppose that, behind the scene, at the beginning of the rendering loop
                // Unity clear the stencil buffer to a "Background value", then, 
                // in some pass afterwards, set "_StencilNonBackground" to the stencil
                // buffer for all pixeles covered by the scene's geometry.
                // So, we can avoid rendering on the background by masking it using the
                // geometry. This is done by setting the Stencil Test logic so that
                // every pixel that has a stencil "value" equal to _StencilNonBackground
                // (because it belongs to the geomtry) is rendered.
                // The others are discarded.
                Ref [_StencilNonBackground]
                ReadMask [_StencilNonBackground]
                CompBack Equal
                CompFront Equal
            }

            CGPROGRAM

            #pragma target 3.0
            #pragma vertex VertexProgram
            #pragma fragment FragmentProgram

            #pragma exclude_renderers nomrt

            #include "UnityCG.cginc"

             struct VertexData {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Interpolators {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            sampler2D _LightBuffer;

            Interpolators VertexProgram (VertexData v) {
                Interpolators i;
                i.pos = UnityObjectToClipPos(v.vertex);
                i.uv = v.uv;
                return i;
            }

            float4 FragmentProgram (Interpolators i) : SV_Target {
                // Decode LDR values before returning them
                return -log2(tex2D(_LightBuffer, i.uv));
            }

            ENDCG
        }
    }
}
