#!/bin/bash
# 构建固定版本的 UnfairPlay 并嵌入 macOS App；不包含任何账号或模型。
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REVISION="2fad9dcb9506674b92aad5833fad8988d69edc75"
CACHE="$PROJECT_DIR/.build/unfairplay/$REVISION"
if [[ "${PLATFORM_NAME:-macosx}" != "macosx" ]]; then exit 0; fi
if ! command -v go >/dev/null; then
    echo "error: 构建内置 UnfairPlay 需要 Go 1.26 或以上版本。"
    exit 1
fi
if [[ ! -f "$CACHE/unfairplay" ]]; then
    mkdir -p "$CACHE"
    if [[ ! -d "$CACHE/source/.git" ]]; then
        git clone --no-checkout https://github.com/DrWhax/unfairplay.git "$CACHE/source"
    fi
    git -C "$CACHE/source" checkout --detach "$REVISION"
    for ARCH in arm64 amd64; do
        (cd "$CACHE/source" && CGO_ENABLED=0 GOOS=darwin GOARCH="$ARCH" go build -trimpath -o "$CACHE/unfairplay-$ARCH" ./cmd/unfairplay)
    done
    lipo -create "$CACHE/unfairplay-arm64" "$CACHE/unfairplay-amd64" -output "$CACHE/unfairplay.tmp"
    mv "$CACHE/unfairplay.tmp" "$CACHE/unfairplay"
fi
if [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
    DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
    LICENSES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/UnfairPlayLicenses"
    mkdir -p "$DEST" "$LICENSES"
    cp "$CACHE/unfairplay" "$DEST/unfairplay"
    chmod 755 "$DEST/unfairplay"
    for FILE in LICENSE LICENSE-DARKPHOENIX.txt LICENSE-MACOSFAIRFREE.txt NOTICE; do
        cp "$CACHE/source/$FILE" "$LICENSES/$FILE"
    done
    if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
        codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime --timestamp=none "$DEST/unfairplay"
    fi
fi
