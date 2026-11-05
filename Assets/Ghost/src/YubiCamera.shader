Shader "wraiknys/YubiCamera"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color("Color", Color) = (1,1,1,1)

        _Distance("Distance", Float) = 0.5

        _SamplingRange("Sampling Range", Range(0,1)) = 0.8

        _YubiForceVisibleMask("Force visible mask (Alpha)", 2D) = "black" {}
        _YubiForceVisibleCutoff("Force visible alpha cutoff", Range(0,1)) = 0

        [Enum(OutFrame, 0, InFrame, 1)]
        _VisibleMode("Visible Mode", Int) = 1

        [MaterialToggle]
        _VisibleInMirror("Visible in mirror or not", Int) = 0

    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue" = "Geometry+300" "VRCFallback"="Hidden" }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.5

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 uv : TEXCOORD0;
                float4 screenPos : TEXCOORD1;
                float3 worldPos : TEXCOORD2;
                float4 vertex : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float4 _Color;

            UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);
            
            #include "YubiCamera.cginc"

            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
                o.uv.zw = TRANSFORM_TEX(v.uv, _YubiForceVisibleMask);
                o.screenPos = ComputeNonStereoScreenPos(o.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                yubiCameraImpl(i.uv.zw, i.screenPos, i.worldPos);

                fixed4 col = tex2D(_MainTex, i.uv.xy) * _Color;
                return col;
            }
            ENDCG
        }
    }
}
