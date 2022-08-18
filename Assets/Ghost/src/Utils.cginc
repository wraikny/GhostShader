#ifndef __wraikny_ghost_utils_inc__
#define __wraikny_ghost_utils_inc__

// ワールド座標をDepthに変換する
float worldPosToDepth(float3 rPos) {
    float4 vpPos = UnityObjectToClipPos(mul(unity_WorldToObject, float4(rPos, 1)).xyz);
    return (vpPos.z / vpPos.w);
}

// ミラーの中か判定する
bool IsInMirror() {
    return dot(cross(UNITY_MATRIX_V[0].xyz, UNITY_MATRIX_V[1].xyz), UNITY_MATRIX_V[2].xyz) > 0;
}

// EyeDepthからワールド座標に変換する
float3 depthToWorldPos(float3 worldPos, float eyeDepth) {
    // https://kurotori4423.github.io/KurotoriMkDoc/%E3%82%B7%E3%82%A7%E3%83%BC%E3%83%80%E3%83%BC/CameraDepth2WorldPos/
    float3 cameraViewDir = -UNITY_MATRIX_V._m20_m21_m22;
    float3 worldViewDir = normalize(UnityWorldSpaceViewDir(worldPos));
    float3 wpos = ((eyeDepth * worldViewDir * (1.0 / dot(cameraViewDir, worldViewDir))) + _WorldSpaceCameraPos);

    return wpos;
}

#endif