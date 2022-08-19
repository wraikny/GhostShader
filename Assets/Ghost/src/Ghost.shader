Shader "wraiknys/Ghost"
{
    Properties
    {
        _MainTex("Main Texture", 2D) = "White" {}
        _Color("Color", Color) = (1,1,1,1)

        // 距離に応じて透過を行う
        [MaterialToggle]_IsFading("Is Fading", Int) = 1

        // 透過の最小距離（これより近いと、はっきり見える）
        _MinDistance("Min Distance", Float) = 0

        // 透過の最大距離（これより遠いと、まったく見えない）
        _MaxDistance("Max Distance", Float) = 5

        [Enum(Depth, 0, Object, 1, Minimum, 2, Maximum, 3)]
        _DistanceMode("Distance Mode", Int) = 0

        [Enum(Linear, 0, InSine, 1, OutSine, 2, InQuad, 3, OutQuad, 4, InCubic, 5, OutCubic, 6)]
        _Easing("Easing", Int) = 0

        [Enum(Tex, 0, ShadowColor, 1)]
        _ShadowColorMode("Shadow Color Mode", Int) = 0

        _ShadowColor("Shadow Color", Color) = (1,1,1,1)

        // 距離に応じて透過を行う
        [MaterialToggle]_IsFadingShadow("Is Fading Shadow", Int) = 1

        [MaterialToggle]_WriteCameraDepthInMirror("Write Camera Depth in Mirror", Int) = 0

        [Enum(UnityEngine.Rendering.CullMode)]
        _Cull("Cull Mode", Float) = 2 // Back

        // 鏡の中での見え方を確認する（デバッグ用）
        [MaterialToggle]_ForceMirrorView("Force Mirror View", Int) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "VRCFallback"="Toon" }
        Cull [_Cull]

        GrabPass { }

        Pass
        {
            ZWrite On
            ColorMask 0
        }

        Pass
        {
            // 影

            ZTest Greater
            ZWrite OFF

            CGPROGRAM
            #pragma vertex mainVert
            #pragma fragment frag
            
            #include "UnityCG.cginc"
            #include "Ghost.cginc"

            fragOut frag(v2f i)
            {
                if (_ForceMirrorView || IsInMirror()) {
                    discard;
                }

                float4 color;
                
                if (_ShadowColorMode == 0) {
                    color = tex2D(_MainTex, i.uv) * _Color;
                } else {
                    color = _ShadowColor;
                }

                float distance = getWorldDistance(i.worldPos, i.screenPos);

                // 見えない
                if (distance >= _MaxDistance) discard;

                fragOut o;
                o.col = color;

                if (_IsFadingShadow) {
                    o.col = fadeColor(o.col, distance, _Easing);
                }

                o.col.rgb = blendGrabTexture(o.col, i.screenPos);

                return o;
            }

            ENDCG
        }

        Pass
        {
            // 通常

            ZWrite OFF

            CGPROGRAM
            #pragma vertex mainVert
            #pragma fragment frag
            
            #include "UnityCG.cginc"
            #include "Ghost.cginc"

            fragOut frag(v2f i)
            {
                if (_ForceMirrorView || IsInMirror()) {
                    discard;
                }

                float4 color = tex2D(_MainTex, i.uv) * _Color;

                float distance = getWorldDistance(i.worldPos, i.screenPos);

                // 見えない
                if (distance >= _MaxDistance) discard;

                fragOut o;

                o.col = color;

                if (_IsFading) {
                    o.col = fadeColor(o.col, distance, _Easing);
                }

                o.col.rgb = blendGrabTexture(o.col, i.screenPos);

                return o;
            }

            ENDCG
        }

        Pass
        {

            // ミラー
            ZWrite OFF

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "UnityCG.cginc"
            #include "Ghost.cginc"

            v2f vert (appdata v)
            {
                v2f o;

                if (!_ForceMirrorView && !IsInMirror()) {
                    o.vertex = float4(0,0,0,0);
                    o.uv = float2(0,0);
                    o.worldPos = float3(0,0,0);
                    o.screenPos = float4(0,0,0,0);
                    return o;
                }

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.screenPos = ComputeGrabScreenPos(o.vertex);

                return o;
            }

            fragOut frag(v2f i)
            {
                if (!_ForceMirrorView && !IsInMirror()) {
                    discard;
                }

                float4 color = tex2D(_MainTex, i.uv) * _Color;

                fragOut o;

                o.col = color;

                o.col.rgb = blendGrabTexture(o.col, i.screenPos);

                return o;
            }

            ENDCG
        }

        Pass
        {
            ZTest Always
            ZWrite On

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            #include "Utils.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float4 screenPos : TEXCOORD0;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.screenPos = ComputeScreenPos(o.vertex);

                return o;
            }

            sampler2D _CameraDepthTexture;
            bool _ForceMirrorView;
            bool _WriteCameraDepthInMirror;

            float frag(v2f i) : SV_Depth {
                if (_ForceMirrorView || IsInMirror()) {
                    if (!_WriteCameraDepthInMirror) {
                        discard;
                    }
                }

                return tex2Dproj(_CameraDepthTexture, i.screenPos).x;
            }

            ENDCG
        }

    }

}
