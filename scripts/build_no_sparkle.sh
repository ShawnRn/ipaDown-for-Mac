#!/bin/bash

# ipaDown 双端自动打包脚本 (不含 Sparkle 更新)
# 编译并导出 macOS .dmg 及 iOS .ipa，但跳过 appcast.xml 生成

# 1. 配置路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build_output"
MAC_ARCHIVE="$BUILD_DIR/Mac.xcarchive"
IOS_ARCHIVE="$BUILD_DIR/iOS.xcarchive"
WORKSPACE="$PROJECT_DIR/ipaDown-for-Apple.xcodeproj/project.xcworkspace"
SCHEME="ipaDown"

# 创建输出目录
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "=========================================="
echo "    ipaDown 双端自动打包 (不含 Sparkle)    "
echo "=========================================="

# 2. 编译 macOS 版本
echo ">>> 开始编译 macOS 版本..."
xcodebuild clean archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=macOS' \
    -archivePath "$MAC_ARCHIVE" \
    | xcpretty || xcodebuild clean archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=macOS' \
    -archivePath "$MAC_ARCHIVE"

if [ ! -d "$MAC_ARCHIVE" ]; then
    echo "❌ macOS 构建失败！"
    exit 1
fi

echo "✅ macOS Archive 构建成功！"

# 3. 提取 macOS .app 构建产物
echo ">>> 提取 macOS .app..."
MAC_APP_PATH="$MAC_ARCHIVE/Products/Applications/ipaDown.app"
if [ -d "$MAC_APP_PATH" ]; then
    cp -R "$MAC_APP_PATH" "$BUILD_DIR/"
    cd "$BUILD_DIR"
    APP_VERSION=$(defaults read "$(pwd)/ipaDown.app/Contents/Info.plist" CFBundleShortVersionString)

    # 尝试使用 create-dmg
    if command -v create-dmg &> /dev/null; then
        echo ">>> 使用 create-dmg 创建 DMG..."
        rm -f "ipaDown_${APP_VERSION}.dmg"
        create-dmg "ipaDown.app" "$BUILD_DIR"
        
        if [ -f "ipaDown $APP_VERSION.dmg" ]; then
            mv "ipaDown $APP_VERSION.dmg" "ipaDown_${APP_VERSION}.dmg"
        elif [ -f "ipaDown.dmg" ]; then
            mv "ipaDown.dmg" "ipaDown_${APP_VERSION}.dmg"
        else
            mv ipaDown*.dmg "ipaDown_${APP_VERSION}.dmg" 2>/dev/null || true
        fi
        echo "✅ macOS 应用 DMG 制作完成: $BUILD_DIR/ipaDown_${APP_VERSION}.dmg"
    else
        echo "⚠️ 未找到 create-dmg CLI，降级使用 zip 压缩..."
        zip -r "ipaDown_${APP_VERSION}_Mac.zip" "ipaDown.app" >/dev/null
        echo "✅ macOS 应用提取完成: $BUILD_DIR/ipaDown_${APP_VERSION}_Mac.zip"
    fi
fi

# 4. 编译 iOS 版本
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

# 5. 提取 iOS .ipa 构建产物
echo ">>> 提取 iOS .app 并打包为 .ipa..."
IOS_APP_PATH="$IOS_ARCHIVE/Products/Applications/ipaDown.app"
if [ -d "$IOS_APP_PATH" ]; then
    cd "$BUILD_DIR"
    mkdir -p "Payload"
    cp -R "$IOS_APP_PATH" "Payload/"
    zip -qr "ipaDown_${APP_VERSION}_iOS.ipa" "Payload"
    rm -rf "Payload"
    echo "✅ iOS 应用打包完成: $BUILD_DIR/ipaDown_${APP_VERSION}_iOS.ipa"
fi

echo "=========================================="
echo "🎉 自动打包流程全部结束 (已跳过 Sparkle)！"
echo "Mac 产物: $BUILD_DIR/ipaDown_${APP_VERSION}.dmg"
echo "iOS 产物: $BUILD_DIR/ipaDown_${APP_VERSION}_iOS.ipa"
echo "=========================================="
