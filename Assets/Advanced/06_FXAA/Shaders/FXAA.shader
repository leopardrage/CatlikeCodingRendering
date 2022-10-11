Shader "Hidden/FXAA" {

    Properties {
        _MainTex ("Texture", 2D) = "white" {}
    }

    CGINCLUDE
        #include "UnityCG.cginc"

        sampler2D _MainTex;
        float4 _MainTex_TexelSize;
        float _ContrastThreshold;
        float _RelativeThreshold;
        float _SubpixelBlending;

        struct VertexData {
            float4 vertex: POSITION;
            float2 uv: TEXCOORD0;
        };

        struct Interpolators {
            float4 pos: SV_POSITION;
            float2 uv: TEXCOORD0;
        };

        struct LuminanceData {
            float m, n, e, s, w;
            float ne, nw, se, sw;
            float highest, lowest, contrast;
        };

        struct EdgeData {
            bool isHorizontal;
            float pixelStep;
            float oppositeLuminance, gradient;
        };

        Interpolators VertexProgram (VertexData v) {
            Interpolators i;
            i.pos = UnityObjectToClipPos(v.vertex);
            i.uv = v.uv;
            return i;
        }

        float4 Sample (float2 uv) {
            // We don't use mipmaps in the temporary texture
            // we used to calculate the ffxa effect, but we have not
            // explicitely disabled anisotripic filtering, which might
            // distort the final sample. Thus we use the tex2Dlod function
            // to sample the texture without adjustment (the first 0
            // tells Unity to use the level 0 mipmap, which is the original texture).
            // Note that we are still taking advantage of the bilinear
            // filtering (which is the default FilterMode for RenderTexture instances)
            // to blend between pixels based on the given UV.
            return tex2Dlod(_MainTex, float4(uv, 0, 0));
        }

        float SampleLuminance (float2 uv) {
            #if defined(LUMINANCE_GREEN)
                return Sample(uv).g;
            #else
                return Sample(uv).a;
            #endif
        }

        float SampleLuminance (float2 uv, float uOffset, float vOffset) {
            uv += _MainTex_TexelSize * float2(uOffset, vOffset);
            return SampleLuminance(uv);
        }

        LuminanceData SampleLuminanceNeighborhood (float2 uv) {
            LuminanceData l;
            // Doesn't matter if OpenGL and DirectX differs about
            // their V axis direction. The algotithm is symmetric so
            // any chosen convention (OpenGL in this case) is valid
            l.m = SampleLuminance(uv);
            l.n = SampleLuminance(uv, 0, 1);
            l.e = SampleLuminance(uv, 1, 0);
            l.s = SampleLuminance(uv, 0, -1);
            l.w = SampleLuminance(uv, -1, 0);

            // These samples are needed only if the pixel is not skipped
            // according to the skip logic (see the ShouldSkipPixel below).
            // Fortunately, the compiler will optimize our code so that
            // these samples take place only if needed.
            l.ne = SampleLuminance(uv, 1, 1);
            l.nw = SampleLuminance(uv, -1, 1);
            l.se = SampleLuminance(uv, 1, -1);
            l.sw = SampleLuminance(uv, -1, -1);

            l.highest = max(max(max(max(l.n, l.e), l.s), l.w), l.m);
            l.lowest = min(min(min(min(l.n, l.e), l.s), l.w), l.m);
            l.contrast = l.highest - l.lowest;

            return l;
        }

        bool ShouldSkipPixel (LuminanceData l) {
            // Choosing the maximum between the two thresholds means that
            // we are using a highly aggressive skipping policy: we skip a pixel
            // if its contrast is lower than one of the thresholds.
            // NOTE: the relative threshold, as such, it's scaled by the highest
            // luminance of the pixel neighborhood.
            float threshold = max(_ContrastThreshold, _RelativeThreshold * l.highest);
            return l.contrast < threshold;
        }

        float DeterminePixelBlendFactor (LuminanceData l) {
            // We are calculating the avarage luminance of all pixels
            // around the current one. Since diagonal neighbors are farther then
            // the others, they should matter less and we achieve this by doubling
            // the weight of the others. This brings the sum of all weights to 12
            // (2 + 2 + 2 + 2 + 1 + 1 + 1 + 1) so we divide by 12 at the end.
            //
            // This works as a low-pass filter: in image processing, frequency
            // is the rate of change of the image. A full white image has all
            // frequencies == 0, while a very detailed and full of colors image
            // have a lot of high frequencies. These are defined by the Fourier
            // Transform of the image, which is a way to represent an image in the
            // so called frequency domain (as opposed to the standard space domain).
            // In the frequency domain, an image is represented as the sum of
            // frequencies: low frequencies represent global and overall changes
            // in the image (such as the change between the ground and the sky
            // in a landscape picture), while high frequencies represent the
            // tiny details. In this case, the algorithm produce a low pass filter
            // because pixels with a neighborhood that contains high luminance
            // differencies (such as on edges from dark to bright) are very blurred
            // (their high frequency is compressed down) while neighborhoods with
            // few or weak differencies in luminance are very similar to the original.
            // You can see this clearly by just outputting this value while
            // disabling pixel skipping.
            float filter = 2 * (l.n + l.e + l.s + l.w);
            filter += l.ne + l.nw + l.se + l.sw;
            filter *= 1.0 / 12;

            // This has now become a high pass filter. Not sure
            // if there is a specific formula that proves this, but reasonably
            // I think that the middle pixel luminance is taken as reference
            // against the neighborhood: if the avarage luminance is similar to
            // the one of the current pixel, we can assume low frequency, so
            // we return low values. Otherwise, it means high frequency, so
            // larger values are returned.
            filter = abs(filter - l.m);

            // Normalization of the filter relative to contrast. The result is
            // clamped to 1 because diagonal pixels might generate larger values.
            // Indeed, if the filter were based on cross samples only, it couldn't
            // have greater values than the contrast (maybe a theorem exists that
            // proves that). But since we are using also diagonal samples for the
            // filter, its values might be potentially higher, leading to values
            // greater than 1.
            // Lastly, scaling with the contrast allow to increase the overall values,
            // giving a larger boost to lower values than the one given to higher values.
            // This, de facto, makes the resulting values more even across all pixels.
            filter = saturate(filter / l.contrast);

            // Since the result is a too harsh transition we smooth it out with
            // smoothstep and squared the results to slow it down (see the
            // tutorial for a visual representation).
            float blendFactor = smoothstep(0, 1, filter);
            // Also, a user defined _SubpixelBlending property is used
            // to customize the blend intensity
            return blendFactor * blendFactor * _SubpixelBlending;
        }

        EdgeData DetermineEdge (LuminanceData l) {
            EdgeData e;
            // The amount of luminance changes between rows of our kernel
            // represents how likely it is that we are on an horizontal edge.
            float horizontal =
                abs(l.n + l.s - 2 * l.m) * 2 +
                abs(l.ne + l.se - 2 * l.e) +
                abs(l.nw + l.sw - 2 * l.w);
            // The amount of luminance changes between columns of our kernel
            // represents how likely it is that we are on a vertical edge.
            float vertical =
                abs(l.e + l.w - 2 * l.m) * 2 +
                abs(l.ne + l.nw - 2 * l.n) +
                abs(l.se + l.sw - 2 * l.s);
            // The winning value defines the (approximated) edge direction
            e.isHorizontal = horizontal >= vertical;

            // To know if we have to blend in the positive or negative direction
            // we compare (based on the edge direction) the contrast between
            // either side and the middle pixel.
            float pLuminance = e.isHorizontal ? l.n : l.e;
            float nLuminance = e.isHorizontal ? l.s : l.w;
            // Here "gradient" stays for "contrast", since they are semantically
            // interchangable in this context.
            float pGradient = abs(pLuminance - l.m);
            float nGradient = abs(nLuminance - l.m);

            // Pixel Step to sample neighboors for blending, based on the
            // blend direction, which is orthogonal to the edge direction.
            e.pixelStep =
                e.isHorizontal ? _MainTex_TexelSize.y : _MainTex_TexelSize.x;

            if (pGradient < nGradient) {
                e.pixelStep = -e.pixelStep;
                e.oppositeLuminance = nLuminance;
                e.gradient = nGradient;
            } else {
                e.oppositeLuminance = pLuminance;
                e.gradient = pGradient;
            }

            return e;
        }

        // These helps to increase quality for staircase steps more than
        // ten pixels EDGE_STEP_COUNT wide
        #if defined(LOW_QUALITY)
            #define EDGE_STEP_COUNT 4
            #define EDGE_STEPS 1, 1.5, 2, 4
            #define EDGE_GUESS 12
        #else
            #define EDGE_STEP_COUNT 10
            // From the 1.5 step, we are sampling between adjacent pixel pairs,
            // so, with the following increments of 2, we in fact sampling 4 pixels
            // instead of 2. This is less accurate, but it prevents pixel skipping.
            #define EDGE_STEPS 1, 1.5, 2, 2, 2, 2, 2, 2, 2, 4
            #define EDGE_GUESS 8
        #endif

        static const float edgeSteps[EDGE_STEP_COUNT] = { EDGE_STEPS };

        float DetermineEdgeBlendFactor (LuminanceData l, EdgeData e, float2 uv) {
            float2 uvEdge = uv;
            float2 edgeStep;
            if (e.isHorizontal) {
                uvEdge.y += e.pixelStep * 0.5;
                edgeStep = float2(_MainTex_TexelSize.x, 0);
            } else {
                uvEdge.x += e.pixelStep * 0.5;
                edgeStep = float2(0, _MainTex_TexelSize.y);
            }

            float edgeLuminance = (l.m + e.oppositeLuminance) * 0.5;
            float gradientThreshold = e.gradient * 0.25;

            float2 puv = uvEdge + edgeStep * edgeSteps[0];
            float pLuminanceDelta = SampleLuminance(puv) - edgeLuminance;
            bool pAtEnd = abs(pLuminanceDelta) >= gradientThreshold;

            UNITY_UNROLL
            for (int i = 1; i < EDGE_STEP_COUNT && !pAtEnd; i++) {
                puv += edgeStep * edgeSteps[i];
                pLuminanceDelta = SampleLuminance(puv) - edgeLuminance;
                pAtEnd = abs(pLuminanceDelta) >= gradientThreshold;
            }
            // If we didn't find the end point in the previous loop
            // we are safe to assume that is further ahead
            if (!pAtEnd) {
                puv += edgeStep * EDGE_GUESS;
            }

            float2 nuv = uvEdge - edgeStep * edgeSteps[0];
            float nLuminanceDelta = SampleLuminance(nuv) - edgeLuminance;
            bool nAtEnd = abs(nLuminanceDelta) >= gradientThreshold;

            // Explicitely unroll the for loop improves performance.
            // According to https://forum.unity.com/threads/what-are-unroll-and-loop-when-to-use-them.1283096/
            // however, it seems that we are in the case where a regular loop
            // might be preferable, since skipping unwanted operations would be
            // better than avoiding the loop overhead (in the unrolled version
            // IF statements are translated by the GPU in a way that executes
            // both if and else bodies and then perform assignments based on the
            // conditional evaluation, so unrolled versions seem to perform better
            // for fixed loop, especially on light operations...).
            // But the tutorial author states that he got significant performance boost
            // by unrolling these loops, so we trust him as good acolytes.
            UNITY_UNROLL
            for (int j = 1; j < EDGE_STEP_COUNT && !nAtEnd; j++) {
                nuv -= edgeStep * edgeSteps[j];
                nLuminanceDelta = SampleLuminance(nuv) - edgeLuminance;
                nAtEnd = abs(nLuminanceDelta) >= gradientThreshold;
            }
            if (!nAtEnd) {
                nuv -= edgeStep * EDGE_GUESS;
            }

            // This is a visual representation of the distance between the
            // current pixel and the endpoint of the edge step. The largest the
            // distance, the whiter the pixel will be. Since we use the uv distance
            // between the two points, we scale it by 10 to better see the results.
            float pDistance, nDistance;
            if (e.isHorizontal) {
                pDistance = puv.x - uv.x;
                nDistance = uv.x - nuv.x;
            } else {
                pDistance = puv.y - uv.y;
                nDistance = uv.y - nuv.y;
            }

            float shortestDistance;
            // Represent the sign of the difference between the luminance
            // on the found end point of the edge and the current pixel edge
            // luminance (that is to say: the luminance delta).
            bool deltaSign;
            if (pDistance <= nDistance) {
                shortestDistance = pDistance;
                deltaSign = pLuminanceDelta >= 0;
            } else {
                shortestDistance = nDistance;
                deltaSign = nLuminanceDelta >= 0;
            }

            // To prevent both pixels on the two sides of the edge
            // to add their blend factor contribution, we skip pixels
            // that goes in the opposite direction of the previousl
            // calculated deltaSign. This way, the pixel on one side takes
            // care of the edge in one direction, while the other one takes
            // care of it in the other direction.
            if (deltaSign == (l.m - edgeLuminance >= 0)) {
                return 0;
            }

            // Edge Blend Factor:
            // The closer we are to the end point of the edge, the more we blend.
            // Likewise, in the center of the edge are blend factor is 0.
            // We have 0 when shortestDistance is equal to pDistance and nDistance
            // (we are in the middle of the edge).
            // We have 0.5 (full blend factor) when we are on the end point of
            // the edge (shortestDistance == 0).
            // We have blend factor in [0, 0.5], linearly, for shortestDistance
            // values in between.
            return 0.5 - shortestDistance / (pDistance + nDistance);
        }

        float4 ApplyFXAA(float2 uv) {
            LuminanceData l = SampleLuminanceNeighborhood(uv);
            if (ShouldSkipPixel(l)) {
                //return 0;
                return Sample(uv);
            }

            float pixelBlend = DeterminePixelBlendFactor(l);
            EdgeData e = DetermineEdge(l);

            float edgeBlend = DetermineEdgeBlendFactor(l, e, uv);
            float finalBlend = max(pixelBlend, edgeBlend);

            if (e.isHorizontal) {
                uv.y += e.pixelStep * finalBlend;
            } else {
                uv.x += e.pixelStep * finalBlend;
            }
            return float4(Sample(uv).rgb, l.m);
        }

    ENDCG
    
    SubShader {
		
        // Typical cull and depth settings for post-process shaders
        Cull Off
        ZTest Always
        ZWrite Off

        Pass { // 0 luminancePass
            CGPROGRAM
                #pragma vertex VertexProgram
			    #pragma fragment FragmentProgram

                #pragma multi_compile _ GAMMA_BLENDING
                
                float4 FragmentProgram (Interpolators i) : SV_Target {
                    float4 sample = tex2D(_MainTex, i.uv);

                    // We are assuming to work in HDR, so we can
                    // have values outside 0-1 range. But LinearRgbToLuminance
                    // (and FXAA in general as an algorythm) expects values in 0-1.
                    // Generally we expect that FXAA is performed after tonemapping
                    // and color grading, which should ensure resulting values to
                    // be in 0-1 range, but since we are not using those effects, we
                    // explicitly clamp colors to 0-1 to ensure the algorythm correctness.
                    // We also do it to avoid the case, during the next FXAA pass,
                    // where HDR and LDR values might be blended together. In that
                    // case we can end up increasing aliasing instead of decreasing it
                    // if we are not working in LDR space. Example: Edge 1: 0.5 gray,
                    // Edge 2: 1.5 (white HDR). Blend factor: 0.5. Resulting color on
                    // the edge: 1. So you have, orthogonally to the edge, 0.5, 1 and 1.5,
                    // which, once clamped to LDR to be sent on screen, you have:
                    // 0.5, 1, 1 (aliasing still visible).
                    sample.rgb = saturate(sample.rgb);

                    // Green contributes to most of the pixel luminance,
                    // so it might resemble a crude luminance approximation.
                    //sample.rgb = sample.g;

                    // Calculating the correct luminance is not so trivial
                    // and thus we use a convenient function from UnityCG.cginc
                    // for that.
                    // However, since we are assuming to work in HDR, we can
                    // have values outside 0-1 range. But LinearRgbToLuminance
                    // (and FXAA in general as an algorythm) expects values in 0-1.
                    // Generally we expect that FXAA is performed after tonemapping
                    // and color grading, which should ensure resulting values to
                    // be in 0-1 range, but since we are not using those effects, we
                    // explicitly clamp colors to 0-1 to ensure the algorythm correctness.
                    // NOTE: LinearRgbToLuminance is just a weighted sum of the colors
                    // channels. The green channel is by far the heaviest, that's why
                    // using the green channel alone is a good raw approximation.
                    // Most likely, the weights are the result of a experimetal calculation.
                    sample.a = LinearRgbToLuminance(sample.rgb);

                    // If requested, convert colors in gamma space before blending
                    // (must be done now because LinearRgbToLuminance wants values
                    // in linear space).
                    // Remember: this FXAA implementation assumes we are working
                    // in linear space.
                    #if defined(GAMMA_BLENDING)
                        sample.rgb = LinearToGammaSpace(sample.rgb);
                    #endif

                    return sample;
                }
            ENDCG
        }

        Pass { // 1 fxaaPass
            CGPROGRAM
                #pragma vertex VertexProgram
			    #pragma fragment FragmentProgram

                #pragma multi_compile _ LUMINANCE_GREEN
                #pragma multi_compile _ LOW_QUALITY
                #pragma multi_compile _ GAMMA_BLENDING
                
                float4 FragmentProgram (Interpolators i) : SV_Target {
                    float4 sample = ApplyFXAA(i.uv);

                    // If we chose to blend in gamma space, convert
                    // back to linear space before outputting the final values.
                    // Remember: this FXAA implementation assumes we are working in
                    // linear space
                    #if defined(GAMMA_BLENDING)
                        sample.rgb = GammaToLinearSpace(sample.rgb);
                    #endif
                    
                    return sample;
                }
            ENDCG
        }
	}
}