#!/bin/bash

# ipaDown 双端自动打包导出脚本
# 自动编译并导出 macOS 的 .app (压缩为 .zip) 及 iOS 的 .ipa (通过 Payload 方式)

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
echo "    ipaDown 双端自动打包脚本 (Mac & iOS)   "
echo "=========================================="

# 1a. 获取项目版本信息并预检
echo ">>> 检查项目版本信息..."
XCODE_INFO=$(xcodebuild -project ipaDown-for-Apple.xcodeproj -target ipaDown -showBuildSettings 2>/dev/null)
PROJECT_BUILD=$(echo "$XCODE_INFO" | grep "CURRENT_PROJECT_VERSION =" | sed 's/.*= //')
PROJECT_VERSION=$(echo "$XCODE_INFO" | grep "MARKETING_VERSION =" | sed 's/.*= //')
APPCAST_FILE="$PROJECT_DIR/appcast.xml"

if [ -z "$PROJECT_BUILD" ]; then
    echo "错误: 无法从 Xcode 项目中获取 build 号 (CURRENT_PROJECT_VERSION)"
    exit 1
fi

echo "Xcode 项目 Build 号: $PROJECT_BUILD"
echo "Xcode 项目版本号: $PROJECT_VERSION"

# 检查 appcast.xml 中的 build 号
if [ -f "$APPCAST_FILE" ]; then
    CURRENT_APPCAST_BUILD=$(grep -oE "<sparkle:version>[0-9]+</sparkle:version>" "$APPCAST_FILE" | head -n 1 | grep -oE "[0-9]+")
    if [ -n "$CURRENT_APPCAST_BUILD" ]; then
        echo "当前 appcast.xml 中的 Build 号: $CURRENT_APPCAST_BUILD"
        
        if [ "$PROJECT_BUILD" -lt "$CURRENT_APPCAST_BUILD" ]; then
            echo "❌ 错误: Xcode 项目 build 号 ($PROJECT_BUILD) 必须大于或等于 appcast.xml 中的当前 build 号 ($CURRENT_APPCAST_BUILD)。"
            echo "请检查 Xcode 项目设置中的 Build 号 (CURRENT_PROJECT_VERSION) 以防版本回退。"
            exit 1
        fi
    fi
fi

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
        -destination "generic/platform=macOS" \
        -archivePath "$CURRENT_MAC_ARCHIVE" \
        ARCHS="${TARGET_ARCH}" \
        | xcpretty || xcodebuild clean archive \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -destination "generic/platform=macOS" \
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
    APP_VERSION=$(defaults read "$(pwd)/Payload/ipaDown.app/Info.plist" CFBundleShortVersionString)

    zip -qr "ipaDown_${APP_VERSION}_iOS.ipa" "Payload"
    rm -rf "Payload"
    echo "✅ iOS 应用打包完成: $BUILD_DIR/ipaDown_${APP_VERSION}_iOS.ipa"
else
    echo "❌ 找不到 iOS 应用: $IOS_APP_PATH"
fi

# 6. 生成 Sparkle appcast.xml (针对新产生的双架构 macOS DMG)
echo ">>> 开始更新 Sparkle appcast.xml..."
APPCAST_FILE="$PROJECT_DIR/appcast.xml"
DMG_ARM64="$BUILD_DIR/ipaDown_${APP_VERSION}_arm64.dmg"
DMG_X86_64="$BUILD_DIR/ipaDown_${APP_VERSION}_x86_64.dmg"

if [ -f "$DMG_ARM64" ] && [ -f "$DMG_X86_64" ]; then
    SIGN_TOOL=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -type f -perm +111 | head -n 1)

    SPARKLE_VERSION="$PROJECT_BUILD"
    echo "使用项目 Build 号 (sparkle:version): $SPARKLE_VERSION"

    if [ -n "$SIGN_TOOL" ]; then
        echo "正在生成 DMG 的 EdDSA 签名..."
        SIG_ARM64=$($SIGN_TOOL "$DMG_ARM64")
        SIG_X86_64=$($SIGN_TOOL "$DMG_X86_64")
    else
        echo "⚠️ 找不到 sign_update 工具，将插入占位签名。"
        SIG_ARM64="sparkle:edSignature=\"YOUR_SIGNATURE_HERE\""
        SIG_X86_64="sparkle:edSignature=\"YOUR_SIGNATURE_HERE\""
    fi

    SIZE_ARM64=$(stat -f%z "$DMG_ARM64")
    SIZE_X86_64=$(stat -f%z "$DMG_X86_64")
    PUB_DATE=$(date -R)
    URL_ARM64="https://github.com/ShawnRn/ipaDown-for-Mac/releases/download/v${APP_VERSION}/ipaDown_${APP_VERSION}_arm64.dmg"
    URL_X86_64="https://github.com/ShawnRn/ipaDown-for-Mac/releases/download/v${APP_VERSION}/ipaDown_${APP_VERSION}_x86_64.dmg"

    cat <<EOF > "$APPCAST_FILE"
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>ipaDown-for-Mac Updates</title>
        <item>
            <title>v$APP_VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$SPARKLE_VERSION</sparkle:version>
            <sparkle:shortVersionString>$APP_VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure url="$URL_ARM64" length="$SIZE_ARM64" type="application/octet-stream" sparkle:os="macos" sparkle:nativeArchitecture="arm64" $SIG_ARM64/>
            <enclosure url="$URL_X86_64" length="$SIZE_X86_64" type="application/octet-stream" sparkle:os="macos" sparkle:nativeArchitecture="x86_64" $SIG_X86_64/>
        </item>
    </channel>
</rss>
EOF
    echo "✅ appcast.xml 更新完成！"
    echo "📌 请在 GitHub 创建 Tag v$APP_VERSION 并使用 gh 命令分别上传: "
    echo "$DMG_ARM64 和 $DMG_X86_64"
else
    echo "⚠️ 未找到两份期望的 DMG 文件，跳过更新 appcast.xml"
fi

echo "=========================================="
echo "🎉 自动打包流程全部结束！"
echo "Mac 产物: $BUILD_DIR/ipaDown_${APP_VERSION}.dmg (若已安装 create-dmg) 或 .zip"
echo "iOS 产物: $BUILD_DIR/ipaDown_${APP_VERSION}_iOS.ipa"
echo "=========================================="
