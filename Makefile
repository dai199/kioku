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

.PHONY: generate build run test clean

generate:
	xcodegen generate

build: generate
	$(XCODEBUILD) $(SIGN) build

test: generate
	$(XCODEBUILD) $(SIGN) test

run: build
	@pkill -x Kioku || true
	open $(APP)

clean:
	rm -rf $(DERIVED) Kioku.xcodeproj
