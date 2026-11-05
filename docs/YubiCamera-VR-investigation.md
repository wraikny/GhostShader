# YubiCamera の VR 表示不具合調査

調査日: 2026-11-03。対象: このチェックアウトと Unity 2019.4.31f1 の Built-in Shader Includes。
調査後、下記の座標修正・深度宣言修正をシェーダー本体へ適用済み。マテリアル・プロジェクト設定は変更していない。
HMD 上の再現・修正確認は未実施。Unity コンパイル確認はライセンス検証で起動が終了したため未完了。

## 結論と確度

Single Pass Stereo（Double-Wide）では、横方向の探索が現在の眼の範囲を越え、反対の眼の深度を左右判定に利用する不具合がコード上で確認できる。
「右目では左側が開いていても通り、左目では右側が開いていても通る」という症状の方向と一致する。
追加情報として、ユーザーから「VRChat の VR で発生し、Desktop では発生しない」と確認できた。
VRChat 公式情報でも PC VR の Single-Pass Stereo 継続が確認でき、原因候補の確度は高まった（末尾参照）。
ただし、不具合発生時のクライアント版・GPU 上の実測は未確認なので、実機症状の原因の最終確定には比較検証が必要。

別途、Single Pass Instanced / Multiview では深度テクスチャの宣言が対応していない。
Multi Pass には Double-Wide の座標問題は当てはまらず、その方式でも発生する場合は追加調査が必要。

## 1. 横方向の探索が両眼を横断する

該当箇所:

- `Assets/Ghost/src/YubiCamera.shader`: 頂点側で `ComputeScreenPos(o.vertex)` を使用。
- `Assets/Ghost/src/YubiCamera_OpenLit.cginc`: 同じく `ComputeScreenPos(o.pos)` を使用。
- `Assets/Ghost/src/YubiCamera.cginc`: `screenPos` の算出、`depthPassX`、`left` / `right` の更新。
- 同ファイルの `adjustStereo()` はコメントのみで、引数をそのまま返す。

インストール済みの Unity 2019.4.31f1 の `Editor/Data/CGIncludes/UnityCG.cginc:798-810` を確認した。
`ComputeScreenPos()` は `UNITY_SINGLE_PASS_STEREO` 時に、眼ごとの scale / offset を適用済みの座標を返す。
典型的な Double-Wide の場合、w 除算後の x は以下となる。

| 座標 | 左眼 | 右眼 |
| --- | --- | --- |
| 眼内 UV | 0–1 | 0–1 |
| 深度テクスチャ全体の UV | 0–0.5 | 0.5–1 |
| 眼の中央の x | 0.25 | 0.75 |

一方、探索用の `t` は全体の 0–1 を基準に生成される。`_SamplingRange = 0.8` では約 0.1–0.9 を探索する。

```hlsl
checkDepth(adjustStereo(float2(t, screenPos.y)), surfaceDistance);
left  = left  || ((t < screenPos.x)  && depthPassX);
right = right || ((screenPos.x <= t) && depthPassX);
```

このため右眼の x=0.75 に対して、左眼内の近い物体 x=0.15 が `left` を満たせる。
逆に左眼の x=0.25 に対して、右眼内の近い物体 x=0.85 が `right` を満たせる。
上下の条件を本来の上下の指が満たせば、欠けた辺があるのに `inFrame` が true になる。

通常の「現在のピクセルの深度」取得 `getDepth(screenPos)` は Double-Wide として整合している。
そこだけ可視化しても、この横方向探索の問題は見つからない。縦方向探索は x を固定しているため、典型的な横並び配置では反対の眼に移らない。

