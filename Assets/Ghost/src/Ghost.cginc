#ifndef __wraikny_ghost_inc__
#define __wraikny_ghost_inc__

#include "Utils.cginc"

float4 _Color;

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

float _Easing;

// 色をGrabTextureと合成する
float3 blendGrabTexture(float4 col, float4 screenPos)
{
    float3 background = tex2Dproj(_GrabTexture, screenPos).rgb;
    return col.a * col + (1.0 - col.a) * background;
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

#define EASING_Linear 0
#define EASING_InSine 1
#define EASING_OutSine 2
#define EASING_InQuad 3
#define EASING_OutQuad 4
#define EASING_InQubic 5
#define EASING_OutQubic 6

float getEasing(int easing, float t) {
    const float pi = 3.1415926535;

    if (t <= 0) return 0;
    if (t >= 1) return 1;

    switch(easing) {
        case EASING_Linear: return t;
        case EASING_InSine: return 1 - cos(t * pi * 0.5);
        case EASING_OutSine: return sin(t * pi * 0.5);
        case EASING_InQuad: return t * t;
        case EASING_OutQuad: return t * (2 - t);
        case EASING_InQubic: return t * t * t;
        case EASING_OutQubic: return (t - 1) * (t - 1) * (t - 1) + 1;
        default: return t;
    }
}

float4 fadeColor(float4 color, float distance, int easing) {
    if ((_MinDistance < distance) && (distance < _MaxDistance))
    {
        float alpha = 1 - (distance - _MinDistance) / (_MaxDistance - _MinDistance);
        
        alpha = getEasing(easing, alpha);

        return float4(color.rgb, alpha * color.a);
    }

    return color;
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