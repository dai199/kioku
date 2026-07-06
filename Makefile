DERIVED := .build
APP := $(DERIVED)/Build/Products/Debug/Kioku.app

.PHONY: generate build run clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project Kioku.xcodeproj -scheme Kioku -configuration Debug \
		-derivedDataPath $(DERIVED) build

run: build
	@pkill -x Kioku || true
	open $(APP)

clean:
	rm -rf $(DERIVED) Kioku.xcodeproj