Unity の公式資料も、Single Pass の packed texture と眼ごとの UV 変換・範囲制限を説明している。
[Single Pass Stereo rendering (Unity 2019.4)](https://docs.unity3d.com/2019.4/Documentation/Manual/SinglePassStereoRendering.html)

## 2. 数値での切り分け

既存コードと同じ 128 回の `t` 生成・並べ替え・Sampling Range 0.8 を PowerShell 上で計算した。
水平線上の packed UV x=0.15 と x=0.85 の周辺（幅 ±0.02）だけで深度条件が通ると仮定した。
これは「左眼には左辺だけ、右眼には右辺だけ」の模擬深度である。

| 対象の眼・欠けた辺 | 現状の (left, right) | 眼内で探索した場合の (left, right) |
| --- | --- | --- |
| 左眼・右辺なし | (true, true) | (true, false) |
| 右眼・左辺なし | (true, true) | (false, true) |

実機の深度画像を使った再現ではないが、現在のアルゴリズムが報告と同じ向きの誤判定を作れることを確認した。

## 3. 修正方針

判定・走査はすべて眼内 UV（0–1）にそろえ、深度取得の直前にだけテクスチャ用 UV へ変換する。
以下の修正を本体へ適用済み。

両方の頂点シェーダーの screenPos 計算を変更する。

```hlsl
// 通常版
o.screenPos = ComputeNonStereoScreenPos(o.vertex);
// OpenLit 版
o.screenPos = ComputeNonStereoScreenPos(o.pos);
```

共通の `getDepth()` で変換する。

```hlsl
float getDepth(in float2 eyeUV) {
    float2 depthUV = UnityStereoTransformScreenSpaceTex(eyeUV);
    return LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, depthUV));
}
```

横走査は `checkDepth(float2(t, screenPos.y), surfaceDistance)` とし、不要になった `adjustStereo()` を削除する。
中心・横・縦のすべての取得が同じ `getDepth()` を通るので、変換箇所を統一できる。
これにより Sampling Range と左右の比較も、両眼とも眼内 0–1 を基準に扱える。

`adjustStereo()` だけを復活させる修正では不十分。
深度サンプルを現在の眼へ移しても、`t` と packed `screenPos.x` の比較に異なる座標系が残る。
また、変換済みの `ComputeScreenPos()` 出力へ重ねて変換すると二重変換になる。

## 4. Instanced / Multiview の別問題

修正前は通常版と OpenLit 共通部の宣言が、両方とも以下になっていた。

```hlsl
sampler2D _CameraDepthTexture;
```

Unity 2019.4.31f1 の `HLSLSupport.cginc:744-759` では、Instanced / Multiview 時に
`SAMPLE_DEPTH_TEXTURE` が `unity_StereoEyeIndex` を配列レイヤーに使う Texture2DArray サンプリングへ置き換わる。
宣言側も次にそろえる必要がある。

```hlsl
UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);
```

修正前は宣言とサンプル処理が一致せず、当該バリアントでコンパイルや取得が正しく行われない可能性があった。
今回、両方を `UNITY_DECLARE_DEPTH_TEXTURE` に変更済み。
これは Double-Wide の左右走査とは別の不具合。
既存コードには頂点での instance ID 初期化・ステレオ出力と、fragment 冒頭での eye index 設定は入っている。
`UnityShaderVariables.cginc:14-24` でも `UNITY_MATRIX_V` と `_WorldSpaceCameraPos` が眼別の値へ切り替わることを確認した。
そのため `surfaceWorldDepth()` を無条件に頭の中央基準と見なす根拠はない。

[Single Pass Instanced rendering (Unity 2019.4)](https://docs.unity3d.com/2019.4/Documentation/Manual/SinglePassInstancing.html)
は描画方式による 2D / 配列の違いと、深度用マクロの参照先を説明している。

## 5. 実行環境での確認手順

1. 発生環境の Unity バージョン・Graphics API・実際のステレオ方式を記録する。
   このチェックアウトは Unity 2019.4.31f1、保存設定は VR 無効、`m_StereoRenderingPath: 0`。
   これだけでは、別プロジェクトや VRChat 内での実行方式は分からない。
2. 深度へ書き込む不透明な物体で上下左右の枠を作り、対象をその奥に置く。
   枠は near clip より遠く、`_Distance` より近く配置し、強制表示マスクの影響を除く。
3. 左右を片側ずつ外し、それぞれの眼を確認する。上下も同様に確認する。
   視差のため、物体が実際に各眼の視野内にあることも確認する。
4. 一時的に左右フラグを色として表示すると、最終的な discard だけを見るより切り分けやすい。
   例: `float4(left ? 1.0 : 0.0, right ? 1.0 : 0.0, 0, 1)`。
   これは通常の discard より前に返す診断用変更とする。
5. Double-Wide なら、片眼にのみ存在する深度が反対眼のフラグに影響するか比較する。
   修正後にその影響がなくなること、四辺ありなら両眼で通ることを確認する。
6. Multi Pass / Double-Wide / Instanced を実行環境が対応する範囲で比較し、通常版・OpenLit Opaque・Transparent を確認する。

Multi Pass でも残る場合は、取得した深度と各フラグの可視化を優先する。
このシェーダーは輪郭の閉鎖性を判定せず、同じ行・列に近い深度があるかだけを判定するため、
別の指・手・身体・周辺物体でも条件が成立する。また、透明物体や ShadowCaster の有無など、
深度テクスチャに実際に含まれる物体の確認も必要。

## 6. VRChat の描画方式を追加調査した結果

対象は PC 版 VRChat の VR 主視点。Quest 単体版の方式へ一般化しない。

### 公式情報と時系列

| 日付 | 確認できたこと | 出典 |
| --- | --- | --- |
| 2022-04-21 | SDK が Mono / Single-Pass Stereo に加え、将来に備え SPS-I 用バリアントも生成するようになった。実行方式の切り替え告知ではない。 | [VRChat 2022.1.2](https://docs.vrchat.com/docs/vrchat-202212) |
| 2026-06-25 | Unity 6 ベータでも描画パイプラインを変更せず、SPS-I ではなく Single-Pass Stereo を特別な Unity ビルドで維持すると明記。 | [Developer Update - 25 June 2026](https://ask.vrchat.com/t/developer-update-25-june-2026/48618) |
| 2026-10-02 | クライアントの Unity 6 移行が正式リリース。SDK 側の移行とは別。 | [VRChat 2026.3.3](https://docs.vrchat.com/docs/vrchat-202633) |
| 2026-10-30 | SDK 3.10.6 は引き続き Unity 2022.3 を利用。 | [Release 3.10.6](https://creators.vrchat.com/releases/release-3-10-6/) |

「Unity の新しい版なら VRChat も必ず Instanced」と推定してはいけない。
公式に確認できた方式は Single-Pass Stereo。2026-10-02 の正式移行告知には SPS-I への変更の記述はなく、
2026-06-25 に説明された方式の継続と読むのが妥当。ただし今回、稼働中クライアントの GPU キャプチャは行っていない。
また、このリポジトリの Player Settings は VRChat クライアントの描画方式を決めるものではない。

### Desktop と VR で違いが出る理由

Unity の Double-Wide の仕様と上記 VRChat 情報を合わせると、主視点の深度を次のように扱う必要がある。

```text
Desktop: [        単眼 0 .. 1        ]
PC VR:   [ 左眼 0 .. 0.5 ][ 右眼 0.5 .. 1 ]
```

Desktop は画面全体と眼内の範囲が一致するので、今の 0–1 の探索でも別眼を読むことがない。
VR では `ComputeScreenPos()` が現在の眼の半分へ変換する一方、横走査の t は全体を動く。
この違いから、Desktop で正常・VR で左右対称に片側だけ誤判定することを説明できる。
これはシェーダー自身の任意のサンプリング座標の問題であり、Unity が左右の深度を勝手に混ぜているという意味ではない。

### 深度が存在する条件、主視点とカメラの違い

[VRCCameraSettings の公式説明](https://creators.vrchat.com/worlds/udon/vrc-graphics/vrc-camera-settings/)では、
`ScreenCamera` が主視点で、VR 時はステレオとなる。
深度は `DepthTextureMode` または影を有効にしたリアルタイムライトで生成を要求できる。
`PhotoCamera` は常に Depth が有効であるため、手持ちカメラで正常でも主視点での正常動作の証明にはならない。
`DepthTextureMode.None` だけを見ても、ライトによって深度が生成されていないとは判断できない。
この API はワールドの Udon 向けであり、アバターから直接呼べる修正手段ではない。

README にある「Directional Light を入れる」対策は深度生成の有無に関するもの。
眼をまたいだ探索を修正する効果はない。
Unity Built-in の通常の DepthTextureMode.Depth 生成では、ShadowCaster パス（fallback 含む）と不透明側の Queue <= 2500 が重要になる。
見えている指が必ず深度にも入るとは限らない。
[Unity: Cameras and depth textures](https://docs.unity3d.com/2019.4/Documentation/Manual/SL-CameraDepthTexture.html)

ミラーも別の描画コンテキストなので、主視点とは分けて確認する。
VRChat の `_VRChatMirrorMode` は通常描画 / VR ミラー / Desktop ミラーを区別する公式グローバル変数。
ただし現在の `insideMirror()` は行列で判定しており、今回この部分は変更しない。
[VRChat Shader Globals](https://creators.vrchat.com/worlds/udon/vrc-graphics/vrchat-shader-globals/)

### 原因確定のために次に行う比較

優先するのは第3節の眼内座標への統一。Instanced 用宣言の修正は互換性対策として扱い、今回の原因と混同しない。
同じ VRChat ワールド・同じ視点で、現状版と座標修正版を比較する。
閉じた枠、左辺なし、右辺なし、上辺なし、下辺なしで左右眼それぞれの判定を確認する。
主視点とミラー、手持ちカメラは別々に記録する。

方式の追加確認が必要なら、一時的な診断表示で `UNITY_SINGLE_PASS_STEREO`、
`UNITY_STEREO_INSTANCING_ENABLED`、`UNITY_STEREO_MULTIVIEW_ENABLED` の有効状態を色にし、VRChat 内で確認できる。
この方法は SDK が単にそのバリアントを生成したかではなく、その描画で選ばれたシェーダーバリアントを確認するためのもの。
マクロの色表示や深度表示だけで終了せず、左右フラグと欠けた辺の比較まで行って原因を確定する。

## 7. 修正の適用と検証状況

- `YubiCamera.shader` と `YubiCamera_OpenLit.cginc` の両方で `ComputeNonStereoScreenPos` を使用。
- 共通の `getDepth()` に `UnityStereoTransformScreenSpaceTex` を集約。
- `adjustStereo()` を削除し、横方向も縦方向も眼内 UV で走査・比較。
- 深度宣言を両方とも `UNITY_DECLARE_DEPTH_TEXTURE` へ変更。
- `git diff --check` は通過。

元プロジェクトの設定や Library を変えずに確認するため、TEMP 配下に検証用の最小プロジェクトを作成し、
インストール済みの Unity 2019.4.31f1 を batchmode / Direct3D 11 で起動した。
しかしライセンス検証で終了し、シェーダーのインポート・コンパイル処理まで到達しなかった。
Unity が終了コード 0 を返していても、コンパイル成功とは扱っていない。
ライセンスファイルの変更・再認証は行っていない。
通常版・OpenLit Opaque / Transparent の Unity コンパイルおよび VRChat 実機比較は引き続き必要。
