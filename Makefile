APP_NAME = 弹来弹去
BUNDLE = build/$(APP_NAME).app
# Universal 二进制（Intel + Apple Silicon）
BINARY = .build/apple/Products/Release/DanmakuOverlay
VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
DMG = build/DanLaiDanQu-v$(VERSION).dmg

.PHONY: build app run dmg clean

build:
	swift build -c release --arch arm64 --arch x86_64

app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(BINARY)" "$(BUNDLE)/Contents/MacOS/DanmakuOverlay"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	codesign --force --sign - "$(BUNDLE)"
	@echo "Built $(BUNDLE)"

run: app
	open "$(BUNDLE)"

# 生成可分发的 DMG（经典拖拽安装窗口布局）
dmg: app
	bash scripts/package_dmg.sh

clean:
	rm -rf .build build
