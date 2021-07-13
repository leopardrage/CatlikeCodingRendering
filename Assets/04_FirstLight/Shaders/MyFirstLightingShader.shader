// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/My First Lighting Shader" {

    Properties {
        _Tint ("Tint", Color) = (1, 1, 1, 1)
        _MainTex ("Albedo", 2D) = "white" {}
        _SpecularTint ("Specular", Color) = (0.5, 0.5, 0.5)
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
    }

    SubShader {
		
        Pass {
            Tags {
                "LightMode" = "ForwardBase"
            }

            CGPROGRAM

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            // #include "UnityCG.cginc" // it's already included by the next include
            #include "UnityStandardBRDF.cginc"
            #include "UnityStandardUtils.cginc"

            float4 _Tint;
            sampler2D _MainTex;
            float4 _MainTex_ST;
            float4 _SpecularTint;
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

                // Energy conservation (light contribution cannot exceed 1)
                // Manual version
                // albedo *= 1 - max(_SpecularTint.r, max(_SpecularTint.g, _SpecularTint.b));
                // Using utility included in UnityStandardUtils
                float oneMinusReflectivity;
                albedo = EnergyConservationBetweenDiffuseAndSpecular(albedo, _SpecularTint.rgb, oneMinusReflectivity); 

                // saturate clamps between 0 and 1
                // float3 lightDiffuseIntensity = saturate(dot(lightDir, i.normal));
                float3 lightDiffuseIntensity = DotClamped(lightDir, i.normal); // Slightly optimized version
                float3 diffuse = albedo * lightColor * lightDiffuseIntensity;
                
                // Phong Model
                // float3 reflectionDir = reflect(-lightDir, i.normal);
                // float3 specularLight = pow(DotClamped(viewDir, reflectionDir), _Smoothness * 100);

                // Blinn-Phong Model
                float3 halfVector = normalize(lightDir + viewDir);
                float3 specularLight = pow(DotClamped(halfVector, i.normal), _Smoothness * 100);

                float3 specular = _SpecularTint.rgb * lightColor * specularLight;

                return float4(diffuse + specular, 1);
			}

            ENDCG
        }
	}
}