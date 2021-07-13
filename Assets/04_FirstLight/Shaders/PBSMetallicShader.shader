Shader "Custom/PBS Metallic Shader" {

    Properties {
        _Tint ("Tint", Color) = (1, 1, 1, 1)
        _MainTex ("Albedo", 2D) = "white" {}
        [Gamma] _Metallic ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
    }

    SubShader {
		
        Pass {
            Tags {
                "LightMode" = "ForwardBase"
            }

            CGPROGRAM

            #pragma target 3.0

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            // #include "UnityCG.cginc" // it's already included by UnityPBSLighting
            // #include "UnityStandardBRDF.cginc" // it's already included by UnityPBSLighting
            #include "UnityPBSLighting.cginc"

            float4 _Tint;
            sampler2D _MainTex;
            float4 _MainTex_ST;
            float _Metallic;
            float _Smoothness;

            struct VertexData {
                float4 position : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Interpolators {
				float4 position : SV_POSITION;
				float2 uv : TEXCOORD0;
                float3 normal : TEXCOORD1;
                float3 worldPos : TEXCOORD2;
			};

            Interpolators MyVertexProgram (VertexData v) {
                Interpolators i;
                i.uv = TRANSFORM_TEX(v.uv, _MainTex);
                i.position = UnityObjectToClipPos(v.position);
                i.worldPos = mul(unity_ObjectToWorld, v.position);
                i.normal = UnityObjectToWorldNormal(v.normal);
                // i.normal = mul(transpose((float3x3)unity_WorldToObject), v.normal);
                i.normal = normalize(i.normal);
                return i;
			}

			float4 MyFragmentProgram (Interpolators i) : SV_TARGET {
                // Linerarly interpolating unit vectors doesn't produce unit vectors
                // The difference is very small, though, so not normalizing at this stage
                // is a common optimization, typical of mobile devices
                i.normal = normalize(i.normal);

                // _WorldSpaceLightPos0 is the position of the main light in homogeneous coordinates (if it'a point light)
                // or is the diraction of the main light (if it's a directional light)
                float3 lightDir = _WorldSpaceLightPos0.xyz;

                float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);

                // _LightColor0 is defined in UnityLightingCommon and is the color of the main light
                float3 lightColor = _LightColor0.rgb;

                float3 albedo = tex2D(_MainTex, i.uv).rgb * _Tint.rgb;

                //
                // Metallic flow logic
                //

                // Oversemplification: metal has specular but no albedo, dielectries the other way around
                // float3 specularTint = albedo * _Metallic;
                // float oneMinusReflectivity = 1 - _Metallic;
                // albedo *= oneMinusReflectivity;

                // More realistic approach, using a utility function of UnityStandardUtils
                float3 specularTint;
                float oneMinusReflectivity;
                albedo = DiffuseAndSpecularFromMetallic(albedo, _Metallic, specularTint, oneMinusReflectivity);

                //
                // -----
                //

                UnityLight light;
                light.color = lightColor;
                light.dir = lightDir;
                light.ndotl = DotClamped(i.normal, lightDir);
                UnityIndirect indirectLight;
                indirectLight.diffuse = 0;
                indirectLight.specular = 0;

                return UNITY_BRDF_PBS(
                    albedo,
                    specularTint,
                    oneMinusReflectivity,
                    _Smoothness,
                    i.normal,
                    viewDir,
                    light,
                    indirectLight
                );
			}

            ENDCG
        }
	}
}