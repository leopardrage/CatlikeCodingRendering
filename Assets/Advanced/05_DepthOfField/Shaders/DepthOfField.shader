Shader "Hidden/DepthOfField" {

    Properties {
        _MainTex ("Texture", 2D) = "white" {}
    }

    CGINCLUDE
        #include "UnityCG.cginc"

        sampler2D _MainTex, _CameraDepthTexture, _CoCTex, _DoFTex;
        float4 _MainTex_TexelSize;

        float _FocusDistance, _FocusRange, _BokehRadius;

        struct VertexData {
            float4 vertex: POSITION;
            float2 uv: TEXCOORD0;
        };

        struct Interpolators {
            float4 pos: SV_POSITION;
            float2 uv: TEXCOORD0;
        };

        Interpolators VertexProgram (VertexData v) {
            Interpolators i;
            i.pos = UnityObjectToClipPos(v.vertex);
            i.uv = v.uv;
            return i;
        }

    ENDCG
    
    SubShader {
		
        // Typical cull and depth settings for post-process shaders
        Cull Off
        ZTest Always
        ZWrite Off

        Pass { // 0 circleOfConfusionPass
            CGPROGRAM
                #pragma vertex VertexProgram
			    #pragma fragment FragmentProgram
                
                half FragmentProgram (Interpolators i) : SV_Target {
                    half depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
                    depth = LinearEyeDepth(depth);

                    float coc = (depth - _FocusDistance) / _FocusRange;
                    coc = clamp(coc, -1, 1) * _BokehRadius;
                    return coc;
                }
            ENDCG
        }

        Pass { // 1 preFilterPass
            CGPROGRAM
                #pragma vertex VertexProgram
			    #pragma fragment FragmentProgram

                half Weigh(half3 c) {
                    // The brighter the color, the lesser the weight
                    // white (1, 1, 1) -> weight == 1/2 (minimum value)
                    // red   (1, 0, 0) -> weight == 1/2 (minimum value)
                    // black (0, 0, 0) -> weight == 1 (maximum value)
                    return 1 / (1 + max(max(c.r, c.g), c.b));
                }
                
                half4 FragmentProgram (Interpolators i) : SV_Target {
                    // Get the UV offsets to the center of the 4 coc pixels in the
                    // source texture around the current pixel of the destinaion
                    // texture. Than sample the COC texture with offset UVs to 
                    // get the unaltered coc samples (if sampling in the center
                    // of the pixel, bilinear filter doesn't do anything),
                    // process them according to our prefilter logic (see later)
                    // and store the resulting coc value in the alpha channel.
                    // NOTE: this is what the Texture Gather function does,
                    // which is commonly provided by most graphics libraries.
                    // See: https://docs.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-to-gather
                    // and: https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/textureGather.xhtml
                    // However the tutorial doesn't use it because it says it
                    // not universally supported. However, shader graph has
                    // a dedicated node for that: https://docs.unity3d.com/Packages/com.unity.shadergraph@12.1/manual/Gather-Texture-2D-Node.html
                    // even with some gotchas based on the target platform (see the link).
                    float4 offset = _MainTex_TexelSize.xyxy * float2(-0.5, 0.5).xxyy;
                    half coc0 = tex2D(_CoCTex, i.uv + offset.xy).r;
                    half coc1 = tex2D(_CoCTex, i.uv + offset.zy).r;
                    half coc2 = tex2D(_CoCTex, i.uv + offset.xw).r;
                    half coc3 = tex2D(_CoCTex, i.uv + offset.zw).r;

                    // This is what the bilinear filter would do, but we don't
                    // want that, because we are dealing with values resulting
                    // from the depth texture, and avaraging them would be wrong.
                    // half coc = (coc0 + coc1 + coc2 + coc3) * 0.25;

                    // We use the most extreme value as our resulting coc
                    half cocMin = min(min(min(coc0, coc1), coc2), coc3);
                    half cocMax = max(max(max(coc0, coc1), coc2), coc3);
                    half coc = cocMax >= -cocMin ? cocMax : cocMin;

                    // To achieve a better visual effect we want to tone down
                    // the bokeh, so it has a lesser impact on the overall image.
                    // To do this, instead of simply sampling _MainTex with i.uv (and
                    // relying on the bilinear filter to take the avarage values
                    // between the four surrounding samples), we sample each original
                    // sorrounding sample and use their contribute based on an averaged
                    // weight.
                    // The weigh function will return a weight inversely proportional
                    // to the brightness of the pixel, resulting in less weight
                    // for brighter pixels.
                    half3 s0 = tex2D(_MainTex, i.uv + offset.xy).rgb;
                    half3 s1 = tex2D(_MainTex, i.uv + offset.zy).rgb;
                    half3 s2 = tex2D(_MainTex, i.uv + offset.xw).rgb;
                    half3 s3 = tex2D(_MainTex, i.uv + offset.zw).rgb;

                    half w0 = Weigh(s0);
                    half w1 = Weigh(s1);
                    half w2 = Weigh(s2);
                    half w3 = Weigh(s3);

                    half3 color = s0 * w0 + s1 * w1 + s2 * w2 + s3 * w3;
                    // use max with a non 0 value to avoid division by 0 in case
                    // four black pixels.
                    color /= max(w0 + w1 + w2 + w3, 0.00001);

                    return half4(color, coc);
                }
            ENDCG
        }

        Pass { // 2 bokehPass
            CGPROGRAM
                #pragma vertex VertexProgram
			    #pragma fragment FragmentProgram
                
                #define BOKEH_KERNEL_MEDIUM
                // #define BOKEH_KERNEL_SMALL

                // From https://github.com/Unity-Technologies/PostProcessing/blob/v2/PostProcessing/Shaders/Builtins/DiskKernels.hlsl
                #if defined(BOKEH_KERNEL_SMALL)
                    // Kernel from Unity PostProcessing Stack V2: it contains
                    // the central point, a ring of 5 points around it and
                    // another outer ring around of 10 points. Total 16 points.
                    // All of them are withing the unit circle.
                    static const int kernelSampleCount = 16;
                    static const float2 kernel[kernelSampleCount] = {
                        float2(0, 0),
                        float2(0.54545456, 0),
                        float2(0.16855472, 0.5187581),
                        float2(-0.44128203, 0.3206101),
                        float2(-0.44128197, -0.3206102),
                        float2(0.1685548, -0.5187581),
                        float2(1, 0),
                        float2(0.809017, 0.58778524),
                        float2(0.30901697, 0.95105654),
                        float2(-0.30901703, 0.9510565),
                        float2(-0.80901706, 0.5877852),
                        float2(-1, 0),
                        float2(-0.80901694, -0.58778536),
                        float2(-0.30901664, -0.9510566),
                        float2(0.30901712, -0.9510565),
                        float2(0.80901694, -0.5877853),
                    };
                #elif defined(BOKEH_KERNEL_MEDIUM)
                    // Kernel from Unity PostProcessing Stack V2: it contains
                    // the central point, a ring of 7 points around it and
                    // another outer ring around of 14 points. Total 22 points.
                    // All of them are withing the unit circle.
                    static const int kernelSampleCount = 22;
					static const float2 kernel[kernelSampleCount] = {
						float2(0, 0),
						float2(0.53333336, 0),
						float2(0.3325279, 0.4169768),
						float2(-0.11867785, 0.5199616),
						float2(-0.48051673, 0.2314047),
						float2(-0.48051673, -0.23140468),
						float2(-0.11867763, -0.51996166),
						float2(0.33252785, -0.4169769),
						float2(1, 0),
						float2(0.90096885, 0.43388376),
						float2(0.6234898, 0.7818315),
						float2(0.22252098, 0.9749279),
						float2(-0.22252095, 0.9749279),
						float2(-0.62349, 0.7818314),
						float2(-0.90096885, 0.43388382),
						float2(-1, 0),
						float2(-0.90096885, -0.43388376),
						float2(-0.6234896, -0.7818316),
						float2(-0.22252055, -0.974928),
						float2(0.2225215, -0.9749278),
						float2(0.6234897, -0.7818316),
						float2(0.90096885, -0.43388376),
					};
                #endif

                half Weigh (half coc, half radius) {
                    // Simple weigh function mirroring the original
                    // contributing/discarted policy
                    // return coc >= radius;

                    // Smoother transition with all kernels included
                    // By adding a small value and then dividing by it,
                    // we introduce an offset and turn it into a steep ramp.
                    // Specifically: this function returns 1 for all kernels
                    // inside the coc, and values linearly distributed
                    // from 1 to 0 for kernels beyond the coc (0 will be
                    // the weight when radius >= coc + 2)
                    // NOTE: why it specifically adds 2 is a mystery to me.
                    return saturate((coc - radius + 2) / 2);
                }
                
                // This is not the final version of the fragment shader, but I
                // leave it here as its comments explain the middle development
                // stages of Depth of Field according to the tutorial
                half4 BokehMixedFGandBG (Interpolators i) {
                    half3 color = 0;
                    half weight = 0;
                    //
                    // Custom kernel bokeh (PostProcessStack V2)
                    //
                    for (int k = 0; k < kernelSampleCount; k++) {
                        // kernel values are within the unit circle, so we
                        // multiply them by the size of our bokeh size.
                        float2 offset = kernel[k] * _BokehRadius;
                        // The idea is add the contribute of the current sample only
                        // if its within the coc radius. The less the radius of
                        // coc is, the less samples would be added, and thus the
                        // the less the sample would be blurred (in case of radius == 0,
                        // only the central sample would be get, resulting in an
                        // unchanged pixel).
                        // NOTE: for greater efficiency, we could have created a
                        // dedicated array for the offsets of each point of the kernel,
                        // instead of recalculating the distance each time.
                        half radius = length(offset);
                        offset *= _MainTex_TexelSize.xy;
                        half4 s = tex2D(_MainTex, i.uv + offset);

                        // The coc radius is stored in the alpha channel of the
                        // source texture. However this approach cause abrupt change
                        // in the bokeh depending on the coc.
                        /* if (abs(s.a) >= radius) {
                            color += s.rgb;
                            weight += 1;
                        } */
                        // This alternative approach help us to mitigate the coc
                        // impact by using a weight for the contribution of each kernel
                        // sample, instead of simply adding it or not.
                        half sw = Weigh(abs(s.a), radius);
                        color += s.rgb * sw;
                        weight += sw;
                    }
                    color *= 1.0 / weight;

                    // Round and square bokeh (starting bokeh examples)
                    /* float weight = 0;
                    for (int u = -4; u <= 4; u++) {
                        for (int v = -4; v <= 4; v++) {
                            //
                            // Round bokeh
                            //
                            float2 offset = float2(u, v);
                            // For a simple rounded bokeh we can simple exclude
                            // the samples that are beyond a certain distance from
                            // the current pixel
                            if (length(offset) <= 4) {
                                // We multiply the offset by _BokehRadius to increase the sampling area
                                // without increasing the (already huge) number of samples.
                                offset *= _MainTex_TexelSize.xy * _BokehRadius;
                                color += tex2D(_MainTex, i.uv + offset).rgb;
                                weight++;
                            }

                            //
                            // Square bokeh
                            //
                            // We multiply the offset by _BokehRadius to increase the sampling area
                            // without increasing the (already huge) number of samples.
                            //float2 offset = float2(u, v) * _MainTex_TexelSize.xy * _BokehRadius;
                            //color += tex2D(_MainTex, i.uv + offset).rgb;
                            //weight++;
                        }
                    }
                    color *= 1.0 / weight; */

                    return half4(color, 1);
                }

                // This is the full bokeh implementation, each handle unfocused
                // foreground and background differences
                half4 BokehSplitFGandBG (Interpolators i) {

                    half coc = tex2D(_MainTex, i.uv).a;

                    half3 bgColor = 0, fgColor = 0;
					half bgWeight = 0, fgWeight = 0;
					for (int k = 0; k < kernelSampleCount; k++) {
						float2 o = kernel[k] * _BokehRadius;
						half radius = length(o);
						o *= _MainTex_TexelSize.xy;
						half4 s = tex2D(_MainTex, i.uv + o);

                        // BG weight are taken using maximum of 0 for coc values.
                        // However, we need to take the minimum between the current
                        // kernel point coc and the current pixel coc to prevent
                        // the background to bleed onto the source texture.
                        // (However, I don't get how this could prevent it for
                        // all possible bokeh radius values... check the large cube
                        // on the right in the tutorial, where bleed occurs if we don't
                        // use the minimum function: for large bokeh values this works,
                        // but for smaller values (e.g. 1), there is no visual difference
                        // between the two approach, even if, according to calculation,
                        // in that case bleed should occur with both strategy.
                        // This is due to the weigh function, because it adds this
                        // mysterious 2 to the coc - radius input value)
                        half bgw = Weigh(max(0, min(s.a, coc)), radius);
						bgColor += s.rgb * bgw;
						bgWeight += bgw;

                        // Same mystery here: seems fine to use negative coc values
                        // to show unfocused foreground values: however the weigh
                        // function adds 2 to coc - radius, thus largely changing
                        // the results based on the bokeh radius (for large values
                        // only unfocused foreground is gathered, for smaller values
                        // even focused and unfocused background values are sampled,
                        // until we get the also the camera background for bokeh radius
                        // equal to 1). So, it's not clear what this so called "foreground"
                        // actually is.
						half fgw = Weigh(-s.a, radius);
						fgColor += s.rgb * fgw;
						fgWeight += fgw;
					}
                    // bgWeight == 0 and fgWeight == 0 are used to avoid divisions by 0
                    // It should never happen for background colors, but it happens
                    // for foreground colors when bokeh radius is greater than 1.
                    // dividing by one in that case prevents this black color from being
                    // blended with the rest of the colors.
					bgColor *= 1 / (bgWeight + (bgWeight == 0));
                    fgColor *= 1 / (fgWeight + (fgWeight == 0));

                    // We recombine foreground and background by lerping between
                    // them based on the foreground weight, clamped to 1 (mh...
                    // should it cause a loss of information...? More mysteries...)
                    // However, we  divide the weight by the number of samples
                    // because it would otherwise be at full strength even if a single
                    // kernel sample belongs to the background. Moreover we scale it
                    // by a constant (PI, in this case, since we are dealing with a disk
                    // (Yeah... convincing...)) to make the foreground visually stronger
                    // but, the final scaling value is a matter of choice.
                    half bgfg = min(1, fgWeight * 3.14159265359  / kernelSampleCount);
                    half3 color = lerp(bgColor, fgColor, bgfg);

                    // the interpolator factor between background and foreground
                    // is passed in the alpha channel so that the combine pass
                    // can use it to fix the blending with the source image.
					return half4(color, bgfg);
                }

                half4 FragmentProgram (Interpolators i) : SV_Target {
                    // Bokeh creation up to paragragh 4.4 of the tutorial
                    // return BokehMixedFGandBG(i);
                    // Complete Bokeh creation according to the tutorial
                    return BokehSplitFGandBG(i);
                }

            ENDCG
        }

        Pass { // 3 postFilterPass
            CGPROGRAM
                #pragma vertex VertexProgram
			    #pragma fragment FragmentProgram
                
                half4 FragmentProgram (Interpolators i) : SV_Target {
                    // Gaussian blur with 3x3 kernel. It samples half texel size
                    // diagonally, taking advantage of bilinear filtering to
                    // give the contribute of all the 2x2 sub kernel to the final
                    // result.
                    float4 offset = _MainTex_TexelSize.xyxy * float2(-0.5, 0.5).xxyy;
                    half4 s =
                        tex2D(_MainTex, i.uv + offset.xy) +
                        tex2D(_MainTex, i.uv + offset.zy) +
                        tex2D(_MainTex, i.uv + offset.xw) +
                        tex2D(_MainTex, i.uv + offset.zw);
                    return s * 0.25;

                    // This is the previous algorithm without taking advantage
                    // of the bilinear filtering. This is of course less performant
                    // since we are using more samples (bilinear filtering uses
                    // screen space derivatives to sample adjacent pixel so for each
                    // 2x2 sub kernel the sample cost is always 1), but it allows
                    // to visualize the weights of each pixel of the kernel.
                    /* float4 offset = _MainTex_TexelSize.xyxy * float2(-1, 1).xxyy;
                    half4 s =
                        tex2D(_MainTex, i.uv) * 4 +
                        tex2D(_MainTex, i.uv + float2(offset.x, 0)) * 2 +
                        tex2D(_MainTex, i.uv + float2(offset.z, 0)) * 2 +
                        tex2D(_MainTex, i.uv + float2(0, offset.y)) * 2 +
                        tex2D(_MainTex, i.uv + float2(0, offset.w)) * 2 +
                        tex2D(_MainTex, i.uv + offset.xy) +
                        tex2D(_MainTex, i.uv + offset.zy) +
                        tex2D(_MainTex, i.uv + offset.xw) +
                        tex2D(_MainTex, i.uv + offset.zw);

                    return s * 0.0625; */
                }
            ENDCG
        }

        Pass { // 4 combinePass
            CGPROGRAM
                #pragma vertex VertexProgram
			    #pragma fragment FragmentProgram
                
                half4 FragmentProgram (Interpolators i) : SV_Target {
                    half4 source = tex2D(_MainTex, i.uv);
                    half coc = tex2D(_CoCTex, i.uv).r;
                    half4 dof = tex2D(_DoFTex, i.uv);

                    // Using coc directly would produce values between 0.1 and 1 only for
                    // unfocused background and focused values (coc >= 0). For foreground
                    // unfocused values (coc < 0) will have always 0.1. And that would be
                    // fine for our calculations.
                    // However we have artifacts around the edges of foreground elements
                    // where they transition to a far-away background. In that case, a
                    // large portion of kernel samples end up in the background, and that
                    // weakens the foreground influence. To solve that, use the absolute
                    // value of the coc
                    half dofStrength = smoothstep(0.1, 1, abs(coc));
                    half3 color = lerp(
                        source.rgb,
                        dof.rgb,
                        // dof.a contains the foreground weight for the current pixel
                        // if it's 0, then it's a background point, and the unaltered
                        // dofStrength is used. If it's greater the 0, than it's a
                        // foreground point and the interpolator is calculated by
                        // this expression, which makes the interpolation non-linear
                        // (I skipped digging into the details about this, I admit it)
                        dofStrength + dof.a - dofStrength * dof.a
                    );
                    return half4(color, source.a);
                }
            ENDCG
        }
	}
}