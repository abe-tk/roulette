# roulette

macOS 向けの 3D ルーレットアプリ。  
名前を最大 500 件ホイールに並べ、約 14 秒の演出と効果音つきで当選者を 1 名選ぶ。  

## 動作環境

| 項目 | 内容 |
| --- | --- |
| OS | macOS 12.0 以上 |
| Flutter | 3.47.5（FVM で固定、`.fvmrc`） |
| 3D 描画 | [flutter_scene](https://pub.dev/packages/flutter_scene) 0.23.0（Flutter GPU / Impeller） |
| 効果音 | [flutter_scene_soloud](https://pub.dev/packages/flutter_scene_soloud)（SoLoud） |

Flutter GPU は `macos/Runner/Info.plist` の `FLTEnableFlutterGPU` で有効にしている。  

## 起動

```bash
fvm install
cp assets/nicknames.example.txt assets/nicknames.txt
fvm flutter pub get
fvm flutter run -d macos
```

VS Code では `.vscode/launch.json` の `roulette (debug)` / `roulette (profile)` / `roulette (release)` から起動できる。  

## 操作

| キー | 動作 |
| --- | --- |
| Space / Enter | スピンを開始する（スピン中は無効） |

## 名前の登録

`assets/nicknames.txt` に 1 行 1 名で書く。  
前後の空白は除かれ、空行は読み飛ばす。  
0 件または 500 件を超えると起動時にエラーになる。  

`assets/nicknames.txt` は Git の管理対象外にしている。  
書式の見本として、ダミーの名前 500 件を `assets/nicknames.example.txt` に置いている。  

起動中に名前を差し替えるときは、`assets/nicknames.txt` を上書きしてから `flutter run` の端末で `R`（ホットリスタート）を押す。  

## 抽選と演出

当選者はスピン開始時に `Random.secure()` で先に決め、その区画でポインタが止まる回転を組み立てる（`lib/roulette/spin_plan.dart`）。  
区画内の停止位置は区画幅の ±35% の範囲でずらし、中央ちょうどには止めない。  

演出は次の段階で進む。  

| 段階 | 時間の目安 | 内容 |
| --- | --- | --- |
| 溜め（windup） | 0.9 秒 | ホイールを少し逆回しする |
| 高速回転（rush） | 約 3 秒 | 最高速で回る |
| 減速（slowdown） | 約 7 秒 | 徐々に遅くなり、カメラが寄る |
| 粘り（creep） | 2.8 秒 | 止まりかけのまま当選区画まで進む |
| 当選（celebrate） | 次のスピンまで | 当選者を表示し、花火を約 12 秒、紙吹雪を約 7 秒出す |

## 効果音

音源は `assets/sounds/` に置く。  
同梱のファイルは配線確認用の仮の合成音で、本番の素材で同じファイル名のまま上書きする。  

| ファイル | 鳴るタイミング |
| --- | --- |
| `tick.wav` | ポインタが区画をまたいだとき（高速時は 40ms 間隔に間引く） |
| `drumroll_loop.wav` | 高速回転〜減速中にループ再生し、音量とピッチを回転速度に合わせる |
| `heartbeat.wav` | 粘り中、電飾の鼓動（1.2Hz）に合わせて 1 拍ずつ |
| `windup.wav` | 溜めの開始時 |
| `fanfare.wav` | 当選時 |
| `cheer.wav` | 当選時 |
| `firework.wav` | 花火を打ち上げるたび |

wav 以外（mp3・ogg など）を使う場合は、`lib/roulette/stage_audio.dart` の `_Sound` のファイル名も合わせる。  
見つからない音源は警告ログを出して鳴らさない。  

音量は `lib/roulette/stage_audio.dart` の `SoundLevels` で音ごとに調整する。  
`SoundLevels.master` は全体の音量で、1.0 が素材そのままの大きさ。  

素材を選ぶときは、クレジット表記の要否と再配布の可否を配布元の規約で確認する。  
再配布を禁止している素材は、公開リポジトリにコミットしない。  

## ソース構成

| パス | 役割 |
| --- | --- |
| `lib/main.dart` | アプリのルート |
| `lib/nickname/nickname_master.dart` | ニックネームマスタの読み込みと検証 |
| `lib/roulette/roulette_page.dart` | 画面、キー操作、名前と当選者の表示 |
| `lib/roulette/roulette_stage.dart` | 3D シーン、演出の段階、照明・カメラ・パーティクルの制御 |
| `lib/roulette/spin_plan.dart` | 当選者の決定と回転角の計算 |
| `lib/roulette/stage_effects.dart` | 火花・花火・紙吹雪などのパーティクル |
| `lib/roulette/stage_audio.dart` | 効果音の再生と音量設定 |
| `lib/roulette/wheel_texture.dart` | ホイール面・背景・光の粒のテクスチャ描画 |

## 開発

```
fvm dart analyze
fvm flutter test
```

Lint は [very_good_analysis](https://pub.dev/packages/very_good_analysis) を使う。  
