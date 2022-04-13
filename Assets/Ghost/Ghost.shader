Shader "wraiknys/Ghost"
{
    Properties
    {
        _MainTex("Main Texture", 2D) = "White" {}
        _Color("Color", Color) = (1,1,1,1)

        _MirrorAlpha("Mirror Alpha", Range(0, 1)) = 0.8

        // 距離に応じて透過を行う
        [MaterialToggle]_IsFading("Is Fading", Int) = 1

        // 透過の最小距離（これより近いと、はっきり見える）
        _MinDistance("Min Distance", Float) = 0

        // 透過の最大距離（これより遠いと、まったく見えない）
        _MaxDistance("Max Distance", Float) = 5

        // 鏡の中での見え方を確認する（デバッグ用）
        [MaterialToggle]_ForceMirrorView("Force Mirror View", Int) = 0

        [Enum(UnityEngine.Rendering.CullMode)]
        _Cull("Cull Mode", Float) = 2 // Back
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        ZWrite Off
        Cull [_Cull]

        GrabPass { }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "UnityCG.cginc"

            float4 _Color;

            float _MirrorAlpha;

            sampler2D _MainTex;
            float4 _MainTex_ST;

            sampler2D _GrabTexture;
            sampler2D _CameraDepthTexture;

            float _MinDistance;
            float _MaxDistance;

            bool _IsFading;
            bool _ForceMirrorView;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 grabPos : TEXCOORD1;
                float3 worldPos : TEXCOORD2;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.grabPos = ComputeGrabScreenPos(o.vertex);

                return o;
            }

            struct fragOut
            {
                float4 col : SV_Target;
                float depth : SV_Depth;
            };

            // ワールド座標をDepthに変換する
            float worldPosToDepth(float3 rPos) {
                float4 vpPos = UnityObjectToClipPos(mul(unity_WorldToObject, float4(rPos, 1)).xyz);
                return (vpPos.z / vpPos.w);
            }
            
            // ミラーの中か判定する
            bool IsInMirror() {
                return dot(cross(UNITY_MATRIX_V[0].xyz, UNITY_MATRIX_V[1].xyz), UNITY_MATRIX_V[2].xyz) > 0;
            }

            // 色をGrabTextureと合成する
            float3 blendGrabTexture(float3 col, float4 grabPos, float alpha)
            {
                float3 background = tex2Dproj(_GrabTexture, grabPos).rgb;
                return alpha * col + (1.0 - alpha) * background;
            }

            // EyeDepthからワールド座標に変換する
            float3 depthToWorldPos(float3 worldPos, float eyeDepth) {
                // https://kurotori4423.github.io/KurotoriMkDoc/%E3%82%B7%E3%82%A7%E3%83%BC%E3%83%80%E3%83%BC/CameraDepth2WorldPos/
                float3 cameraViewDir = -UNITY_MATRIX_V._m20_m21_m22;
                float3 worldViewDir = normalize(UnityWorldSpaceViewDir(worldPos));
                float3 wpos = ((eyeDepth * worldViewDir * (1.0 / dot(cameraViewDir, worldViewDir))) + _WorldSpaceCameraPos);

                return wpos;
            }

            fragOut frag(v2f i)
            {
                float eyeDepth = LinearEyeDepth(tex2Dproj(_CameraDepthTexture, i.grabPos).x);

                // _CameraDepthTextureのワールド座標での距離
                float dDistance = length(depthToWorldPos(i.worldPos, eyeDepth) - _WorldSpaceCameraPos);

                float4 color = tex2D(_MainTex, i.uv) * _Color;

                // 見えない
                if (dDistance >= _MaxDistance) discard;

                // 鏡での見え方
                if (_ForceMirrorView || IsInMirror()) {
                    fragOut o;
                    o.depth = worldPosToDepth(i.worldPos);
                    o.col = float4(blendGrabTexture(color.rgb, i.grabPos, _Color.a * _MirrorAlpha), 1);
                    return o;
                }

                fragOut o;
                // 常に見えるように
                o.depth = 1;

                // Fade
                if (_IsFading && (_MinDistance < dDistance) && (dDistance < _MaxDistance))
                {
                    float alpha = 1 - (dDistance - _MinDistance) / (_MaxDistance - _MinDistance);
                    o.col.rgb = float4(blendGrabTexture(color.rgb, i.grabPos, alpha * _Color.a), 1);
                } else {
                    o.col = float4(color.rgb, 1);
                }

                return o;
            }

            ENDCG
        }

    }
}
