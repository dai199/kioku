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
   ├─ 翻訳  TranslationSession → TranslationEngine(protocol) → GeminiEngine
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

## 進め方

- **コミットはユーザーの承認後**。ビルド（と必要ならテスト）を通し、動作を確かめてもらってから
- コミットメッセージは日本語。1行目は「主題: 要約」、本文は変更点と**なぜそうしたか**を箇条書きで
- SPECのバックログを消化したら、SPEC側の番号に ✅ と到達範囲を書き戻す（実装だけ進めない）
