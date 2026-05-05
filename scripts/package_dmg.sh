#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FolderCompare"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
STAGING_DIR="$DIST_DIR/.dmg_staging"
VOLUME_NAME="$APP_NAME"

cd "$ROOT_DIR"

# 1. 先复用现有 app 打包流程，确保 dmg 总是基于最新的应用产物。
bash "$ROOT_DIR/scripts/package_app.sh"

if [[ ! -d "$APP_DIR" ]]; then
    echo "缺少应用产物: $APP_DIR"
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
rm -f "$DMG_PATH"

# 2. 组装 dmg 内容目录，保留应用本体，并添加 Applications 快捷方式方便拖拽安装。
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# 3. 生成压缩 dmg，输出到 dist 目录，文件名带上版本号便于分发和追踪。
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "DMG 已生成: $DMG_PATH"
