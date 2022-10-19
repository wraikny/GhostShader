Shader "wraiknys/YubiCamera"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color("Color", Color) = (1,1,1,1)

        _Distance("Distance", Float) = 0.5

        [Range(0,1)]
        _SamplingRange("Sampling Range", Float) = 0.8

        [Enum(OutFrame, 0, InFrame, 1)]
        _VisibleMode("Visible Mode", Int) = 1

        [MaterialToggle]
        _VisibleInMirror("Visible in mirror or not", Int) = 0

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
                float3 worldPos : TEXCOORD2;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float4 _Color;

            float _Distance;
            int _Resolution;
            float _SamplingRange;

            int _VisibleMode;
            bool _VisibleInMirror;

            sampler2D _CameraDepthTexture;

            bool IsInMirror() {
                return dot(cross(UNITY_MATRIX_V[0].xyz, UNITY_MATRIX_V[1].xyz), UNITY_MATRIX_V[2].xyz) > 0;
            }

            v2f vert (appdata v)
            {
                v2f o;

                if (!_VisibleInMirror && IsInMirror()) {
                    o.vertex = float4(0,0,0,0);
                    o.uv = float2(0,0);
                    o.worldPos = float3(0,0,0);
                    o.screenPos = float4(0,0,0,0);
                    return o;
                }

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.screenPos = ComputeScreenPos(o.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                return o;
            }

            // Depth (World座標)
            float getDepth(float2 uv) {
                float eyeDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
                return eyeDepth;
            }

            float surfaceWorldDepth(float3 wPos) {
                float3 cameraViewDir = -UNITY_MATRIX_V._m20_m21_m22;
                return dot((wPos - _WorldSpaceCameraPos), cameraViewDir);
            }

            bool checkDepth(float2 uv, float surfaceDistance) {
                float depth = getDepth(uv);
                return (depth < surfaceDistance) && (depth < _Distance);
            }

            #define IMPL(N) do { \
                bool left = false; \
                bool right = false; \
                bool up = false; \
                bool down = false; \
                [unroll] \
                for(int _i = 0; _i < N; _i++) { \
                    float t = ((float)_i + 0.5) / N * _SamplingRange + (1 - _SamplingRange) / 2; \
                    if (checkDepth(float2(t, screenPos.y), surfaceDistance)) { \
                        if (t < screenPos.x) { \
                            left = true; \
                        } else if (!left) { \
                            break; \
                        } else { \
                            right = true; \
                        } \
                    } \
                    if (checkDepth(float2(screenPos.x, t), surfaceDistance)) { \
                        if (t < screenPos.y) { \
                            down = true; \
                        } else if (!down) { \
                            break; \
                        } else { \
                            up = true; \
                        } \
                    } \
                    if (right && left && up && down) break; \
                } \
                bool inFrame = (right && left && up && down); \
                if (inFrame != (_VisibleMode == 1)) discard; \
            } while (0)

            fixed4 frag (v2f i) : SV_Target
            {
                if (IsInMirror()) {
                    if (!_VisibleInMirror) discard;
                } else {
                    float surfaceDistance = surfaceWorldDepth(i.worldPos);
                    float2 screenPos = i.screenPos.xy / i.screenPos.w;

                    IMPL(64);
                }

                fixed4 col = tex2D(_MainTex, i.uv) * _Color;
                return col;
            }
            ENDCG
        }
    }
}
