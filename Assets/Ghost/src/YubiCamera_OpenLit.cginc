#ifndef __YUBICAMERA_OPENLIT_INC__
#define __YUBICAMERA_OPENLIT_INC__

#if defined(SHADER_API_GLES)
    #undef _PACK_LIGHTDATAS
#endif

#include "UnityCG.cginc"
#include "Lighting.cginc"
#include "AutoLight.cginc"

// [OpenLit] Include this
#include "OpenLit.cginc"

UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);


#include "YubiCamera.cginc"

bool _EnabledYubiCamera;

struct appdata
{
    float4 vertex   : POSITION;
    float2 uv       : TEXCOORD0;
    float2 uv1      : TEXCOORD1;
    float3 normalOS : NORMAL;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2f
{
    float4 pos          : SV_POSITION;
    float3 positionWS   : TEXCOORD0;
    float4 uv           : TEXCOORD1;
    float3 normalWS     : TEXCOORD2;
    // [OpenLit] Add light datas
    #if defined(_PACK_LIGHTDATAS)
        nointerpolation uint3 lightDatas : TEXCOORD3;
        UNITY_FOG_COORDS(4)
        UNITY_LIGHTING_COORDS(5, 6)
        #if !defined(LIGHTMAP_ON) && UNITY_SHOULD_SAMPLE_SH && defined(VERTEXLIGHT_ON)
            float3 vertexLight  : TEXCOORD7;
        #endif
    #else
        nointerpolation float3 lightDirection : TEXCOORD3;
        nointerpolation float3 directLight : TEXCOORD4;
        nointerpolation float3 indirectLight : TEXCOORD5;
        UNITY_FOG_COORDS(6)
        UNITY_LIGHTING_COORDS(7, 8)
        #if !defined(LIGHTMAP_ON) && UNITY_SHOULD_SAMPLE_SH && defined(VERTEXLIGHT_ON)
            float3 vertexLight  : TEXCOORD9;
        #endif
    #endif
    float4 screenPos : TEXCOORD10;
    UNITY_VERTEX_OUTPUT_STEREO
};

v2f vert(appdata v)
{
    v2f o;
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_OUTPUT(v2f, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

    o.positionWS    = mul(unity_ObjectToWorld, float4(v.vertex.xyz, 1.0)).xyz;
    o.pos           = UnityWorldToClipPos(o.positionWS);
    o.uv.xy         = TRANSFORM_TEX(v.uv, _MainTex);
    o.uv.zw         = TRANSFORM_TEX(v.uv, _YubiForceVisibleMask);
    o.normalWS      = UnityObjectToWorldNormal(v.normalOS);
    o.screenPos     = ComputeNonStereoScreenPos(o.pos);
    UNITY_TRANSFER_FOG(o,o.pos);
    UNITY_TRANSFER_LIGHTING(o,v.uv1);

    // [OpenLit] Calculate and copy vertex lighting
    #if !defined(LIGHTMAP_ON) && UNITY_SHOULD_SAMPLE_SH && defined(VERTEXLIGHT_ON)
        o.vertexLight = ComputeAdditionalLights(o.positionWS, o.pos.xyz) * _VertexLightStrength;
        o.vertexLight = min(o.vertexLight, _LightMaxLimit);
    #endif

    // [OpenLit] Calculate and copy light datas
    OpenLitLightDatas lightDatas;
    ComputeLights(lightDatas, _LightDirectionOverride);
    CorrectLights(lightDatas, _LightMinLimit, _LightMaxLimit, _MonochromeLighting, _AsUnlit);
    #if defined(_PACK_LIGHTDATAS)
        PackLightDatas(o.lightDatas, lightDatas);
    #else
        o.lightDirection    = lightDatas.lightDirection;
        o.directLight       = lightDatas.directLight;
        o.indirectLight     = lightDatas.indirectLight;
    #endif

    return o;
}

float4 frag(v2f i) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

    if (_EnabledYubiCamera) {
        yubiCameraImpl(i.uv.zw, i.screenPos, i.positionWS);
    }
    
    UNITY_LIGHT_ATTENUATION(attenuation, i, i.positionWS);

    // [OpenLit] Copy light datas from the input
    OpenLitLightDatas lightDatas;
    #if defined(_PACK_LIGHTDATAS)
        UnpackLightDatas(lightDatas, i.lightDatas);
    #else
        lightDatas.lightDirection   = i.lightDirection;
        lightDatas.directLight      = i.directLight;
        lightDatas.indirectLight    = i.indirectLight;
    #endif

    float3 N = normalize(i.normalWS);
    float3 L = lightDatas.lightDirection;
    float NdotL = dot(N,L);
    float factor = NdotL > _ShadowThreshold ? 1 : 0;
    if(_ReceiveShadow) factor *= attenuation;

    float4 col = tex2D(_MainTex, i.uv.xy) * _Color;
    float3 albedo = col.rgb;
    col.rgb *= lerp(lightDatas.indirectLight, lightDatas.directLight, factor);
    #if !defined(LIGHTMAP_ON) && UNITY_SHOULD_SAMPLE_SH
        #if defined(VERTEXLIGHT_ON)
            col.rgb += albedo.rgb * i.vertexLight;
        #endif
        col.rgb = min(col.rgb, albedo.rgb * _LightMaxLimit);
    #endif
    UNITY_APPLY_FOG(i.fogCoord, col);
    return col;
}

#endif
