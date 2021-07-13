Shader "Custom/Spherical Harmonics" {

    Properties {
        _Mterm ("M Term", Range (-2.0, 2.0)) = 0.0
        _Lterm ("L Term", Range (0.0, 2.0)) = 0.0
    }

    SubShader {

        Pass {

            CGPROGRAM

            #pragma target 3.0

            #pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

            #include "UnityCG.cginc"

            float _Mterm;
            float _Lterm;

            struct VertexData {
                float4 position : POSITION;
                float3 normal : NORMAL;
            };

            struct Interpolators {
                float4 position : SV_POSITION;
                float3 normal : TEXCOORD0;
            };

            Interpolators MyVertexProgram (VertexData v) {
                Interpolators i;
                i.position = UnityObjectToClipPos(v.position);
                i.normal = UnityObjectToWorldNormal(v.normal);
                return i;
            }

            float4 MyFragmentProgram (Interpolators i) : SV_TARGET {
                i.normal = normalize(i.normal);

                float t = 0;
                if (_Lterm < 0.5) {
                   t = 1; 
                } else if (_Lterm < 1.5) {
                    if (_Mterm < -0.5) {
                        t = i.normal.y;
                    } else if (_Mterm < 0.5) {
                        t = i.normal.z;
                    } else {
                        t = i.normal.x;
                    }   
                } else {
                    if (_Mterm < -1.5) {
                        t = i.normal.x * i.normal.y;
                    } else if (_Mterm < -0.5) {
                        t = i.normal.y * i.normal.z;
                    } else if (_Mterm < 0.5) {
                        t = i.normal.z * i.normal.z;
                    } else if (_Mterm < 1.5) {
                        t = i.normal.x * i.normal.z;
                    } else if (_Mterm < 2.5) {
                        t = i.normal.x * i.normal.x - i.normal.y * i.normal.y;
                    }    
                }
                float4 color = t > 0 ? t : (float4(1, 0, 0, 1) * -t);
                // If in linear space
                color = pow(color, 2.2);
                return color;
            }

            ENDCG
        }
	}
}