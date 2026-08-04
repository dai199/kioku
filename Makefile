DERIVED := .build
APP := $(DERIVED)/Build/Products/Debug/Kioku.app

.PHONY: generate build run test clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project Kioku.xcodeproj -scheme Kioku -configuration Debug \
		-derivedDataPath $(DERIVED) build

test: generate
	xcodebuild -project Kioku.xcodeproj -scheme Kioku -configuration Debug \
		-derivedDataPath $(DERIVED) test

run: build
	@pkill -x Kioku || true
	open $(APP)

clean:
	rm -rf $(DERIVED) Kioku.xcodeproj
