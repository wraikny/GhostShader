Shader "wraiknys/YubiCamera"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color("Color", Color) = (1,1,1,1)

        _Distance("Distance", Float) = 0.5

        [Enum(N16, 0, N32, 1, N64, 2)]
        _Resolution("Resolution", Int) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue" = "Geometry+300" "VRCFallback"="Toon" }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 screenPos : TEXCOORD1;
                float4x4 mvp_t : TEXCOORD2;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float4 _Color;

            float _Distance;
            int _Resolution;

            sampler2D _CameraDepthTexture;

            float4x4 inverse(float4x4 input)
            {
                // https://answers.unity.com/questions/218333/shader-inversefloat4x4-function.html
                #define minor(a,b,c) determinant(float3x3(input.a, input.b, input.c))
                //determinant(float3x3(input._22_23_23, input._32_33_34, input._42_43_44))

                float4x4 cofactors = float4x4(
                     minor(_22_23_24, _32_33_34, _42_43_44), 
                    -minor(_21_23_24, _31_33_34, _41_43_44),
                     minor(_21_22_24, _31_32_34, _41_42_44),
                    -minor(_21_22_23, _31_32_33, _41_42_43),

                    -minor(_12_13_14, _32_33_34, _42_43_44),
                     minor(_11_13_14, _31_33_34, _41_43_44),
                    -minor(_11_12_14, _31_32_34, _41_42_44),
                     minor(_11_12_13, _31_32_33, _41_42_43),

                     minor(_12_13_14, _22_23_24, _42_43_44),
                    -minor(_11_13_14, _21_23_24, _41_43_44),
                     minor(_11_12_14, _21_22_24, _41_42_44),
                    -minor(_11_12_13, _21_22_23, _41_42_43),

                    -minor(_12_13_14, _22_23_24, _32_33_34),
                     minor(_11_13_14, _21_23_24, _31_33_34),
                    -minor(_11_12_14, _21_22_24, _31_32_34),
                     minor(_11_12_13, _21_22_23, _31_32_33)
                );
                #undef minor
                return transpose(cofactors) / determinant(input);
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.screenPos = ComputeScreenPos(o.vertex);
                o.mvp_t = inverse(UNITY_MATRIX_MVP);
                return o;
            }

            float getDepth(float2 uv, float4x4 mvp_t) {
                float eyeDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
                float3 cameraViewDir = -UNITY_MATRIX_V._m20_m21_m22;
                
                float3 worldPos = mul(unity_ObjectToWorld, float4(mul(mvp_t, float4(uv, 0, 1)).xyz, 1));
                float3 worldViewDir = normalize(UnityWorldSpaceViewDir(worldPos));

                // https://kurotori4423.github.io/KurotoriMkDoc/%E3%82%B7%E3%82%A7%E3%83%BC%E3%83%80%E3%83%BC/CameraDepth2WorldPos/
                return length(eyeDepth * worldViewDir * (1.0 / dot(cameraViewDir, worldViewDir)));
            }

            bool IsInMirror() {
                return dot(cross(UNITY_MATRIX_V[0].xyz, UNITY_MATRIX_V[1].xyz), UNITY_MATRIX_V[2].xyz) > 0;
            }

            #define IMPL(N) do { \
                bool left = false, right = false, up = false, down = false; \
                float d; \
                [unroll] \
                for(int _i = 1; _i < N-1; _i++) { \
                    float t = ((float)_i + 0.5) / N; \
                    d = getDepth(float2(t, screenPos.y), mvp_t); \
                    if (d < thresholdDistance) { \
                        if (t < screenPos.x) { \
                            left = true; \
                        } else { \
                            right = true; \
                        } \
                    } \
                    d = getDepth(float2(screenPos.x, t), mvp_t); \
                    if (d < thresholdDistance) { \
                        if (t < screenPos.y) { \
                            down = true; \
                        } else { \
                            up = true; \
                        } \
                    } \
                    if (right && left && up && down) break; \
                } \
                if (!right || !left || !up || !down) discard; \
            } while (0)

            fixed4 frag (v2f i) : SV_Target
            {
                if (!IsInMirror()) {
                    float2 screenPos = i.screenPos.xy / i.screenPos.w;

                    float thresholdDistance = _Distance;

                    float4x4 mvp_t = i.mvp_t;

                    if (_Resolution == 1) {
                        IMPL(32);
                    } else if (_Resolution == 2) {
                        IMPL(64);
                    } else {
                        IMPL(16);
                    }
                }

                fixed4 col = tex2D(_MainTex, i.uv) * _Color;
                return col;
            }
            ENDCG
        }
    }
}
