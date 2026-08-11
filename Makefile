DERIVED := .build
APP := $(DERIVED)/Build/Products/Debug/Kioku.app

# 署名の指定。既定はad-hoc署名（project.yml側）で、誰の環境でもビルドが通る。
# 自分のApple Developer Team IDを渡すと、その証明書で署名する:
#     make build TEAM=XXXXXXXXXX
# 署名が毎回同じになるぶん、アクセシビリティ権限が再ビルド後も保持される。
# Team IDは Xcode > Settings > Accounts、または developer.apple.com で確認できる。
TEAM ?=
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
