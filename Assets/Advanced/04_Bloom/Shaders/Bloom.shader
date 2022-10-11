Shader "Custom/Bloom" {

    Properties {
        _MainTex ("Texture", 2D) = "white" {}
    }
    
    SubShader {
		
        // Typical cull and depth settings for post-process shaders
        Cull Off
        ZTest Always
        ZWrite Off

        CGINCLUDE
            #include "UnityCG.cginc"

            // _MainTex is a reserved keyword that Unity uses to store
            // the source texture in case the shader is used for a Blit operation
            sampler2D _MainTex, _SourceTex;
            // (1/width, 1/height, width, height), where width and height
            // are _MainTex's width and _MainTex's height respectively.
            float4 _MainTex_TexelSize;

            // The bloom effect expects that only the brighter pixels should be
            // added to the process. To do this we select bright pixels based on a
            // user defined threshold, so that the otherpixels are added as black pixel
            // to the final contribution.
            // half _Threshold;

            // To avoid cases of abrupt change of bloom contribution we can rely on
            // a soft threshold to smoothly fade from brightness 0 to the "hard knee"
            // contribution curve.
            // half _SoftThreshold;

            // Instead of using raw _Threshold and _SoftThreshold values we have
            // the client script pass all constant values needed by the prefilter step
            // to increase performance.
            half4 _Filter;

            // This value allows to tune bloom intensity to create artistic results.
            half _Intensity;

            struct VertexData {
                float4 vertex: POSITION;
                float2 uv: TEXCOORD0;
            };

            struct Interpolators {
                float4 pos: SV_POSITION;
                float2 uv: TEXCOORD0;
            };

            // We want only bright pixels to contribute to the bloom effect. We select
            // them in what is commonly called a prefilter step, where an input pixel
            // is transformed according to a given logic (not enough bright pixels
            // will be set to black, so they don't contribute to the bloom effect).
            half3 Prefilter (half3 c) {
                // brightness if defined as the channel with higher value
                half brightness = max(c.r, max(c.g, c.b));

                // Softening curve: the idea is to apply a soft value minimum value
                // for the contribution, instead of an hardcoded 0, which would cause
                // abrupt changes.
                // See the tutorial for in-depth math explaination for this curve.
                /* half knee = _Threshold * _SoftThreshold;
                half soft = brightness - _Threshold + knee;
                soft = clamp(soft, 0, 2 * knee);
                soft = soft * soft / (4 * knee + 0.00001);
                half threshold = _Threshold; */
                // Variant using _Filter data, to avoid calculating values that
                // stay constant for all frames.
                half soft = brightness - _Filter.y;
                soft = clamp(soft, 0, _Filter.z);
                soft = soft * soft * _Filter.w;
                half threshold = _Filter.x;

                // contribution is equal to (b - t) / b, where b = brightness
                // and t = threshold.
                half contribution = max(soft, brightness - threshold);
                // To avoid division by zero, clamp to a minimum of 0.00001.
                contribution /= max(brightness, 0.00001);
                return c * contribution;
            }

            half3 Sample (float2 uv) {
                return tex2D(_MainTex, uv).rgb;
            }

            half3 SampleBox (float2 uv, float delta) {
                // Calculating the vertices of a box of 2x2 texels,
                // centered in the origin
                // delta will be 1 when downsampling, resulting in a box with
                // unaltered size, while it will be 0.5 for upsampling, thus
                // halfing the size (see later)
                float4 o = _MainTex_TexelSize.xyxy * float2(-delta, delta).xxyy;
                // Sample all four vertices, relatively to the UV,
                // and return the avarage value.
                // NOTE: if using this shader to downsampling a texture to
                // half its resolution, this procudure will be followed by
                // a bilinear filtering, de-facto filtering using a mask
                // of 4x4 pixels (for each pixel of the destination texture
                // we would have 4 2x2 boxes which are downsampled to 1 pixel
                // via bilinear filtering). When using the shader for upsampling,
                // we need to avoid to sample too far away, otherwise we'll blur
                // the image too much. So we use a delta of 0.5 so we can sample
                // using a box that cover 3x3 texels, resulting in a more focused
                // kernel.
                half3 s =
                    Sample(uv + o.xy) + Sample(uv + o.zy) +
                    Sample(uv + o.xw) + Sample(uv + o.zw);
                return s * 0.25f;
            }

            Interpolators VertexProgram (VertexData v) {
                Interpolators i;
                i.pos = UnityObjectToClipPos(v.vertex);
                i.uv = v.uv;
                return i;
            }

        ENDCG

        Pass { // 0 - First Downsampling

            // The first downsampling pass apply the prefilter operation
            // that scale the pixel color based on its brightness, so that
            // darker pixels impact less on the bloom effect.

            CGPROGRAM
                #pragma vertex VertexProgram
			    #pragma fragment FragmentProgram

                // HDR values are typically stored in half-precision format
                // so we explicitly return a half4 type.
                half4 FragmentProgram (Interpolators i) : SV_Target {
                    return half4(Prefilter(SampleBox(i.uv, 1)), 1);
                    
                }
            ENDCG
        }

        Pass { // 1 - Intermediate Downsamplings

            CGPROGRAM
                #pragma vertex VertexProgram
			    #pragma fragment FragmentProgram

                // HDR values are typically stored in half-precision format
                // so we explicitly return a half4 type.
                half4 FragmentProgram (Interpolators i) : SV_Target {
                    return half4(SampleBox(i.uv, 1), 1);
                    
                }
            ENDCG
        }

        Pass { // 2 - Intermediate Upsamplings

            // The Bloom effect is achieved by summing blurred downsampled textures
            // with their corrisponding upsampled texture of the same size, thus
            // brightening and blurring the entire images. For intermediate iterations
            // this can be easily done via additive blending (Blend mode One One),
            // since the client script uses a downsampled texture as source to render
            // the upsampled texture with its same size. This is not true, however,
            // for the final pass (se the next pass for more details).
            Blend One One

            CGPROGRAM
                #pragma vertex VertexProgram
			    #pragma fragment FragmentProgram

                // HDR values are typically stored in half-precision format
                // so we explicitly return a half4 type.
                half4 FragmentProgram (Interpolators i) : SV_Target {
                    return half4(SampleBox(i.uv, 0.5), 1);
                    
                }
            ENDCG
        }

        Pass { // 3 - Final Upsampling

            // The final pass cannot rely on the fact that the source texture
            // has the same values as the original texture, so we manually add
            // the accumulated blurred textures to a _SourceTex variable that the
            // client script is expected to set to the original texture

            CGPROGRAM
                #pragma vertex VertexProgram
			    #pragma fragment FragmentProgram

                // HDR values are typically stored in half-precision format
                // so we explicitly return a half4 type.
                half4 FragmentProgram (Interpolators i) : SV_Target {
                    half4 c = tex2D(_SourceTex, i.uv);
                    c.rgb += _Intensity * SampleBox(i.uv, 0.5);
                    return c;
                    
                }
            ENDCG
        }

        Pass { // 4 - Debug Pass

            // The final pass cannot rely on the fact that the source texture
            // has the same values as the original texture, so we manually add
            // the accumulated blurred textures to a _SourceTex variable that the
            // client script is expected to set to the original texture

            CGPROGRAM
                #pragma vertex VertexProgram
			    #pragma fragment FragmentProgram

                // HDR values are typically stored in half-precision format
                // so we explicitly return a half4 type.
                half4 FragmentProgram (Interpolators i) : SV_Target {
                    return half4(_Intensity * SampleBox(i.uv, 0.5), 1);
                    
                }
            ENDCG
        }
	}
}