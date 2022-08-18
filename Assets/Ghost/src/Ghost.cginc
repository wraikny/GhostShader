#ifndef __wraikny_ghost_inc__
#define __wraikny_ghost_inc__

#include "Utils.cginc"

float4 _Color;
float _Alpha;

sampler2D _GrabTexture;
sampler2D _CameraDepthTexture;

float _MinDistance;
float _MaxDistance;

int _DistanceMode;

bool _IsFading;

int _ShadowColorMode;
float4 _ShadowColor;
bool _IsFadingShadow;

sampler2D _MainTex;
float4 _MainTex_ST;

bool _ForceMirrorView;

// 色をGrabTextureと合成する
float3 blendGrabTexture(float3 col, float4 screenPos, float alpha)
{
    float3 background = tex2Dproj(_GrabTexture, screenPos).rgb;
    return alpha * col + (1.0 - alpha) * background;
}


float getWorldDistance(float3 worldPos, float4 screenPos) {
    float eyeDepth = LinearEyeDepth(tex2Dproj(_CameraDepthTexture, screenPos).x);

    // _CameraDepthTextureのワールド座標での距離
    float depthDistance = length(depthToWorldPos(worldPos, eyeDepth) - _WorldSpaceCameraPos);
    float objectDistance = length(worldPos - _WorldSpaceCameraPos);
    float distance = depthDistance;
    switch (_DistanceMode) {
        case 1:
            distance = objectDistance;
            break;
        case 2:
            distance = min(depthDistance, objectDistance);
            break;
        case 3:
            distance = max(depthDistance, objectDistance);
            break;
        default:
            break;
    }

    return distance;
}

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

struct fragOut
{
    float4 col : SV_Target;
};

v2f mainVert (appdata v)
{
    v2f o;

    if (_ForceMirrorView || IsInMirror()) {
        o.vertex = float4(0,0,0,0);
        o.uv = float2(0,0);
        o.worldPos = float3(0,0,0);
        o.screenPos = float4(0,0,0,0);
        return o;
    }

    o.vertex = UnityObjectToClipPos(v.vertex);
    o.uv = TRANSFORM_TEX(v.uv, _MainTex);
    o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
    o.screenPos = ComputeScreenPos(o.vertex);

    return o;
}

#endif