Shader "Custom/FlatGeometry" {

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
    #define PARALLAX_FUNCTION ParallaxRaymarching
    #define PARALLAX_RAYMARCHING_INTERPOLATE
    #define PARALLAX_RAYMARCHING_SEARCH_STEPS 3
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

            // Geometry shaders are only available for Shader Model 4.0+
            // If a geometry shader is detected, Unity automatically 
            // sets the appropriate minimum Shader Model version, if it was set lower here.
            // We just set it explicitely for clarity.
            #pragma target 4.0

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
            #pragma geometry MyGeometryProgram

            #define FORWARD_BASE_PASS

            #include "FlatGeometryShader.cginc"

            ENDCG
        }

        Pass {
            Tags {
                "LightMode" = "ForwardAdd"
            }

            Blend [_SrcBlend] One

            ZWrite Off

            CGPROGRAM

            // Minimum target for geometry shaders (see base pass for full details)
            #pragma target 4.0
            
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
            #pragma geometry MyGeometryProgram

            #include "FlatGeometryShader.cginc"

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

            // Minimum target for geometry shaders (see base pass for full details)
            #pragma target 4.0
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
            #pragma geometry MyGeometryProgram

            // This allow the included shader to know when it's in the deferred pass
            #define DEFERRED_PASS

            #include "FlatGeometryShader.cginc"

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

            #include "Assets/Shared/Shaders/MetaShared.cginc"

            ENDCG
        }
	}

    CustomEditor "FlatWireframeGUI"
}