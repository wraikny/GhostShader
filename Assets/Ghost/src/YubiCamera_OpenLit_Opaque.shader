// Shader example using OpenLit Library
// This code is licensed under CC0 1.0 Universal.
// https://creativecommons.org/publicdomain/zero/1.0/
Shader "wraiknys/YubiCameraOpenLit/Opaque"
{
    Properties
    {
        //------------------------------------------------------------------------------------------------------------------------------
        // Properties for material
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1, 1, 1, 1)
        _ShadowThreshold ("Shadow Threshold", Range(-1,1)) = 0
        [Toggle(_)] _ReceiveShadow ("Receive Shadow", Int) = 0
        [Toggle(_PACK_LIGHTDATAS)] _PackLightDatas ("[Debug] Pack Light Datas", Int) = 0

        //------------------------------------------------------------------------------------------------------------------------------
        // [OpenLit] Properties for lighting

        // It is more accurate to set _LightMinLimit to 0, but the avatar will be black.
        // In many cases, setting a small value will give better results.

        // _VertexLightStrength should be set to 1, but vertex lights will not work properly if there are multiple SkinnedMeshRenderers.
        // And many users seem to prefer to use multiple SkinnedMeshRenderers.
        [Space]
        _AsUnlit                ("As Unlit", Range(0,1)) = 0
        _VertexLightStrength    ("Vertex Light Strength", Range(0,1)) = 0
        _LightMinLimit          ("Light Min Limit", Range(0,1)) = 0.05
        _LightMaxLimit          ("Light Max Limit", Range(0,10)) = 1
        _MonochromeLighting     ("Monochrome lighting", Range(0,1)) = 0
        _LightDirectionOverride ("Light Direction Override", Vector) = (0.001,0.002,0.001,0)

        //------------------------------------------------------------------------------------------------------------------------------
        // [OpenLit] ForwardBase
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend   ("SrcBlend", Int) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend   ("DstBlend", Int) = 0
        [Enum(UnityEngine.Rendering.BlendOp)]   _BlendOp    ("BlendOp", Int) = 0

        //------------------------------------------------------------------------------------------------------------------------------
        [Space]
        [MaterialToggle]
        _EnabledYubiCamera("Enabled YubiCamera", Int) = 1
        
        _Distance("Distance", Float) = 0.5

        _SamplingRange("Sampling Range", Range(0,1)) = 0.8

        _YubiForceVisibleMask("Force visible mask (Alpha)", 2D) = "black" {}
        _YubiForceVisibleCutoff("Force visible alpha cutoff", Range(0,1)) = 0

        [Enum(OutFrame, 0, InFrame, 1)]
        _VisibleMode("Visible Mode", Int) = 1

        [MaterialToggle]
        _VisibleInMirror("Visible in mirror or not", Int) = 0

        [Space]
        [Enum(UnityEngine.Rendering.CullMode)]
        _Cull("Cull Mode", Float) = 2 // Back
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue" = "Geometry+300" "VRCFallback"="Hidden" }
        Cull [_Cull]

        CGINCLUDE
            #pragma skip_variants LIGHTMAP_ON DYNAMICLIGHTMAP_ON LIGHTMAP_SHADOW_MIXING SHADOWS_SHADOWMASK DIRLIGHTMAP_COMBINED

            sampler2D _MainTex;
            float4  _MainTex_ST;
            float4  _Color;
            float   _ShadowThreshold;
            uint    _ReceiveShadow;

            // [OpenLit] Properties for lighting
            float   _AsUnlit;
            float   _VertexLightStrength;
            float   _LightMinLimit;
            float   _LightMaxLimit;
            float   _MonochromeLighting;
            float4  _LightDirectionOverride;
        ENDCG

        Pass
        {
            Tags { "LightMode" = "ForwardBase" }
            BlendOp [_BlendOp], Add
            Blend [_SrcBlend] [_DstBlend], One OneMinusSrcAlpha

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.5
            #pragma multi_compile_fwdbase
            #pragma multi_compile_fog
            #pragma shader_feature_local _ _PACK_LIGHTDATAS

            #include "YubiCamera_OpenLit.cginc"

            ENDCG
        }
    }

    Fallback Off
}
