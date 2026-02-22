#!/bin/bash

# ipaDown 仅 macOS 自动打包导出脚本
# 仅编译并导出 macOS 的 .app (压缩为 .zip) 或 .dmg

# 1. 配置路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build_output"
MAC_ARCHIVE="$BUILD_DIR/Mac.xcarchive"
WORKSPACE="$PROJECT_DIR/ipaDown-for-Apple.xcodeproj/project.xcworkspace"
SCHEME="ipaDown"

# 创建输出目录
mkdir -p "$BUILD_DIR"

echo "=========================================="
echo "     ipaDown macOS 自动打包脚本 (.dmg)     "
echo "=========================================="

# 2. 编译 macOS 版本
echo ">>> 开始编译 macOS 版本..."
cd "$PROJECT_DIR"
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
else
    echo "❌ 找不到 macOS 应用: $MAC_APP_PATH"
fi

echo "=========================================="
echo "🎉 macOS 打包流程结束！"
echo "产物: $BUILD_DIR/ipaDown_${APP_VERSION}.dmg (或 .zip)"
echo "=========================================="
