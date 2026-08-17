# Kioku

macOS常駐の翻訳アプリ兼学習アプリ。どのアプリでもテキストを選択すると翻訳でき、
その履歴が学習素材として貯まり、週次でAIが「覚える価値の高い表現」をSRSカードとして提案する。

- **[SPEC.md](SPEC.md)** — 要件・データモデル・ロードマップ。**何を作るかはここが正**
- **[DESIGN.md](DESIGN.md)** — デザイン言語。**画面を触るときは必ず従う**

この2つに書いてあることはここで繰り返さない。迷ったら先にそちらを読む。

## コマンド

```sh
make build   # xcodegen generate → xcodebuild build
make test    # ユニットテスト（Tests/KiokuTests）
make run     # ビルドして起動（起動中のKiokuはpkillで落とす）
make clean   # .build と Kioku.xcodeproj を捨てる

make eval        # 翻訳エンジンの品質を測る（LIMIT=20 で件数を指定）
make screenshots # サイト用のスクリーンショットを撮る（画面を専有する）
```

`Kioku.xcodeproj` は `project.yml` から生成される**成果物**でgit管理外。
ターゲット・ビルド設定・依存の変更は必ず `project.yml` を編集する。
ソースファイルを追加したら `make build`（内部で `xcodegen generate` が走る）。

## 構成

```
KiokuApp (MenuBarExtra, LSUIElement)
└─ AppCoordinator ─── 権限・監視・UIを束ねる中枢。配線はここに集約する
   ├─ 検知  SelectionMonitor → SelectionProbe(AX API) → SelectionFilter
   ├─ 提示  FloatingIconController / PopupController（nonactivating NSPanel）
   ├─ 翻訳  PopupTranslationSession → TranslationEngine(protocol) → GeminiEngine
   │        + TranslationCache / TextReplacer
   ├─ 永続  DatabaseManager（GRDB/SQLite）
   ├─ 学習  ReportManager → WeeklyAnalyzer / ReviewScheduler / CardContent
   └─ 画面  MainWindow（復習・履歴・レポート）+ SettingsWindow
```

## この土台で守っていること

- **翻訳エンジンは `TranslationEngine` 越しに使う**。`GeminiEngine` を直に参照しない
  （Apple Translationやオンデバイスへの差し替え口）。プロンプトを変えたら
  そのエンジンの `promptVersion` を必ず上げる — 選好シグナルと突き合わせて効果を追うため。
  版はエンジン名で修飾する（`gemini/…`）。キャッシュキーに入るので、
  衝突するとエンジンを切り替えても前のエンジンの訳が返る
- **エンジンを足すときは `capabilities` を必ず考える**。Apple Translationのように
  方向指定も再生成もできないエンジンがある。画面は能力を見て操作を出し分ける
  （できない操作を出して黙って無視されるのが最悪）
- **ポップアップはフォーカスを奪わない**（nonactivating）。日→英の本文置換が成り立つ前提条件。
  クリックは `Button` で実装する（`onTapGesture` は非キーウィンドウで取りこぼす）
- **DBスキーマの変更はマイグレーション追加のみ**。既存の `registerMigration` は書き換えない
- **学習データを見る画面はメインウィンドウに集約する**。新しいウィンドウを増やさない
  （設定だけは⌘,の慣習で独立）
- **ユーザー向け文言・コード内コメントは日本語**
- **SwiftUIを通らないユーザー向け文言は `String(localized:)` で書く**。
  `Text("覚える")` などSwiftUIのリテラルは `LocalizedStringKey` として扱われるので
  そのままでよい。対象になるのは素の `String` を返すところ——
  エラーの `errorDescription`、通知の本文、`TranslationProvider.detail` など。
  UIの多言語化は未着手（SPEC §10）だが、**新しく足す文言だけ先に対応させておけば
  未対応分が増え続けるのは止まる**。既存分の切り出しは着手時にまとめて行う

## テスト

`Tests/KiokuTests` は純粋ロジックとDB層をカバーする。
AX APIとネットワークは未カバー（外部環境に依存するため）。
ロジックを足すときは、テストできる形（副作用のない型・関数）に切り出してから書く。

**DB層のテストは必ずインメモリDBで書く**。`DatabaseManager(dbQueue: DatabaseQueue())` が
その口で、実DB（アプリサポート配下）には絶対に触れない。マイグレーションを足したら、
空DBからの適用とバックフィルの結果を `DatabaseMigrationTests` に足す
（ここは壊れると実データが失われる唯一の層）。

テストはアプリをテストホストとして起動する構成なので、実行中に実DBが読み取り専用で開かれる。

`#expect` の中に `try` は書けない。値を先に取り出してから比較する。

## AXの実装はアプリごとに違う（実測 2026-08-12）

**選択範囲の画面座標は、取れるアプリと取れないアプリがある。**

| アプリ | `kAXBoundsForRange` |
|---|---|
| テキストエディット | ○ 正しく返る |
| Google Chrome | ✗ 対応を申告しつつ固定値（`0,956 0x0`）を返す |
| Slack（Electron） | ✗ 同上 |

