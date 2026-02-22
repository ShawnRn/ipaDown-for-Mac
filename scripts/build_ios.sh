#!/bin/bash

# ipaDown 仅 iOS 自动打包导出脚本
# 仅编译并导出 iOS 的 .ipa (通过 Payload 方式)

# 1. 配置路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build_output"
IOS_ARCHIVE="$BUILD_DIR/iOS.xcarchive"
WORKSPACE="$PROJECT_DIR/ipaDown-for-Apple.xcodeproj/project.xcworkspace"
SCHEME="ipaDown"

# 创建输出目录
mkdir -p "$BUILD_DIR"

echo "=========================================="
echo "      ipaDown iOS 自动打包脚本 (.ipa)      "
echo "=========================================="

# 2. 编译 iOS 版本
echo ">>> 开始编译 iOS 版本..."
cd "$PROJECT_DIR"
xcodebuild clean archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -archivePath "$IOS_ARCHIVE" \
    | xcpretty || xcodebuild clean archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -archivePath "$IOS_ARCHIVE"

if [ ! -d "$IOS_ARCHIVE" ]; then
    echo "❌ iOS 构建失败！"
    exit 1
fi

echo "✅ iOS Archive 构建成功！"

# 3. 提取 iOS .ipa 构建产物
echo ">>> 提取 iOS .app 并打包为 .ipa..."
IOS_APP_PATH="$IOS_ARCHIVE/Products/Applications/ipaDown.app"
if [ -d "$IOS_APP_PATH" ]; then
    cd "$BUILD_DIR"
    mkdir -p "Payload"
    cp -R "$IOS_APP_PATH" "Payload/"
    APP_VERSION=$(defaults read "$(pwd)/Payload/ipaDown.app/Info.plist" CFBundleShortVersionString)

    zip -qr "ipaDown_${APP_VERSION}_iOS.ipa" "Payload"
    rm -rf "Payload"
    echo "✅ iOS 应用打包完成: $BUILD_DIR/ipaDown_${APP_VERSION}_iOS.ipa"
else
    echo "❌ 找不到 iOS 应用: $IOS_APP_PATH"
fi

echo "=========================================="
echo "🎉 iOS 打包流程结束！"
echo "产物: $BUILD_DIR/ipaDown_${APP_VERSION}_iOS.ipa"
echo "=========================================="
