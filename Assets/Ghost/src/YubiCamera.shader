Shader "wraiknys/YubiCamera"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color("Color", Color) = (1,1,1,1)

        _Distance("Distance", Float) = 0.5

        [Enum(N16, 0, N32, 1, N64, 2)]
        _Resolution("Sampling Resolution", Int) = 0
        
        [Range(0,1)]
        _SamplingRange("Sampling Range", Float) = 0.9

        [MaterialToggle]
        _VisibleInMirror("Visible in Mirror", Int) = 1
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
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float4 _Color;

            float _Distance;
            int _Resolution;
            float _SamplingRange;
            bool _VisibleInMirror;

            sampler2D _CameraDepthTexture;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.screenPos = ComputeScreenPos(o.vertex);
                return o;
            }

            float getDepth(float2 uv) {
                float eyeDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
                return eyeDepth;
            }

            bool IsInMirror() {
                return dot(cross(UNITY_MATRIX_V[0].xyz, UNITY_MATRIX_V[1].xyz), UNITY_MATRIX_V[2].xyz) > 0;
            }

            #define IMPL(N) do { \
                bool left = false; \
                bool right = false; \
                bool up = false; \
                bool down = false; \
                [unroll] \
                for(int _i = 0; _i < N; _i++) { \
                    float t = ((float)_i + 0.5) / N * _SamplingRange + (1 - _SamplingRange) / 2; \
                    if (getDepth(float2(t, screenPos.y)) < _Distance) { \
                        if (t < screenPos.x) { \
                            left = true; \
                        } else { \
                            right = true; \
                        } \
                    } \
                    if (getDepth(float2(screenPos.x, t)) < _Distance) { \
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
                if (IsInMirror()) {
                    if (!_VisibleInMirror) discard;
                } else {
                    float2 screenPos = i.screenPos.xy / i.screenPos.w;

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
