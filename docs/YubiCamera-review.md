# YubiCamera の追加レビュー

調査日: 2026-11-03。対象コミット: `7270306`。
通常版、OpenLit Opaque / Transparent、共通 include、同梱マテリアルを確認した。
調査時点では文書のみを追加。その後の修正適用状況は末尾に記載する。

コードと Unity / OpenLit の一次資料、CPU 上の模擬走査による調査である。
GPU 時間・コンパイル結果・VRChat 実機の追加検証は含まない。
前回の Unity 起動時にライセンス検証で終了したため、Unity Editor のコンパイル済みとは扱わない。
修正後に別途行った Direct3D のオフラインコンパイルとCPU回帰検証については末尾参照。

## 優先順位

| 優先 | 対象 | 判断 | 対応案 |
| --- | --- | --- | --- |
| 高 | OpenLit の LightMode | 指定漏れを確認。ライティング・影への実際の影響は要実機確認 | OpenLit の Pass に ForwardBase を指定 |
| 高 | 強制表示マスク | alpha のみ・非ゼロ判定のため、入力次第で全画面を常時表示 | alpha の仕様を明示し、未設定と通常の画像を検証 |
| 高 | 深度走査 | 最悪257回/fragment。未成立時にも全探索 | 判定済み方向の読み取りを省く |
| 中 | 判定不能な領域 | 探索範囲外でも通常の深度走査を実行 | 眼内座標と Sampling Range で先に不成立を確定 |
| 中 | マスクの UV | マスク自身の Tiling / Offset を参照していない | 独立 UV を渡す、または UI を隠して共有仕様を明示 |
| 中 | Sampling Range の UI | ShaderLab の Range 型ではなく Float + 属性になっている | 正式な Range 型へ変更 |
| 中 | ループと暗黙 LOD | tex2D と動的な分岐・break が混在 | LOD 0 の明示と必要 shader target をセットで検証 |
| 低 | 未使用プロパティ | Before Exposure Limit は処理に反映されない | 削除・非表示、または本来の処理を実装 |

## 1. OpenLit の LightMode が欠けている

該当: `YubiCamera_OpenLit_Opaque.shader:87`、`YubiCamera_OpenLit_Transparent.shader:87` 付近の Pass。

