#ifndef __YUBICAMERA_INCLUDE__
#define __YUBICAMERA_INCLUDE__

#include "UnityCG.cginc"

float _Distance;
float _SamplingRange;

int _VisibleMode;
bool _VisibleInMirror;

sampler2D _YubiForceVisibleMask;
float4 _YubiForceVisibleMask_ST;
float _YubiForceVisibleCutoff;

bool insideMirror() {
    return dot(cross(UNITY_MATRIX_V[0].xyz, UNITY_MATRIX_V[1].xyz), UNITY_MATRIX_V[2].xyz) > 0;
}

// UVs used by the frame test are eye-local; pack only when sampling depth.
float getDepth(in float2 eyeUV) {
    float2 depthUV = UnityStereoTransformScreenSpaceTex(eyeUV);
    float eyeDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_LOD(_CameraDepthTexture, float4(depthUV, 0, 0)));
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

bool isForceVisibleMaskEnabled(in float2 uv) {
    return tex2D(_YubiForceVisibleMask, uv).a > _YubiForceVisibleCutoff;
}

bool isInYubiFrame(in float2 screenPos, in float surfaceDistance) {
    const float samplingRange = clamp(_SamplingRange, 0.0, 1.0);
    const float sampleMin = (1.0 - samplingRange) * 0.5;
    const float sampleMax = sampleMin + samplingRange;

    // No samples can surround a point outside the sampling region.
    if (samplingRange <= 0.0 || _Distance <= 0.0 ||
        screenPos.x <= sampleMin || screenPos.x > sampleMax ||
        screenPos.y <= sampleMin || screenPos.y > sampleMax) return false;

    if (!(getDepth(screenPos) > surfaceDistance)) return false;

    bool left = false, right = false, up = false, down = false;
    const int iterCount = 128;
    const float m = 8;

    for (int _i = 0; _i < iterCount; _i++) {
        float t = ((float)_i / iterCount);
        t = fmod(m * t + floor(m * t) / iterCount, 1.0);
        t = t * samplingRange + sampleMin;

        // Each flag is monotonic: once found, that direction needs no more reads.
        if (t < screenPos.x) {
            if (!left) left = checkDepth(float2(t, screenPos.y), surfaceDistance);
        } else {
            if (!right) right = checkDepth(float2(t, screenPos.y), surfaceDistance);
        }
        if (t < screenPos.y) {
            if (!down) down = checkDepth(float2(screenPos.x, t), surfaceDistance);
        } else {
            if (!up) up = checkDepth(float2(screenPos.x, t), surfaceDistance);
        }

        if (left && right && down && up) return true;
    }
    return false;
}

void yubiCameraImpl(float2 maskUV, float4 inScreenPos, float3 inWorldPos) {
    if (insideMirror()) {
        if (!_VisibleInMirror && !isForceVisibleMaskEnabled(maskUV)) discard;
    } else {
        if (!isForceVisibleMaskEnabled(maskUV)) {
            // inScreenPos must come from ComputeNonStereoScreenPos.
            float2 screenPos = inScreenPos.xy / inScreenPos.w;
            float surfaceDistance = surfaceWorldDepth(inWorldPos);

            bool inFrame = isInYubiFrame(screenPos, surfaceDistance);
            if (inFrame != (_VisibleMode == 1)) discard;
        }
    }
}


#endif
