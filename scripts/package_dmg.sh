#!/bin/bash
# 生成经典拖拽安装体验的 DMG：
# 可写镜像 → Finder 脚本布置窗口与图标位置（写入 .DS_Store）→ 压缩为只读发行版
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="弹来弹去"
BUNDLE="build/${APP_NAME}.app"
STAGING="build/dmg-staging"
TMP_DMG="build/tmp-rw.dmg"
FINAL_DMG="build/${APP_NAME}.dmg"
VOL="/Volumes/${APP_NAME}"

[ -d "$BUNDLE" ] || { echo "先运行 make app 生成 ${BUNDLE}"; exit 1; }

rm -rf "$STAGING" "$TMP_DMG" "$FINAL_DMG"
mkdir -p "$STAGING"
cp -R "$BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# 残留同名卷先卸载，避免挂载点冲突
hdiutil detach "$VOL" >/dev/null 2>&1 || true

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDRW "$TMP_DMG" >/dev/null
hdiutil attach "$TMP_DMG" >/dev/null

# Finder 布置窗口：图标视图、无工具栏、112pt 大图标、App 在左 Applications 在右
osascript <<EOF
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 200, 840, 560}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set position of item "${APP_NAME}.app" of container window to {160, 150}
    set position of item "Applications" of container window to {480, 150}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

sync
hdiutil detach "$VOL" >/dev/null
hdiutil convert "$TMP_DMG" -format UDZO -o "$FINAL_DMG" >/dev/null
rm -f "$TMP_DMG"
rm -rf "$STAGING"
echo "Built $FINAL_DMG"
