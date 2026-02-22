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
        
        # create-dmg 默认行为会产生 "appName version.dmg" 或 "appName.dmg" 等情况
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

# 6. 生成 Sparkle appcast.xml (仅针对 macOS DMG)
echo ">>> 开始更新 Sparkle appcast.xml..."
APPCAST_FILE="$PROJECT_DIR/appcast.xml"
DMG_FILE="$BUILD_DIR/ipaDown_${APP_VERSION}.dmg"

if [ -f "$DMG_FILE" ]; then
    SIGN_TOOL=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -type f -perm +111 | head -n 1)

    TODAY=$(date +"%Y%m%d")
    LAST_BUILD=$(grep -oE "<sparkle:version>${TODAY}[0-9]{2}</sparkle:version>" "$APPCAST_FILE" 2>/dev/null | grep -oE "${TODAY}[0-9]{2}" | sort -nr | head -n 1)

    if [ -z "$LAST_BUILD" ]; then
        SPARKLE_VERSION="${TODAY}00"
    else
        SUFFIX=${LAST_BUILD:8:2}
        NEXT_SUFFIX=$(printf "%02d" $((10#$SUFFIX + 1)))
        SPARKLE_VERSION="${TODAY}${NEXT_SUFFIX}"
    fi

    if [ -n "$SIGN_TOOL" ]; then
        echo "正在生成 DMG 的 EdDSA 签名..."
        SIGNATURE=$($SIGN_TOOL "$DMG_FILE")
    else
        echo "⚠️ 找不到 sign_update 工具，将插入占位签名。"
        SIGNATURE="sparkle:edSignature=\"YOUR_SIGNATURE_HERE\""
    fi

    PUB_DATE=$(date -R)
    DOWNLOAD_URL="https://github.com/ShawnRn/ipaDown-for-Mac/releases/download/v${APP_VERSION}/ipaDown_${APP_VERSION}.dmg"

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
            <enclosure url="$DOWNLOAD_URL" type="application/octet-stream" $SIGNATURE/>
        </item>
    </channel>
</rss>
EOF
    echo "✅ appcast.xml 更新完成！"
    echo "📌 请在 GitHub 创建 Tag v$APP_VERSION 并上传 $DMG_FILE 以及 appcast.xml"
else
    echo "⚠️ 未找到 DMG 文件 ($DMG_FILE)，跳过更新 appcast.xml"
fi

echo "=========================================="
echo "🎉 自动打包流程全部结束！"
echo "Mac 产物: $BUILD_DIR/ipaDown_${APP_VERSION}.dmg (若已安装 create-dmg) 或 .zip"
echo "iOS 产物: $BUILD_DIR/ipaDown_${APP_VERSION}_iOS.ipa"
echo "=========================================="
