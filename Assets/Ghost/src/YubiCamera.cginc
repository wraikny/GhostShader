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

bool isForceVisibleMaskEnabled(float2 uv) {
    return tex2D(_YubiForceVisibleMask, uv).a != 0;
}

#define YUBICAMERA_CHECK_DEPTH(TARGET, U, V) \
    if (!TARGET && checkDepth(float2(U, V), __surfaceDistance)) { \
        TARGET = true; \
    }

#define YUBICAMERA_ITERATION(N, SP, SD) { \
    float2 __screenPos = (SP); \
    float __surfaceDistance = (SD); \
    float samplingRange = clamp(_SamplingRange, 0.0, 1.0); \
    [unroll] for (int _i = 0; _i < N; _i++) { \
        float t = ((_i + 0.5) / N) * samplingRange + (1.0 - samplingRange) * 0.5; \
        if (t < __screenPos.x) { \
            YUBICAMERA_CHECK_DEPTH(left, t, __screenPos.y) \
        } else if (!left) { \
            break; \
        } else { \
            YUBICAMERA_CHECK_DEPTH(right, t, __screenPos.y) \
        } \
        if (t < __screenPos.y) { \
            YUBICAMERA_CHECK_DEPTH(down, __screenPos.x, t) \
        } else if (!down) { \
            break; \
        } else { \
            YUBICAMERA_CHECK_DEPTH(up, __screenPos.x, t) \
        } \
        if (left && right && down && up) break; \
    } \
}

void yubiCameraImpl(float2 uv, float4 inScreenPos, float3 inWorldPos) {
    if (insideMirror()) {
        if (!_VisibleInMirror) discard;
    } else {
        if (!isForceVisibleMaskEnabled(uv)) {
            bool left = false, right = false, up = false, down = false;
            float2 screenPos = inScreenPos.xy / inScreenPos.w;
            float surfaceDistance = surfaceWorldDepth(inWorldPos);

            if (getDepth(screenPos) > surfaceDistance) {
                YUBICAMERA_ITERATION(64, screenPos, surfaceDistance)
            }

            bool inFrame = (right && left && up && down);
            if (inFrame != (_VisibleMode == 1)) discard;
        }

    }
}


#endif
