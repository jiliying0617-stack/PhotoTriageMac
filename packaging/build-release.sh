#!/bin/bash
set -euo pipefail

# Usage: bash packaging/build-release.sh [--desktop]
# Set SKIP_TESTS=1 only when packaging on a machine without a GUI test host.
# No overwrite: each App directory gets a build timestamp; existing DMGs must be renamed explicitly.
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
VERSION="$(tr -d '\n\r' < packaging/VERSION)"
BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"
BUILD_ROOT="$(mktemp -d /tmp/photo-triage-release-build.XXXXXX)"
RELEASE_DIR="$PROJECT_ROOT/dist/正式发布-v$VERSION-$BUILD_NUMBER"
DMG_PATH="$PROJECT_ROOT/dist/筛图神器-v$VERSION-macOS-universal.dmg"
[[ ! -e "$DMG_PATH" ]] || { echo "已有安装包：${DMG_PATH}；请先保留或重命名旧包。"; exit 1; }
if [[ "${1:-}" == "--desktop" ]]; then
    DESKTOP_DMG="$HOME/Desktop/筛图神器-v$VERSION-macOS-universal.dmg"
    [[ ! -e "$DESKTOP_DMG" ]] || { echo "桌面已有同版本安装包，请先重命名保留。"; exit 1; }
fi

if [[ "${SKIP_TESTS:-0}" == "1" ]]; then
    echo "跳过测试（SKIP_TESTS=1）"
else
    # AppKit image-host and timer tests share the main actor. Run the full
    # release gate serially so concurrent decoding cannot starve their waits.
    swift test --no-parallel
fi
swift build -c release --arch arm64 --scratch-path "$BUILD_ROOT/arm64"
swift build -c release --arch x86_64 --scratch-path "$BUILD_ROOT/x86_64"

mkdir -p "$RELEASE_DIR/筛图神器.app/Contents/MacOS" "$RELEASE_DIR/筛图神器.app/Contents/Resources"
APP_PATH="$RELEASE_DIR/筛图神器.app"
cp packaging/Info.plist "$APP_PATH/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_PATH/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"
cp packaging/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
/usr/bin/lipo -create "$BUILD_ROOT/arm64/arm64-apple-macosx/release/PhotoTriageMac" "$BUILD_ROOT/x86_64/x86_64-apple-macosx/release/PhotoTriageMac" -output "$APP_PATH/Contents/MacOS/PhotoTriageMac"
/usr/bin/lipo "$APP_PATH/Contents/MacOS/PhotoTriageMac" -verify_arch arm64 x86_64
/usr/bin/codesign --force --sign - "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
/usr/bin/plutil -lint "$APP_PATH/Contents/Info.plist"

cp packaging/使用说明.txt packaging/打不开时运行.command "$RELEASE_DIR/"
cp packaging/CHANGELOG.md "$RELEASE_DIR/更新说明.md"
chmod +x "$RELEASE_DIR/打不开时运行.command"
/bin/zsh -n "$RELEASE_DIR/打不开时运行.command"
ln -s /Applications "$RELEASE_DIR/Applications"
(cd "$RELEASE_DIR" && /usr/bin/shasum -a 256 "筛图神器.app/Contents/MacOS/PhotoTriageMac") > "$RELEASE_DIR/应用校验.txt"
SOURCE_SNAPSHOT="$(mktemp -d /tmp/photo-triage-release-source.XXXXXX)"
ditto Sources "$SOURCE_SNAPSHOT/Sources"
ditto Tests "$SOURCE_SNAPSHOT/Tests"
ditto packaging "$SOURCE_SNAPSHOT/packaging"
cp Package.swift README.md "$SOURCE_SNAPSHOT/"
/usr/bin/ditto -c -k "$SOURCE_SNAPSHOT" "$PROJECT_ROOT/dist/源码-v$VERSION-$BUILD_NUMBER.zip"
/usr/bin/hdiutil create -volname "筛图神器 $VERSION" -srcfolder "$RELEASE_DIR" -ov -format UDZO "$DMG_PATH"
/usr/bin/hdiutil verify "$DMG_PATH"
(cd "$PROJECT_ROOT/dist" && /usr/bin/shasum -a 256 "$(basename "$DMG_PATH")") > "$DMG_PATH.sha256"
if [[ "${1:-}" == "--desktop" ]]; then
    cp "$DMG_PATH" "$DESKTOP_DMG"
    /usr/bin/cmp "$DMG_PATH" "$DESKTOP_DMG"
fi
echo "已生成正式包：$DMG_PATH"
echo "App：$APP_PATH"
