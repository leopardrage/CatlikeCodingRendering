Shader "Custom/Bumpiness NormalMap And DetailMap Shader" {

    Properties {
        _Tint ("Tint", Color) = (1, 1, 1, 1)
        _MainTex ("Albedo", 2D) = "white" {}
        [NoScaleOffset] _NormalMap ("Normals", 2D) = "bump" {}
        _BumpScale ("Bump Scale", Float) = 1
        [Gamma] _Metallic ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        _DetailTex ("Detail Texture", 2D) = "grey" {}
        [NoScaleOffset] _DetailNormalMap ("Detail Normals", 2D) = "bump" {}
        _DetailBumpScale ("Detail Bump Scale", Float) = 1
    }

    SubShader {
		
        // This pass look always for the most intensive directional light in the scene.
        // If none is found, _WorldSpaceLightPos0 and _LightColor0 vectors (and similar, I suppose)
        // are 0 vectors
        Pass {
            Tags {
                "LightMode" = "ForwardBase"
            }

            CGPROGRAM

            #pragma target 3.0

            #pragma multi_compile _ VERTEXLIGHT_ON

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #define FORWARD_BASE_PASS

            #include "BumpinessNormalMapAndDetailMapShader.cginc"

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

            // Handy Unity provided shortcut
            #pragma multi_compile_fwdadd
            // Extended version
            //#pragma multi_compile DIRECTIONAL DIRECTIONAL_COOKIE POINT POINT_COOKIE SPOT

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #include "BumpinessNormalMapAndDetailMapShader.cginc"

            ENDCG
        }
	}
}