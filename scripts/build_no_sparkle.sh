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

# 2 & 3. 编译与提取 macOS 版本 (双架构分离)
echo ">>> 开始编译 macOS 版本..."
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
    else
        echo "❌ 找不到 macOS 应用: $MAC_APP_PATH"
    fi
done

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
