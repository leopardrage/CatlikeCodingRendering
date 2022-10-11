Shader "Custom/TriplanarMappingSpecific" {

    Properties {
        [NoScaleOffset] _MainTex ("Albedo", 2D) = "white" {}
        [NoScaleOffset] _MOHSMap ("MOHS", 2D) = "white" {}
        [NoScaleOffset] _NormalMap ("Normals", 2D) = "white" {}

        [NoScaleOffset] _TopMainTex ("Top Albedo", 2D) = "white" {}
        [NoScaleOffset] _TopMOHSMap ("Top MOHS", 2D) = "white" {}
        [NoScaleOffset] _TopNormalMap ("Top Normals", 2D) = "white" {}

        _MapScale ("Map Scale", Float) = 1
        // We cap the offset to 0.5 because we want to avoid totally
        // flattening vectors close to normalize((1, 1, 1)) = (0.57, 0.57, 0.57)
        // If you try values higher than that (e.g.: 0.6), sudden changes happens
        // when approaching the aforementioned orientation becoming black
        // (weights all zero) when closing more
        _BlendOffset ("Blend Offset", Range(0, 0.5)) = 0.25
        _BlendExponent ("Blend Exponent", Range(1, 8)) = 2
        _BlendHeightStrength ("Blend Height Strength", Range(0, 0.99)) = 0.5
    }

    SubShader {
		
        Pass {
            Tags {
                "LightMode" = "ForwardBase"
            }

            CGPROGRAM
            
            #pragma target 3.0

            #pragma shader_feature _SEPARATE_TOP_MAPS

            #pragma multi_compile_fwdbase
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #define FORWARD_BASE_PASS

            #include "TriplanarMappingTriplanarMapping.cginc"
            #include "TriplanarMappingShared.cginc"

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

            #pragma shader_feature _SEPARATE_TOP_MAPS
            
            #pragma multi_compile_fwdadd_fullshadows
            #pragma multi_compile_fog

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #include "TriplanarMappingTriplanarMapping.cginc"
            #include "TriplanarMappingShared.cginc"

            ENDCG
        }

        Pass {
			Tags {
				"LightMode" = "Deferred"
			}

			CGPROGRAM

			#pragma target 3.0
			#pragma exclude_renderers nomrt

            #pragma shader_feature _SEPARATE_TOP_MAPS

			#pragma multi_compile_prepassfinal
			#pragma multi_compile_instancing

			#pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

			#define DEFERRED_PASS

			#include "TriplanarMappingTriplanarMapping.cginc"
            #include "TriplanarMappingShared.cginc"

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

			#pragma vertex MyShadowVertexProgram
            #pragma fragment MyShadowFragmentProgram

            #include "Assets/Shared/Shaders/SemitransparentShadowShared.cginc"

			ENDCG
		}

        Pass {
			Tags {
				"LightMode" = "Meta"
			}

            Cull Off

			CGPROGRAM

            #pragma vertex MyLightmappingVertexProgram
			#pragma fragment MyLightmappingFragmentProgram

            #pragma shader_feature _SEPARATE_TOP_MAPS

            #define META_PASS_NEEDS_NORMALS
            #define META_PASS_NEEDS_POSITION

            #include "TriplanarMappingTriplanarMapping.cginc"
            #include "TriplanarMappingSpecificMeta.cginc"

			ENDCG
		}
	}

    CustomEditor "TriplanarMappingSpecificGUI"
}