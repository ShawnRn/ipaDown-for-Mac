#!/bin/bash

# ipaDown-for-Mac Sparkle 自动化发布脚本
# 用法: ./scripts/release.sh <版本号>
# 示例: ./scripts/release.sh 1.0.1

VERSION=$1

if [ -z "$VERSION" ]; then
    echo "错误: 请提供版本号 (例如: 1.0.1)"
    exit 1
fi

# 1. 配置路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="$PROJECT_DIR/releases"
APPCAST_FILE="$PROJECT_DIR/appcast.xml"
DMG_FILE="$RELEASE_DIR/ipaDown_$VERSION.dmg"

# 尝试定位 Sparkle 签名工具 (根据 Xcode 缓存路径可能不同)
SIGN_TOOL=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -type f -perm +111 | head -n 1)

if [ -z "$SIGN_TOOL" ]; then
    echo "警告: 找不到 Sparkle 的 sign_update 工具。"
    echo "请确保已在 Xcode 中添加了 Sparkle 依赖并至少编译过一次。"
    echo "你也可以手动指定 SIGN_TOOL 路径。"
fi

mkdir -p "$RELEASE_DIR"

# 检查 DMG 是否存在
if [ ! -f "$DMG_FILE" ]; then
    echo "提示: 找不到 DMG 文件: $DMG_FILE"
    echo "请先使用 Xcode Archive 导出 DMG 并放置在 $RELEASE_DIR 目录下。"
    exit 1
fi

echo "--- 开始为版本 $VERSION 准备发布 ---"

# 2. 获取项目版本信息
echo ">>> 检查项目版本信息..."
XCODE_INFO=$(xcodebuild -project ipaDown-for-Apple.xcodeproj -target ipaDown -showBuildSettings 2>/dev/null)
PROJECT_BUILD=$(echo "$XCODE_INFO" | grep "CURRENT_PROJECT_VERSION =" | sed 's/.*= //')
PROJECT_VERSION=$(echo "$XCODE_INFO" | grep "MARKETING_VERSION =" | sed 's/.*= //')

if [ -z "$PROJECT_BUILD" ]; then
    echo "错误: 无法从 Xcode 项目中获取 build 号 (CURRENT_PROJECT_VERSION)"
    exit 1
fi

echo "Xcode 项目 Build 号: $PROJECT_BUILD"
echo "Xcode 项目版本号: $PROJECT_VERSION"

# 3. 检查 appcast.xml 中的 build 号
if [ -f "$APPCAST_FILE" ]; then
    CURRENT_APPCAST_BUILD=$(grep -oE "<sparkle:version>[0-9]+</sparkle:version>" "$APPCAST_FILE" | head -n 1 | grep -oE "[0-9]+")
    echo "当前 appcast.xml 中的 Build 号: $CURRENT_APPCAST_BUILD"
    
    if [ "$PROJECT_BUILD" -lt "$CURRENT_APPCAST_BUILD" ]; then
        echo "❌ 错误: Xcode 项目 build 号 ($PROJECT_BUILD) 必须大于或等于 appcast.xml 中的当前 build 号 ($CURRENT_APPCAST_BUILD)。"
        echo "请检查 Xcode 项目设置中的 Build 号 (CURRENT_PROJECT_VERSION) 以防版本回退。"
        exit 1
    fi
fi

SPARKLE_VERSION="$PROJECT_BUILD"
echo "使用的 Build 号 (sparkle:version): $SPARKLE_VERSION"

# 3. 生成签名
if [ -n "$SIGN_TOOL" ]; then
    echo "正在生成 EdDSA 签名..."
    SIGNATURE=$($SIGN_TOOL "$DMG_FILE")
    echo "签名: $SIGNATURE"
else
    SIGNATURE="sparkle:edSignature=\"YOUR_SIGNATURE_HERE\""
fi

# 4. 获取文件元数据
FILE_SIZE=$(stat -f%z "$DMG_FILE")
PUB_DATE=$(date -R)
DOWNLOAD_URL="https://github.com/ShawnRn/ipaDown-for-Mac/releases/download/v$VERSION/ipaDown_$VERSION.dmg"

# 5. 更新 appcast.xml
echo "正在更新 appcast.xml..."

cat <<EOF > "$APPCAST_FILE"
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>ipaDown-for-Mac Updates</title>
        <item>
            <title>v$VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$SPARKLE_VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure url="$DOWNLOAD_URL" type="application/octet-stream" $SIGNATURE/>
        </item>
    </channel>
</rss>
EOF

echo "--- 准备完成！ ---"
echo "1. appcast.xml 已更新。"
echo "2. 请前往 GitHub 创建 Tag v$VERSION 并上传 releases/$(basename "$DMG_FILE")"
echo "3. 提交并推送 appcast.xml 更改。"
