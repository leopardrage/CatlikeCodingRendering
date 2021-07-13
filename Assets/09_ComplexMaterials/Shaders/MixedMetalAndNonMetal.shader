Shader "Custom/Mixed Metal And Non Metal" {

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
    }

    CGINCLUDE

    #define BINORMAL_PER_FRAGMENT

    ENDCG

    SubShader {
		
        Pass {
            Tags {
                "LightMode" = "ForwardBase"
            }

            CGPROGRAM

            #pragma target 3.0

            #pragma multi_compile _ SHADOWS_SCREEN
            #pragma multi_compile _ VERTEXLIGHT_ON
            #pragma shader_feature _METALLIC_MAP

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #define FORWARD_BASE_PASS

            #include "MixedMetalAndNonMetalShared.cginc"

            ENDCG
        }

        Pass {
            Tags {
                "LightMode" = "ForwardAdd"
            }

            Blend One One
            ZWrite Off

            CGPROGRAM

            #pragma target 3.0
            
            #pragma multi_compile_fwdadd_fullshadows
            #pragma shader_feature _METALLIC_MAP

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #include "MixedMetalAndNonMetalShared.cginc"

            ENDCG
        }

        Pass {
            Tags {
                "LightMode" = "ShadowCaster"
            }

            CGPROGRAM

            #pragma target 3.0

            #pragma multi_compile_shadowcaster

            #pragma vertex MyShadowVertexProgram
            #pragma fragment MyShadowFragmentProgram

            #include "Assets/Shared/Shaders/ShadowShared.cginc"

            ENDCG
        }
	}

    CustomEditor "MixedMetalAndNonMetalGUI"
}