両方に `#pragma multi_compile_fwdbase` と `UNITY_LIGHT_ATTENUATION` があるが、
`Tags { "LightMode" = "ForwardBase" }` がない。
Unity Built-in は LightMode 未指定の Pass を Always 相当として扱う。
シェーダー内に手書きのライティング計算があるだけでは、ForwardBase の扱いにはならない。
[Unity: Pass Tags](https://docs.unity3d.com/2019.4/Documentation/Manual/SL-PassTags.html)

OpenLit 作者のサンプルにも ForwardBase 指定がある。
[OpenLit: OpenToonLit.shader](https://github.com/lilxyzw/OpenLit/blob/main/Assets/OpenLit/OpenToonLit.shader)

メインライト、頂点ライト、影のデータとバリアントの扱いを正すため、まず OpenLit の2つの Pass に追加するのが妥当。
同梱マテリアルでは Receive Shadow / Vertex Light Strength がともに0なので、それらの問題は見えにくい。
影を有効にした Directional Light、頂点ライト、明暗の異なるワールドで比較が必要。
通常の YubiCamera は unlit なので、一律に ForwardBase へ変えない。
ForwardAdd の追加は光源ごとに深度走査を繰り返すおそれがあり、今回の修正としては推奨しない。

## 2. 強制表示マスクの取り扱い

該当: `YubiCamera.cginc:35-36` と各 shader の `_YubiForceVisibleMask`。

### alpha のみを、0かそれ以外で判定している

```hlsl
return tex2D(_YubiForceVisibleMask, uv).a != 0;
```

黒い RGB でも alpha=1 の画像を割り当てると全域で true となり、枠判定をすべて迂回する。
「白黒マスク」を想定して通常の不透明画像を入れた場合にも同じことが起きる。
これは alpha マスクとしては仕様だが、プロパティ名だけでは分かりにくい。
また Bilinear / mipmap 等で alpha がわずかに残った部分も強制表示するので、境界が意図より広がる可能性がある。

未設定時の `"black"` については注意が必要。
Unity 2019.4 の英語資料では alpha=1、日本語資料では alpha=0 と説明が食い違う。
したがって資料だけで「未設定なら必ず全表示になる」とは断定しない。
今回の実機不具合をこれで説明できたとも扱わない。
[Unity 英語版](https://docs.unity3d.com/2019.4/Documentation/Manual/SL-Properties.html)、
[Unity 日本語版](https://docs.unity3d.com/ja/2019.4/Manual/SL-Properties.html)

確認する入力は、新規マテリアルで未設定、RGB黒・alpha=1、RGB黒・alpha=0、alpha に境界のある画像。
修正時は「alpha マスクのまま、明示的な無効状態としきい値を設ける」か「R チャンネルの白黒マスクにする」かを選ぶ。
後者は既存マテリアルの意味が変わるため、自動的な互換修正として行わない。

### マスク固有の Tiling / Offset が効かない

`i.uv` はすでに `_MainTex_ST` を適用済みで、それがそのままマスクへ渡る。
`_YubiForceVisibleMask_ST` は宣言・参照されていない。
そのためマスク側の Inspector の Tiling / Offset を変更しても反映されず、Main Texture 側の変更でマスクも動く。

独立操作が必要なら、未変換の mesh UV からマスク用の UV を計算して渡す。
同じ UV を共有する仕様なら `[NoScaleOffset]` で効かない設定欄を隠し、Main Texture と共有することを明記する。

## 3. 最大の負荷は深度探索

該当: `YubiCamera.cginc:49-68`。

マスクによる迂回がなく、中心深度の条件を通った場合、中心1回 + 横128回 + 縦128回で最大257回の深度読み取りを記述している。
さらにマスク、Main Texture、OpenLit では影等の読み取りがある。
この数はソース上の論理的なサンプル回数で、実際のメモリ転送数やGPU時間ではない。
キャッシュ、コンパイラの変換、GPU の分岐実行、対象の画面占有率によって実負荷は変わる。

四辺が見つかる場合は break できるが、一本でも見つからなければ128回を完走する。
「枠がなくて表示されていない」状態でも、中心が奥の背景であれば重い処理を実行する。
Transparent は ZWrite Off なので、対象メッシュの重なりによる多重実行も計測対象となる。

### 判定済みの探索を省く

段階的な候補:

1. `left && right` になれば横の取得を止め、`up && down` になれば縦の取得を止める。
2. さらに、t が左側にある回は left 未成立のときだけ読むなど、方向ごとに止める。

これらはフラグを false に戻すことがない現在の判定に対して、論理結果を保って省略できる。
ただしGPUでは隣接 fragment の分岐が揃わず、読み取り回数の減少がそのまま速度改善率にはならない。
特に分岐内の暗黙微分の扱いも含めて、後述の LOD と合わせたコンパイル確認が必要。

CPU 模擬走査では、眼内の対象位置を(0.5,0.5)、辺を0.3/0.7付近（±0.01）とし、
実装と同じ t の並び、128回、Sampling Range=0.8で比較した。中心深度は条件成立、マスク・ミラーは無効とした。

| 模擬状態 | 現状 | 軸単位で省略 | 方向単位で省略 | inFrame |
| --- | ---: | ---: | ---: | --- |
| 四辺あり | 27 | 27 | 21 | 全案 true |
| 左辺のみ欠ける | 257 | 142 | 80 | 全案 false |
| 近い深度なし | 257 | 257 | 257 | 全案 false |

表は深度の論理的な読み取り回数。VRChat や GPU のベンチマークではない。
空の状態にはこの省略だけでは効かないことも確認できる。

### 探索前に不成立を確定できる

Sampling Range を r とすると、すべての探索位置は
`[(1-r)/2, (1+r)/2]` の中にある。
対象ピクセルがその範囲より外にあれば、少なくとも左右または上下の一方にサンプルが存在しない。
マスク・ミラーの特例を処理した後で inFrame=false を確定できる。
InFrame モードなら discard、OutFrame モードなら表示を続ける必要があり、単に全モード discard としない。

`r=0` もすべて同じ位置になるため、上下左右を同時には満たせず、探索不要。
同様に `_Distance` が正でない場合も、通常の正の眼深度では囲いを満たさない。
空間的にまとまった領域を省けるので、fragment ごとの細かい分岐より効果が出る可能性がある。
GPU時間は実測が必要。

## 4. サンプル配置と品質

現状の `floor / fmod` は、128点の一様な格子を並べ替えている。
CPUで全128点について、次の並びと完全一致し、重複もないことを確認した。

```text
u = (8 * (i % 16) + floor(i / 16)) / 128
t = u * SamplingRange + (1 - SamplingRange) / 2
```

Sampling Range=0.8では最小0.1、最大0.89375、刻み0.00625。
片眼の幅が2000ピクセルなら約12.5ピクセル間隔となり、それより細い指などは配置次第で取りこぼす。
これは速度だけでなく、指の移動で表示がちらつく要因にもなりうる。

32 / 64 / 128 の品質設定は有効な候補だが、単純な削減は取りこぼしを増やす。
中央からの距離順への変更も、最悪回数を減らすものではなく、辺の位置によって有利不利がある。
現在の並べ替えは早い段階で探索位置を広く分散させているため、昇順へ戻すだけの変更は推奨しない。
整数の bit 演算による配置計算も可能だが、コンパイラがすでに定数式を最適化している可能性と shader target の制約を考えると優先度は低い。

そもそもこの判定は「閉じた輪郭」を保証しない。
関係のない物体が上下左右の同じ行・列にあれば、枠として成立する。連結性の保証はアルゴリズムの変更となる。

## 5. 暗黙 LOD と shader target

Unity 2019.4 の `HLSLSupport.cginc:328` では通常の深度サンプルは `tex2D`。
現在は、ピクセルごとに変わる条件と break のあるループの中で呼ぶ。
暗黙の微分と分岐はコンパイラによってループ展開・コード移動・警告等の要因となりうる。
このコードが必ずコンパイル失敗する、現在のVR症状を引き起こす、とは断定しない。
[Microsoft: tex2D と flow control](https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-tex2d-s-t-ddx-ddy)

深度に LOD 0 を明示する候補:

```hlsl
SAMPLE_DEPTH_TEXTURE_LOD(_CameraDepthTexture, float4(depthUV, 0, 0))
```

Unity のマクロを経由して、ステレオ配列対応を維持する。
現状は3つの shader とも target の明示がないため、tex2Dlod を追加するだけでは不十分。
Unity の既定 target は2.5で明示 LOD を含まない。少なくとも samplelod の要件を宣言する。
OpenLit は uint のパッキングや多くの TEXCOORD、Instanced は配列を利用するので、
PC 向けに target 3.5 などへ要件を明示することも検討する。TEXCOORD10 という番号だけで必ず11本使用するとは判断せず、コンパイル後の使用量を確認する。
[Unity: shader targets](https://docs.unity3d.com/2019.4/Documentation/Manual/SL-ShaderCompileTargets.html)、
[Microsoft: tex2Dlod](https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-tex2dlod)

強制的な `[unroll]` / `[loop]` は、逆にコード量やレジスタ使用を増やす場合もあるため、生成コードを見る前に追加しない。

## 6. Inspector と小さな整理

- 全 shader の Sampling Range は `[Range(0,1)]` + `Float`。正式な ShaderLab 宣言は
  `_SamplingRange("Sampling Range", Range(0,1)) = 0.8`。
  現在も shader 内で clamp しているので描画値は制限されるが、Inspector の型指定として修正するのが妥当。
  [Unity: properties](https://docs.unity3d.com/2019.4/Documentation/Manual/SL-Properties.html)
- OpenLit の `_BeforeExposureLimit` は UI と uniform の宣言だけで、計算に使われない。
  `_AlphaBoostFA` も宣言が残るが ForwardAdd Pass がない。前者は設定しても効果がない UI、後者は整理対象。
- 頂点ライト用 varying と fragment の加算条件には VERTEXLIGHT_ON がなく、頂点側の計算条件にはある。
  ただし `UNITY_INITIALIZE_OUTPUT` で0初期化されるため、未初期化バグではない。
  条件をそろえて不要な varying を減らす候補であり、コンパイラが既に消している可能性もある。
- 通常版では世界座標を3成分渡して fragment で眼深度を計算している。
  必要なのは眼深度1成分なので、頂点側で計算し補間する候補がある。
  OpenLit は照明等にも世界座標を使うため、同じ削減をそのまま適用しない。
- `_Distance` は直線距離でなく視線方向の眼深度。斜めの物体では実距離と異なる。
  radial distance へ変えるなら座標再構成が必要で、既存の判定範囲と負荷が変わるため、まず仕様を明記する。

## 7. ミラー・深度生成に関して維持すべき点

VRChat 専用のミラー判定には `_VRChatMirrorMode` が利用できる。
行列の handedness による現在の判定より意図が明確だが、Unity 上の検証や一般的な鏡との互換性が変わる。
使用範囲を決めてから切り替える。
[VRChat Shader Globals](https://creators.vrchat.com/worlds/udon/vrc-graphics/vrchat-shader-globals/)

ShadowCaster がないことを一律に不具合として直さない。
この shader は中心の深度が自分より奥であることを要求するため、安易に自分を深度へ参加させると動作が変わる。
描画用の ZWrite と、事前に生成するカメラ深度テクスチャへの参加は分けて扱う。
[Unity: Camera depth textures](https://docs.unity3d.com/2019.4/Documentation/Manual/SL-CameraDepthTexture.html)

深度生成のためのライトがシーン全体へ与える負荷も別途計測する。
枠判定そのものと、深度を生成するための追加描画を一緒に計測すると、効果を取り違えやすい。

## 推奨する作業順と計測

1. OpenLit の LightMode、Sampling Range 型、マスク入力と UV の仕様を修正・確認する。
2. 眼内探索範囲の外を省略する処理を追加し、Visible Mode 両方とマスク・ミラーを確認する。
3. LOD 0 / 必要 target / 方向ごとの省略を比較し、結果の一致と実GPU負荷を検証する。
4. 画質設定を追加するなら、細い指・遠い指・左右眼・異なる解像度で品質低下を評価する。

計測は通常版 / OpenLit、Opaque / Transparent、Desktop / PC VR を分け、
同じ視点・描画面積・解像度で「四辺あり」「一辺なし」「枠なし」「強制表示」「YubiCamera無効」を比較する。
平均 FPS だけでなく GPU frame time と該当描画の時間、深度生成、透明メッシュの重なりを記録する。
今回の模擬回数から、実GPUの改善率やミリ秒単位の削減量は推定しない。

## 修正適用後の状態

- OpenLit Opaque / Transparent の Pass に `LightMode=ForwardBase` を追加。
- `isInYubiFrame()` に判定を分離し、探索領域の外・Sampling Range=0・Distance<=0 を先に除外。
  OutFrame / InFrame の切り替えと、マスク・ミラーの特例は呼び出し側で維持。
- 判定済みの方向では深度を読まない。128点の順序と配置は変更していない。
- 深度の LOD 0 を明示し、3つの shader に target 3.5 を指定。
- UV を float4 の xy / zw にまとめ、Main Texture とマスクをそれぞれの ST で変換。
  UV 用の TEXCOORD 本数は増やしていない。
- マスクを Alpha と明記し、`_YubiForceVisibleCutoff` を追加。初期値0は通常の非負alphaについて従来の非ゼロ判定と同じ。
  RGBマスクへの変更や、既存マスクを無効化する既定値の追加は行っていない。
  `"black"` の未設定時alphaに関する資料の不一致は実機確認が必要で、ここで解消済みとは扱わない。
- Sampling Range を正しい Range 型へ変更。
- 効果のなかった Before Exposure Limit のUI・宣言と、使われない AlphaBoostFA の宣言を削除。
- 頂点ライト用 varying / fragment 加算の条件を頂点側の条件と統一。光量上限の clamp は以前の条件で維持。
- OpenLit の暗黙な float4→float3 切り捨てを `.xyz` で明示。
- README に mask alpha / cutoff / 独立UV と眼深度の説明を追加。

マスクは以前 Main Texture の ST を共有していたが、今回から独立している。
以前の位置を保ちたい場合は、マスクの Tiling / Offset に以前の Main Texture と同じ値を設定する。
既定の Tiling=(1,1)、Offset=(0,0) ではこの差は発生しない。
Before Exposure Limit などの古い保存値はマテリアルに残っていても参照されない。マテリアルファイル自体は変更していない。

### 検証

TEMP配下の検証スクリプトで、実ファイルの CGPROGRAM / CGINCLUDE と Unity 2019.4.31f1 の includes を展開し、
Windows の `D3DCompile` を利用して `vs_5_0` / `ps_5_0` のコンパイルを行った。
通常版・OpenLit両版について mono / Double-Wide / Instanced、OpenLit は非圧縮 / 圧縮+頂点ライト / スクリーン影の組み合わせを確認。
計42の頂点・フラグメントプログラムがエラー・警告なしでコンパイル成功。
Unity の自動バリアント生成や ShaderLab インポートを経たテストではない。

また、実ソースから `isInYubiFrame()` と `checkDepth()` を抽出し、深度取得を模擬したCPU検証を実施。
修正前と同じ128点の走査を基準に、ランダムな深度・位置・範囲、探索境界の隣接浮動小数点値、
Sampling Range=0、Distance=0を含む20,000ケースで、結果の一致と読み取りが増えないことを確認した。
Visible Mode / ミラー / 強制表示の組み合わせも論理結果を比較した。
模擬の四辺ありは27→21回、左辺欠けは257→80回となった。

これらはUnity Editor / VRChat実機での表示確認や、GPU時間のベンチマークの代わりにはならない。
Unity Editor のインポートと、VRChatでの左右眼・影・マスク操作・透明表示の比較は引き続き必要。
