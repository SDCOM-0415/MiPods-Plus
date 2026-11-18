# MiPods-Plus —— 构建与运行
#
# 必须用 Xcode 工具链（Command Line Tools 缺 SwiftUI 宏插件，@State 会编译失败）。

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

SWIFT       := swift
SWIFT_FLAGS ?= -c release --arch arm64 --arch x86_64
APP         := MiPods-Plus.app
PRODUCT     := $(shell $(SWIFT) build $(SWIFT_FLAGS) --show-bin-path)/MiPodsPlus
BUNDLE_ID   ?= com.mipods.plus

.PHONY: all build app test run demo stop clean install

all: app

build:
	$(SWIFT) build $(SWIFT_FLAGS)

test:
	$(SWIFT) test

app: build
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@cp "$(PRODUCT)" "$(APP)/Contents/MacOS/MiPodsPlus"
	@printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '  <key>CFBundleExecutable</key><string>MiPodsPlus</string>' \
	  '  <key>CFBundleIdentifier</key><string>$(BUNDLE_ID)</string>' \
	  '  <key>CFBundleName</key><string>MiPods-Plus</string>' \
	  '  <key>CFBundleDisplayName</key><string>MiPods Plus</string>' \
	  '  <key>CFBundlePackageType</key><string>APPL</string>' \
	  '  <key>CFBundleShortVersionString</key><string>1.0.0</string>' \
	  '  <key>CFBundleVersion</key><string>1</string>' \
	  '  <key>LSMinimumSystemVersion</key><string>12.0</string>' \
	  '  <key>LSUIElement</key><true/>' \
	  '  <key>NSBluetoothAlwaysUsageDescription</key><string>MiPods-Plus 需要蓝牙权限来发现并控制小米/Redmi 耳机。</string>' \
	  '</dict></plist>' > "$(APP)/Contents/Info.plist"
	@codesign --force --deep --sign - "$(APP)" 2>/dev/null || true
	@echo "built $(APP)"

run: app
	@open "$(APP)"

demo: app
	@MIPODS_DEMO=1 "$(APP)/Contents/MacOS/MiPodsPlus"

stop:
	@pkill -f "$(APP)/Contents/MacOS" 2>/dev/null || true
	@echo stopped

clean:
	@rm -rf .build "$(APP)"
	@echo cleaned

install: app
	@rm -rf "/Applications/$(APP)"
	@cp -R "$(APP)" /Applications/
	@echo "installed to /Applications/$(APP)"
