#!/usr/bin/env bash
# 在 macOS 上编出未签名的 Folia.ipa（给全能签等签名工具用）：XcodeGen 生成工程，xcodebuild 关掉签名编译，
# 再把 Folia.app 装进 Payload/ 打成 zip。用法：packaging/ios/build-ipa.sh [输出目录]
# 可选环境变量：FOLIA_SERVER_URL（写进 App 的默认服务端地址）、FOLIA_IOS_BUILD_NUMBER（构建号，默认 1）。
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$IOS_DIR/../.." && pwd)"
OUT_DIR="${1:-$REPO_DIR/release/ios}"
BUILD_DIR="$IOS_DIR/build"

VERSION="$(node -p "require('$REPO_DIR/package.json').version" 2>/dev/null || sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$REPO_DIR/package.json" | head -n 1)"
BUILD_NUMBER="${FOLIA_IOS_BUILD_NUMBER:-1}"
SERVER_URL="${FOLIA_SERVER_URL:-}"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "[ios] 缺少 xcodegen，先运行 brew install xcodegen" >&2
    exit 1
fi

echo "[ios] 版本 $VERSION ($BUILD_NUMBER)，默认服务端：${SERVER_URL:-（不预置，首次打开时填写）}"

cd "$IOS_DIR"
xcodegen generate --spec project.yml

rm -rf "$BUILD_DIR"
xcodebuild \
    -project Folia.xcodeproj \
    -scheme Folia \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    FOLIA_DEFAULT_SERVER_URL="$SERVER_URL" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release-iphoneos/Folia.app"
if [ ! -d "$APP_PATH" ]; then
    echo "[ios] 没有找到编出来的 $APP_PATH" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR/Payload" "$OUT_DIR"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
IPA_PATH="$OUT_DIR/Folia-$VERSION-unsigned.ipa"
rm -f "$IPA_PATH"
(cd "$BUILD_DIR" && zip -qry "$IPA_PATH" Payload)

echo "[ios] 已生成 $IPA_PATH"
