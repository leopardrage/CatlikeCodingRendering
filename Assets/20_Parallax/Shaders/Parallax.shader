Shader "Custom/Parallax" {

    Properties {
        _Color ("Tint", Color) = (1, 1, 1, 1)
        _MainTex ("Albedo", 2D) = "white" {}

        [NoScaleOffset] _NormalMap ("Normals", 2D) = "bump" {}
        _BumpScale ("Bump Scale", Float) = 1

        [NoScaleOffset] _MetallicMap ("Metallic", 2D) = "white" {}
        [Gamma] _Metallic ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5

        _DetailTex ("Detail Albedo", 2D) = "grey" {}
        [NoScaleOffset] _DetailNormalMap ("Detail Normals", 2D) = "bump" {}
        _DetailBumpScale ("Detail Bump Scale", Float) = 1

        [NoScaleOffset] _EmissionMap ("Emission", 2D) = "black" {}
        _Emission ("Emission", Color) = (0, 0, 0)
        
        [NoScaleOffset] _ParallaxMap ("Parallax", 2D) = "black" {}
        // Since parallax effects are rather strong, the range is set to [0, 0.1]
        _ParallaxStrength ("Parallax Strength", Range(0, 0.1)) = 0

        [NoScaleOffset] _OcclusionMap ("Occlusion", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0, 1)) = 1

        [NoScaleOffset] _DetailMask ("Detail Mask", 2D) = "white" {}

        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5

        [HideInInspector] _SrcBlend ("_SrcBlend", Float) = 1
        [HideInInspector] _DstBlend ("_DstBlend", Float) = 0
        [HideInInspector] _ZWrite ("_ZWrite", Float) = 1
    }

    CGINCLUDE

    #define BINORMAL_PER_FRAGMENT
    //#define FOG_DISTANCE

    // Parallax: it allows to use offset limiting, instead of physically correct offset
    //#define PARALLAX_OFFSET_LIMITING
    // Parallax: it allows to specify a custom bias for physically correct offset.
    // If none is defined, a default one is applied.
    //#define PARALLAX_BIAS 0
    // Parallax: it allows to specify the function to be used to get the parallax
    // uv displacement. If not define, it will fallback to the simple parallax offset
    // function used by Unity Standard Shader.
    #define PARALLAX_FUNCTION ParallaxRaymarching
    // Parallax: number of steps for the raymarching parallax function. Increasing it
    // improve quality (reduce the stratification effect) but it also decrease performance.
    //#define PARALLAX_RAYMARCHING_STEPS 100
    // Parallax: use the interpolate optimization variant when using the raymarching 
    // parallax function. Reduce stratification but have hard times against small features,
    // silhouettes and shallow angles. Note: this technique will be used only if the
    // PARALLAX_RAYMARCHING_STEPS is set to 0 (disabled)
    #define PARALLAX_RAYMARCHING_INTERPOLATE
    // Parallax: set the number of steps for the algorithm variant that uses the binary
    // search strategy (it matches the Relief Mapping approach). Set it to 0 to disable
    // this variant, falling back to interpolate if defined.
    // This approach works better with shallow angles but need quite a few steps to get
    // rid of stratification.
    #define PARALLAX_RAYMARCHING_SEARCH_STEPS 3
    // Parallax: enable normalization of normal and tangent vectors before creating the
    // object to world matrix in case of dynamic batching, since in some version of Unity
    // this feature results in not-normalized normal and tangent vectors, causing a warping
    // effect on close overlapping parallx materials for some camera angles.
    // This is made optional so that we can opt-in out in not necessary and save the
    // normalization, which si a little expensive.
    #define PARALLAX_SUPPORT_SCALED_DYNAMIC_BATCHING

    ENDCG

    SubShader {
		
        // Remember: the order of the Passes doesn't matter! Unity
        // will perform them when required by the pipeline.
        Pass {
            Tags {
                "LightMode" = "ForwardBase"
            }
            
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]

            CGPROGRAM

            #pragma target 3.0

            #pragma multi_compile_fwdbase
            #pragma shader_feature _METALLIC_MAP
            #pragma shader_feature _ _SMOOTHNESS_ALBEDO _SMOOTHNESS_METALLIC
            #pragma shader_feature _NORMAL_MAP
            #pragma shader_feature _PARALLAX_MAP
            #pragma shader_feature _EMISSION_MAP
            #pragma shader_feature _OCCLUSION_MAP
            #pragma shader_feature _DETAIL_MASK
            #pragma shader_feature _DETAIL_ALBEDO_MAP
            #pragma shader_feature _DETAIL_NORMAL_MAP
            #pragma shader_feature _ _RENDERING_CUTOUT _RENDERING_FADE _RENDERING_TRANSPARENT
            #pragma multi_compile_fog
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_instancing
            #pragma instancing_options lodfade

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #define FORWARD_BASE_PASS

            #include "ParallaxShared.cginc"

            ENDCG
        }

        Pass {
            Tags {
                "LightMode" = "ForwardAdd"
            }

            Blend [_SrcBlend] One

            ZWrite Off

            CGPROGRAM

            #pragma target 3.0
            
            #pragma multi_compile_fwdadd_fullshadows
            #pragma shader_feature _METALLIC_MAP
            #pragma shader_feature _ _SMOOTHNESS_ALBEDO _SMOOTHNESS_METALLIC
            #pragma shader_feature _NORMAL_MAP
            #pragma shader_feature _PARALLAX_MAP
            #pragma shader_feature _DETAIL_MASK
            #pragma shader_feature _DETAIL_ALBEDO_MAP
            #pragma shader_feature _DETAIL_NORMAL_MAP
            #pragma shader_feature _ _RENDERING_CUTOUT _RENDERING_FADE _RENDERING_TRANSPARENT
            #pragma multi_compile_fog
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #include "ParallaxShared.cginc"

            ENDCG
        }

        // This tells Unity that our shader has a deferred pass. This way
        // Unity will include the opaque and cutout objects in the deferred phase.
        // Transparent objects will still be rendered in the transparent phase.
        Pass {
            Tags {
                "LightMode" = "Deferred"
            }

            CGPROGRAM

            #pragma target 3.0
            // Deferred rendering won't be available for platforms that doesn't
            // support multiple render targets (no mrt)
            #pragma exclude_renderers nomrt

            #pragma shader_feature _ _RENDERING_CUTOUT
            #pragma shader_feature _METALLIC_MAP
            #pragma shader_feature _ _SMOOTHNESS_ALBEDO _SMOOTHNESS_METALLIC
            #pragma shader_feature _NORMAL_MAP
            #pragma shader_feature _PARALLAX_MAP
            #pragma shader_feature _EMISSION_MAP
            #pragma shader_feature _OCCLUSION_MAP
            #pragma shader_feature _DETAIL_MASK
            #pragma shader_feature _DETAIL_ALBEDO_MAP
            #pragma shader_feature _DETAIL_NORMAL_MAP
            #pragma multi_compile_prepassfinal
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_instancing
            #pragma instancing_options lodfade

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            // This allow the included shader to know when it's in the deferred pass
            #define DEFERRED_PASS

            #include "ParallaxShared.cginc"

            ENDCG
        }

        Pass {
            Tags {
                "LightMode" = "ShadowCaster"
            }

            CGPROGRAM

            #pragma target 3.0
            #pragma multi_compile_shadowcaster
            #pragma multi_compile_instancing
            #pragma instancing_options lodfade
            #pragma shader_feature _SMOOTHNESS_ALBEDO
            #pragma shader_feature _RENDERING_CUTOUT _RENDERING_FADE _RENDERING_TRANSPARENT
            #pragma shader_feature _SEMITRANSPARENT_SHADOWS

            #pragma vertex MyShadowVertexProgram
            #pragma fragment MyShadowFragmentProgram
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #include "Assets/Shared/Shaders/SemitransparentShadowShared.cginc"

            ENDCG
        }

        Pass {
            Tags {
                "LightMode" = "Meta"
            }

            Cull Off

            CGPROGRAM

            #pragma shader_feature _METALLIC_MAP
            #pragma shader_feature _ _SMOOTHNESS_ALBEDO _SMOOTHNESS_METALLIC
            #pragma shader_feature _EMISSION_MAP
            #pragma shader_feature _DETAIL_MASK
            #pragma shader_feature _DETAIL_ALBEDO_MAP

            #pragma vertex MyLightmappingVertexProgram
            #pragma fragment MyLightmappingFragmentProgram

            #include "ParallaxMeta.cginc"

            ENDCG
        }
	}

    CustomEditor "ParallaxGUI"
}