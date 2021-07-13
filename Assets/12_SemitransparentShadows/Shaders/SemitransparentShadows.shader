Shader "Custom/Semitransparent Shadows" {

    Properties {
        _Tint ("Tint", Color) = (1, 1, 1, 1)
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

        [NoScaleOffset] _OcclusionMap ("Occlusion", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0, 1)) = 1

        [NoScaleOffset] _DetailMask ("Detail Mask", 2D) = "white" {}

        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.5

        [HideInInspector] _SrcBlend ("_SrcBlend", Float) = 1
        [HideInInspector] _DstBlend ("_DstBlend", Float) = 0
        [HideInInspector] _ZWrite ("_ZWrite", Float) = 1
    }

    CGINCLUDE

    #define BINORMAL_PER_FRAGMENT

    ENDCG

    SubShader {
		
        Pass {
            Tags {
                "LightMode" = "ForwardBase"
            }

            // To Explain this (consider that the default is Blend One Zero)
            // If opaque: source alpha = 1, then we have
                // 1 * (new value) + 0 * (existing value) = 1 * (new value)
                // Same as Blend One Zero
            // If fully transparent: source alpha = 0, then we have
                // 0 * (new value) + 1 * (existing value) = 1 * (existing value)
                // Only the underlying value will be seen
            // If something in between (e.g.: alpha 0.25): source alpha = 0.25, then we have
                // 0.25 * (new value) + 0.75 * (existing value)
                // 25% of the transparent object will be seen, blend with 75% of the
                // underlying value
            // Blend SrcAlpha OneMinusSrcAlpha
            // Since the previous blend mode is specific for the Transparency (Fade)
            // rendering queue, we'll set it based on variable, to have more control
            Blend [_SrcBlend] [_DstBlend]
            // We want to disable writing on the Depth Buffer when using semitrasparent
            // materials (_RENDERING_FADE) to workaround the depth trouble that occurs
            // when overlapping semitransparent objects are not drawn in the correct
            // order (that, for semitransparant objects, should be from the farthers
            // to the, nearest, making semitrasparent objects expensive)
            ZWrite [_ZWrite]

            CGPROGRAM

            #pragma target 3.0

            #pragma multi_compile _ SHADOWS_SCREEN
            #pragma multi_compile _ VERTEXLIGHT_ON
            #pragma shader_feature _METALLIC_MAP
            #pragma shader_feature _ _SMOOTHNESS_ALBEDO _SMOOTHNESS_METALLIC
            #pragma shader_feature _NORMAL_MAP
            #pragma shader_feature _EMISSION_MAP
            #pragma shader_feature _OCCLUSION_MAP
            #pragma shader_feature _DETAIL_MASK
            #pragma shader_feature _DETAIL_ALBEDO_MAP
            #pragma shader_feature _DETAIL_NORMAL_MAP
            #pragma shader_feature _ _RENDERING_CUTOUT _RENDERING_FADE _RENDERING_TRANSPARENT

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #define FORWARD_BASE_PASS

            #include "SemitransparentShadowsShared.cginc"

            ENDCG
        }

        Pass {
            Tags {
                "LightMode" = "ForwardAdd"
            }

            // To Explain this
            // If opaque: source alpha = 1, then we have
                // 1 * (new value) + 1 * (existing value)
                // Same as the opaque Blend mode of the ForwardAdd pass (Blend One One)
            // If fully transparent: source alpha = 0, then we have
                // 0 * (new value) + 1 * (existing value) = 1 * (existing value)
                // Nothing will be added on the Base Pass
            // If something in between (e.g.: alpha 0.25): source alpha = 0.25, then we have
                // 0.25 * (new value) + 1 * (existing value)
                // 25% of the transparent object will be seen, added on the full value
                // of the Base Pass
            //Blend SrcAlpha One
            //Blend One One

            // Since the previous blend mode is specific for the Transparency (Fade)
            // rendering queue, we'll set it based on variable, to have more control
            Blend [_SrcBlend] One

            ZWrite Off

            CGPROGRAM

            #pragma target 3.0
            
            #pragma multi_compile_fwdadd_fullshadows
            #pragma shader_feature _METALLIC_MAP
            #pragma shader_feature _ _SMOOTHNESS_ALBEDO _SMOOTHNESS_METALLIC
            #pragma shader_feature _NORMAL_MAP
            #pragma shader_feature _DETAIL_MASK
            #pragma shader_feature _DETAIL_ALBEDO_MAP
            #pragma shader_feature _DETAIL_NORMAL_MAP
            #pragma shader_feature _ _RENDERING_CUTOUT _RENDERING_FADE _RENDERING_TRANSPARENT

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #include "SemitransparentShadowsShared.cginc"

            ENDCG
        }

        Pass {
            Tags {
                "LightMode" = "ShadowCaster"
            }

            CGPROGRAM

            #pragma target 3.0

            #pragma multi_compile_shadowcaster
            // These are needed to handle tranparency
            #pragma shader_feature _SMOOTHNESS_ALBEDO
            #pragma shader_feature _RENDERING_CUTOUT _RENDERING_FADE _RENDERING_TRANSPARENT
            #pragma shader_feature _SEMITRANSPARENT_SHADOWS

            #pragma vertex MyShadowVertexProgram
            #pragma fragment MyShadowFragmentProgram

            #include "SemitransparentShadowsShadow.cginc"

            ENDCG
        }
	}

    CustomEditor "SemitransparentShadowsGUI"
}