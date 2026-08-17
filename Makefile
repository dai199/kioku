DERIVED := .build
APP := $(DERIVED)/Build/Products/Debug/Kioku.app

# 署名の指定。既定はad-hoc署名（project.yml側）で、誰の環境でもビルドが通る。
#     make build TEAM=XXXXXXXXXX     … その証明書で署名する
#     echo XXXXXXXXXX > .team        … 以後は省略できる（git管理外）
#
# .team を用意するのは、渡し忘れると ad-hoc 署名でアプリが上書きされ、
# **アクセシビリティ権限が黙って外れる**ため。macOSは権限をコード署名に
# 紐づけて記憶するので、署名が変わると設定画面ではオンに見えたまま失効する。
# 気づきにくいので、毎回指定させるのではなく既定値を持たせる。
TEAM ?= $(shell cat .team 2>/dev/null)
ifneq ($(TEAM),)
SIGN := DEVELOPMENT_TEAM=$(TEAM) CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development"
else
SIGN :=
endif

XCODEBUILD := xcodebuild -project Kioku.xcodeproj -scheme Kioku -configuration Debug \
	-derivedDataPath $(DERIVED)

.PHONY: generate build run test eval screenshots clean

generate:
	xcodegen generate

build: generate
	$(XCODEBUILD) $(SIGN) build

# 計測（eval）と撮影（UIテスト）は外す。前者は実APIを叩き、後者は画面を専有するので、
# 普段のテストに混ぜない
test: generate
	$(XCODEBUILD) $(SIGN) -skip-testing:KiokuTests/EngineEvaluation \
		-skip-testing:KiokuUITests test

# エンジン比較の計測。実DBの原文と実APIを使うので、通常のテストとは分けてある。
# 結果は eval-results/ に書き出す（実データを含むためgit管理外）。
#     make eval LIMIT=40   … 原文の件数を変える
# 有効化は -only-testing / -skip-testing で行う。環境変数は
# xcodebuildがテストプロセスへ渡さないため使えない（TEST_RUNNER_接頭辞でも届かない）。
LIMIT ?= 20
eval: generate
	@echo $(LIMIT) > .eval-limit
	$(XCODEBUILD) $(SIGN) -only-testing:KiokuTests/EngineEvaluation test

# サイト用のスクリーンショットを実アプリから撮る。
# 画面を専有するので（メニューバーをクリックし、ウィンドウを前面に出し、
# テキストエディットを操作する）、実行中は触らないこと。
# 開いているテキストエディットの書類は閉じられるので、先に保存しておくこと。
# 終わったら通常モードで起動し直す。
# ランナーはサンドボックス内なのでリポジトリに直接書けない。自分の領域に出させて取り出す
SHOTS := $(HOME)/Library/Containers/com.daikitagami.kioku.uitests.xctrunner/Data/tmp/kioku-screenshots
screenshots: build
	@rm -rf "$(SHOTS)"
	Scripts/capture-screenshots.sh $(XCODEBUILD) $(SIGN) -only-testing:KiokuUITests test
	@mkdir -p sites/images
	@cp "$(SHOTS)"/*.png sites/images/ && echo "→ sites/images/ に取り出しました"
	@ls -1 sites/images/
	@pkill -x Kioku || true
	@open $(APP)

run: build
	@pkill -x Kioku || true
	open $(APP)

clean:
	rm -rf $(DERIVED) Kioku.xcodeproj
