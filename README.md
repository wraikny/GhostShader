# Ghost Shader

`_CameraDepthTexture`から取得した距離に応じて透過するシェーダー。

VRChatではDirectional Lightをアバターに入れないと上手く動かないことがあるので、
CullingMaskにreservedを指定済みかつIntensityを低くしたものをPrefabにした。

Main Textureが空だと描画がおかしくなる場合があったので、whiteテクスチャも入れておいた。

## Properties

* Main Texture: テクスチャ
* Color: 色
* Mirror Alpha: 鏡の中での透過度
* IsFading: 距離に応じて透過を行う
* Min Distance: 透過の最小距離（これより近いと、はっきり見える）
* Max Distance: 透過の最大距離（これより遠いと、まったく見えない）
* Distance Mode: 環境への距離とオブジェクトへの距離のどちらを利用するか
* Force Mirror View: 鏡の中での見え方を確認する（デバッグ用）
