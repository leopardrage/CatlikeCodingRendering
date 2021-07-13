Shader "Custom/Multiple Light PBS Shader" {

    Properties {
        _Tint ("Tint", Color) = (1, 1, 1, 1)
        _MainTex ("Albedo", 2D) = "white" {}
        [Gamma] _Metallic ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
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

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #include "MyPBSLighting.cginc"

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

            #include "MyPBSLighting.cginc"

            ENDCG
        }
	}
}