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

# 2 & 3. 编译与提取 macOS 版本 (双架构分离)
echo ">>> 开始编译 macOS 版本..."
cd "$PROJECT_DIR"
for TARGET_ARCH in "arm64" "x86_64"; do
    echo "=================================================="
    echo ">>> 正在编译 macOS 架构: ${TARGET_ARCH} ..."
    echo "=================================================="
    
    CURRENT_MAC_ARCHIVE="$BUILD_DIR/Mac_${TARGET_ARCH}.xcarchive"
    
    xcodebuild clean archive \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -destination "generic/platform=macOS,arch=${TARGET_ARCH}" \
        -archivePath "$CURRENT_MAC_ARCHIVE" \
        ARCHS="${TARGET_ARCH}" \
        | xcpretty || xcodebuild clean archive \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -destination "generic/platform=macOS,arch=${TARGET_ARCH}" \
        -archivePath "$CURRENT_MAC_ARCHIVE" \
        ARCHS="${TARGET_ARCH}"
        
    if [ ! -d "$CURRENT_MAC_ARCHIVE" ]; then
        echo "❌ macOS (${TARGET_ARCH}) 构建失败！"
        exit 1
    fi
    echo "✅ macOS Archive (${TARGET_ARCH}) 构建成功！"
    
    # 3. 提取 macOS .app 构建产物
    echo ">>> 提取 macOS .app (${TARGET_ARCH})..."
    MAC_APP_PATH="$CURRENT_MAC_ARCHIVE/Products/Applications/ipaDown.app"
    if [ -d "$MAC_APP_PATH" ]; then
        cd "$BUILD_DIR"
        TEMP_APP_DIR="ipaDown_${TARGET_ARCH}_temp"
        mkdir -p "$TEMP_APP_DIR"
        cp -R "$MAC_APP_PATH" "$TEMP_APP_DIR/ipaDown.app"
        
        APP_VERSION=$(defaults read "$(pwd)/$TEMP_APP_DIR/ipaDown.app/Contents/Info.plist" CFBundleShortVersionString)
        
        # 尝试使用 create-dmg
        if command -v create-dmg &> /dev/null; then
            echo ">>> 使用 create-dmg 创建 DMG (${TARGET_ARCH})..."
            DMG_OUT_NAME="ipaDown_${APP_VERSION}_${TARGET_ARCH}.dmg"
            rm -f "$DMG_OUT_NAME"
            create-dmg "$TEMP_APP_DIR/ipaDown.app" "$BUILD_DIR" || true
            
            if [ -f "ipaDown $APP_VERSION.dmg" ]; then
                mv "ipaDown $APP_VERSION.dmg" "$DMG_OUT_NAME"
            elif [ -f "ipaDown.dmg" ]; then
                mv "ipaDown.dmg" "$DMG_OUT_NAME"
            else
                mv ipaDown*.dmg "$DMG_OUT_NAME" 2>/dev/null || true
            fi
            
            echo "✅ macOS 应用 DMG 制作完成: $BUILD_DIR/$DMG_OUT_NAME"
        else
            echo "⚠️ 未找到 create-dmg CLI，降级使用 zip 压缩..."
            cd "$TEMP_APP_DIR"
            zip -r "../ipaDown_${APP_VERSION}_Mac_${TARGET_ARCH}.zip" "ipaDown.app" >/dev/null
            cd ..
            echo "✅ macOS 应用提取完成: $BUILD_DIR/ipaDown_${APP_VERSION}_Mac_${TARGET_ARCH}.zip"
        fi
        
        rm -rf "$TEMP_APP_DIR"
        cd "$PROJECT_DIR"
    else
        echo "❌ 找不到 macOS 应用: $MAC_APP_PATH"
    fi
done

echo "=========================================="
echo "🎉 macOS 打包流程结束！"
echo "产物: $BUILD_DIR/ipaDown_${APP_VERSION}.dmg (或 .zip)"
echo "=========================================="
