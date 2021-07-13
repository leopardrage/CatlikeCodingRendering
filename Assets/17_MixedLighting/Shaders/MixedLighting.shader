Shader "Custom/Mixed Lighting" {

    Properties {
        // Unity lightmapper uses the main color alpha to calculate correct shadows
        // for semitransparent objects, but expects that color property to be named
        // _Color
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

        [NoScaleOffset] _OcclusionMap ("Occlusion", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0, 1)) = 1

        [NoScaleOffset] _DetailMask ("Detail Mask", 2D) = "white" {}

        // Unity lightmapper uses our cutoff value for cutoff rendering mode and cutoff
        // shadows, but expects that color property to be named _Cutoff
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5

        [HideInInspector] _SrcBlend ("_SrcBlend", Float) = 1
        [HideInInspector] _DstBlend ("_DstBlend", Float) = 0
        [HideInInspector] _ZWrite ("_ZWrite", Float) = 1
    }

    CGINCLUDE

    #define BINORMAL_PER_FRAGMENT
    //#define FOG_DISTANCE

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

            // #pragma multi_compile _ SHADOWS_SCREEN
            // In forward path, lightmaps are sampled in the base pass only.
            // Besides, since when lightmaps are used all light are treated as
            // pixel lights, vertex lights won't be included, so the two keyword
            // must be mutually exclusive.
            // #pragma multi_compile _ LIGHTMAP_ON VERTEXLIGHT_ON
            // This multi compile directive add all needed lightmapping keywords
            // and the VERTEXLIGHT_ON keyword
            #pragma multi_compile_fwdbase
            #pragma shader_feature _METALLIC_MAP
            #pragma shader_feature _ _SMOOTHNESS_ALBEDO _SMOOTHNESS_METALLIC
            #pragma shader_feature _NORMAL_MAP
            #pragma shader_feature _EMISSION_MAP
            #pragma shader_feature _OCCLUSION_MAP
            #pragma shader_feature _DETAIL_MASK
            #pragma shader_feature _DETAIL_ALBEDO_MAP
            #pragma shader_feature _DETAIL_NORMAL_MAP
            #pragma shader_feature _ _RENDERING_CUTOUT _RENDERING_FADE _RENDERING_TRANSPARENT
            // Automatically add variants for FOG_LINEAR, FOG_EXP and FOG_EXP2 keywords
            #pragma multi_compile_fog

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #define FORWARD_BASE_PASS

            #include "MixedLightingShared.cginc"

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
            #pragma shader_feature _DETAIL_MASK
            #pragma shader_feature _DETAIL_ALBEDO_MAP
            #pragma shader_feature _DETAIL_NORMAL_MAP
            #pragma shader_feature _ _RENDERING_CUTOUT _RENDERING_FADE _RENDERING_TRANSPARENT
            // Automatically add variants for FOG_LINEAR, FOG_EXP and FOG_EXP2 keywords
            #pragma multi_compile_fog

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #include "MixedLightingShared.cginc"

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

            // RENDERING_FADE and RENDERING_TRANSPARENT variants are not supported
            // in deferred shading
            #pragma shader_feature _ _RENDERING_CUTOUT
            #pragma shader_feature _METALLIC_MAP
            #pragma shader_feature _ _SMOOTHNESS_ALBEDO _SMOOTHNESS_METALLIC
            #pragma shader_feature _NORMAL_MAP
            #pragma shader_feature _EMISSION_MAP
            #pragma shader_feature _OCCLUSION_MAP
            #pragma shader_feature _DETAIL_MASK
            #pragma shader_feature _DETAIL_ALBEDO_MAP
            #pragma shader_feature _DETAIL_NORMAL_MAP

            // #pragma multi_compile _ UNITY_HDR_ON
            // #pragma multi_compile _ LIGHTMAP_ON
            // This takes care of all lightmapping keywords and the HDR keywords
            // (the prepass final terminology it's just legacy for an old
            // version of the deferred pipeline that goes back to Unity 4)
            #pragma multi_compile_prepassfinal

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            // This allow the included shader to know when it's in the deferred pass
            #define DEFERRED_PASS

            #include "MixedLightingShared.cginc"

            ENDCG
        }

        Pass {
            Tags {
                "LightMode" = "ShadowCaster"
            }

            CGPROGRAM

            #pragma target 3.0
            #pragma multi_compile_shadowcaster
            #pragma shader_feature _SMOOTHNESS_ALBEDO
            #pragma shader_feature _RENDERING_CUTOUT _RENDERING_FADE _RENDERING_TRANSPARENT
            #pragma shader_feature _SEMITRANSPARENT_SHADOWS

            #pragma vertex MyShadowVertexProgram
            #pragma fragment MyShadowFragmentProgram

            #include "Assets/Shared/Shaders/SemitransparentShadowShared.cginc"

            ENDCG
        }

        // This pass is only used by lightmapping to figure out the
        // surface color of objects. It's not included in builds.
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

            #include "MixedLightingMeta.cginc"

            ENDCG
        }
	}

    CustomEditor "MixedLightingGUI"
}