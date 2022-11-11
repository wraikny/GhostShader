#ifndef __YUBICAMERA_INCLUDE__
#define __YUBICAMERA_INCLUDE__

#include "UnityCG.cginc"

float _Distance;
float _SamplingRange;

int _VisibleMode;
bool _VisibleInMirror;

sampler2D _YubiForceVisibleMask;

bool insideMirror() {
    return dot(cross(UNITY_MATRIX_V[0].xyz, UNITY_MATRIX_V[1].xyz), UNITY_MATRIX_V[2].xyz) > 0;
}

// Depth (World座標)
float getDepth(in float2 uv) {
    float eyeDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
    return eyeDepth;
}

float surfaceWorldDepth(in float3 wPos) {
    float3 cameraViewDir = -UNITY_MATRIX_V._m20_m21_m22;
    return dot((wPos - _WorldSpaceCameraPos), cameraViewDir);
}

bool checkDepth(float2 uv, in float surfaceDistance) {
    float depth = getDepth(uv);
    return (depth < surfaceDistance) && (depth < _Distance);
}

float2 adjustStereo(float2 uv) {
#if UNITY_SINGLE_PASS_STEREO
    // float4 scaleOffset = unity_StereoScaleOffset[unity_StereoEyeIndex];
    // uv = (uv - scaleOffset.zw) / scaleOffset.xy;
    // return float2(uv.x * 0.5 + unity_StereoEyeIndex * 0.5, uv.y);
#endif
    return uv;
}

bool isForceVisibleMaskEnabled(in float2 uv) {
    return tex2D(_YubiForceVisibleMask, uv).a != 0;
}

void yubiCameraImpl(float2 uv, float4 inScreenPos, float3 inWorldPos) {
    if (insideMirror()) {
        if (!_VisibleInMirror && !isForceVisibleMaskEnabled(uv)) discard;
    } else {
        if (!isForceVisibleMaskEnabled(uv)) {
            bool left = false, right = false, up = false, down = false;
            float2 screenPos = inScreenPos.xy / inScreenPos.w;
            float surfaceDistance = surfaceWorldDepth(inWorldPos);

            if (getDepth(screenPos) > surfaceDistance) {
                const int iterCount = 128;
                const float m = 8;

                const float samplingRange = clamp(_SamplingRange, 0.0, 1.0);

                for (int _i = 0; _i < iterCount; _i++) {
                    float t = ((float)_i / iterCount);
                    t = fmod(m * t + floor(m * t) / iterCount, 1.0);
                    t = t * samplingRange + (1.0 - samplingRange) * 0.5;

                    const bool depthPassX = checkDepth(adjustStereo(float2(t, screenPos.y)), surfaceDistance);
                    const bool depthPassY = checkDepth(float2(screenPos.x, t), surfaceDistance);

                    left = left || ((t < screenPos.x) && depthPassX);
                    right = right || ((screenPos.x <= t) && depthPassX);
                    down = down || ((t < screenPos.y) && depthPassY);
                    up = up || ((screenPos.y <= t) && depthPassY);

                    if (left && right && down && up) break;
                }
            }

            bool inFrame = (right && left && up && down);
            if (inFrame != (_VisibleMode == 1)) discard;
        }
    }
}


#endif
