# GhostShader

## Ghost Shader

`_CameraDepthTexture`から取得した距離に応じて透過するシェーダー。

VRChatではDirectional Lightをアバターに入れないと上手く動かないことがあるので、
CullingMaskにreservedを指定済みかつIntensityを低くしたものをPrefabにした。

Main Textureが空だと描画がおかしくなる場合があったので、whiteテクスチャも入れておいた。

### Properties

* Main Texture: テクスチャ
* Color: 色
* Mirror Alpha: 鏡の中での透過度
* IsFading: 距離に応じて透過を行う
* Min Distance: 透過の最小距離（これより近いと、はっきり見える）
* Max Distance: 透過の最大距離（これより遠いと、まったく見えない）
* Distance Mode: 環境への距離とオブジェクトへの距離のどちらを利用するか
* Force Mirror View: 鏡の中での見え方を確認する（デバッグ用）

## YubiCamera Shader

指で囲った四角形の内側でのみ見えるシェーダー。  
正確には上下左右方向に一定距離以内の深度値がサンプリングされると描画されるシェーダー。

VRChatではDirectional Lightをアバターに入れないと上手く動かないことがあるので、
CullingMaskにreservedを指定済みかつIntensityを低くしたものをPrefabにした。

### Properties

* Main Texture: テクスチャ
* Color: 色
* Distance: 囲いを判定する最大の眼深度（視線方向の距離。カメラからの直線距離ではない）
* Sampling Range: サンプリング範囲
* Force visible mask (Alpha): alpha がしきい値を超えた部分は、枠判定を行わず常に表示する。無効にする部分は alpha を 0 にする。RGB の白黒は判定に使わない。Tiling / Offset は Main Texture から独立している
* Force visible alpha cutoff: 強制表示する alpha のしきい値。初期値 0 は従来の非ゼロ判定に対応し、境界のにじみを抑えたい場合は値を上げる
* Visible Mode: 枠の中でのみ見える(InFrame)か、枠の外でのみ見える(OutFrame)か
* VisibleInMirror: ミラーの中で見えるか
