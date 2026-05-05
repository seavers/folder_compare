#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FolderCompare"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST_PATH="$CONTENTS_DIR/Info.plist"

cd "$ROOT_DIR"

VERSION_COMMIT_ID="$(git rev-parse --short=7 HEAD)"
BUILD_DATE="$(date +%F)"
APP_VERSION="1.0.0.$VERSION_COMMIT_ID"

# 1. 构建 release 可执行文件，确保打包时使用最新代码。
swift build -c release

# 2. 定位二进制输出目录，并准备标准 macOS app bundle 目录结构。
BIN_DIR="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# 3. 拷贝可执行文件与 Info.plist，生成可双击启动的应用包。
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST_PATH"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

# 4. 在打包阶段写入当前版本号和构建日期，确保关于面板展示的是本次构建信息。
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$INFO_PLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION_COMMIT_ID" "$INFO_PLIST_PATH"
if /usr/libexec/PlistBuddy -c "Print :FolderCompareBuildDate" "$INFO_PLIST_PATH" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :FolderCompareBuildDate $BUILD_DATE" "$INFO_PLIST_PATH"
else
    /usr/libexec/PlistBuddy -c "Add :FolderCompareBuildDate string $BUILD_DATE" "$INFO_PLIST_PATH"
fi

chmod +x "$MACOS_DIR/$APP_NAME"

echo "应用已生成: $APP_DIR"