Chromium/Electron系は**「非対応」ではなく「成功を返しつつ中身が無い」**ので、
戻り値の検査を緩めても救えない。1文字分の範囲で問い合わせる回避策も試したが駄目だった。
要素全体の矩形（position＋size）は取れるが、Chromeではページ全体（1716x962）で粗すぎる。

したがって**これらのアプリでは選択位置の取得は不可能**で、
ドラッグの開始点と終了点からの推測が上限。`SelectionEvent.anchor` がその優先順位を持つ。

**ブラウザ内で正確な選択座標を取りたければ、ブラウザ拡張として実装するしかない。**
拡張ならページの内側でDOMの `getClientRects()` を使え、行ごとの矩形が得られる。
外部アプリがAXで問い合わせる構造では、この精度は原理的に出せない。

未着手の案: AXが効くアプリに限り、外接矩形ではなく**選択1行目**の矩形を使えば、
複数行選択でもアイコンが選択の始まりに出せる（`kAXLineForIndex` →
`kAXRangeForLine` → `kAXBoundsForRange`）。効果はAXが効くアプリの長い選択に限られる。

切り分けの記録は `os.Logger` の debug レベルに残してある:

```sh
/usr/bin/log show --last 30m --predicate 'subsystem == "com.daikitagami.kioku"' --info --debug | grep -E "アイコン表示|選択矩形"
```

## 署名（アクセシビリティ権限が黙って外れる罠）

**`xcodebuild` を直接叩かないこと。必ず `make` を経由する。**

macOSはアクセシビリティ権限を**コード署名に紐づけて**記憶する。既定は ad-hoc 署名なので、
`make` を通さずにビルドするとアプリが ad-hoc で上書きされ、**設定画面ではオンに見えたまま
権限が失効する**（`AXIsProcessTrusted()` が false になり、メニューバーが⚠️になる）。
原因が署名だと気づきにくい。

`make` は `.team`（git管理外）に書いたTeam IDで署名するので、経由すれば署名が安定する。
`.team` が無い環境では ad-hoc になり、誰でもビルドは通る。

## 動作確認

**変更を目視で確かめる前に必ずアプリを再起動する**（`make run`、または `pkill -x Kioku` → `open`）。
`make build` はバイナリを差し替えるだけで、起動中のプロセスは古いまま動き続ける。
メニューバー常駐なので何日も起動しっぱなしになりやすく、
「実装したのに出てこない」「動きがおかしい」の大半はこれが原因。

翻訳パスは `os.Logger`（subsystem `com.daikitagami.kioku`）に記録している。
挙動が怪しいときはまずログを見る:

```sh
log show --last 10m --predicate 'subsystem == "com.daikitagami.kioku"' --info --debug
```

## スクリーンショット（`make screenshots`）

実アプリを操作して撮る。オフスクリーン描画では出せない本物の枠と質感が要るため。
`sites/images/` に8枚（レポート・復習・履歴・ポップアップ × ライト/ダーク）が出る。

`-KiokuDemo` で起動すると、**実DBには一切触れず**インメモリの見本データと定型の訳を使う。
撮った画像に自分の翻訳履歴が写らないし、APIキーもネットワークも要らない。
見た目は `-KiokuAppearance light|dark` で自プロセスだけ切り替える（システム設定は変えない）。

ポップアップは他アプリのテキストを選んで出すものなので、テキストエディットを相手にする
（選択範囲の画面座標をAXで正しく返す数少ないアプリ。上の実測表を参照）。
撮影の間だけテキストエディットの表示設定を揃え、終わったら元に戻す。

実行中は画面を専有するので触らないこと。ハマりどころが多いので、直す前にここを読む:

- **合成イベントのドラッグでは選択できない**。`press(thenDragTo:)` は途中の移動を出さず、
  テキスト側が範囲選択と認識しない。行をまるごと選ぶトリプルクリックを使っている
- **日本語を `typeText` で打たない**。入力ソースの切り替え許可を毎回聞かれる。
  見本は保存済みのファイルを開いて渡す（書き換えないので保存確認も出ない）
- **フローティングアイコンとポップアップはAXツリーに出ない**。`CGWindowList` で見つける
- **ウィンドウは前回の位置に復元される**（別ディスプレイのこともある）。定位置へ移してから撮る
- **`XCUIScreenshot` の画像サイズはピクセル**。切り出しの倍率は画面の実寸から出す
- 常駐して他アプリのテキスト欄にボタンを重ねるツールは「ほかを隠す」では消えない。
  撮影範囲に想定外のアプリが重なっていたらテストが止まるので、終了させて撮り直す

## 進め方

- **コミットはユーザーの承認後**。ビルド（と必要ならテスト）を通し、動作を確かめてもらってから
- コミットメッセージは日本語。1行目は「主題: 要約」、本文は変更点と**なぜそうしたか**を箇条書きで
- SPECのバックログを消化したら、SPEC側の番号に ✅ と到達範囲を書き戻す（実装だけ進めない）
