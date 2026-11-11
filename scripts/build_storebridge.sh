#!/bin/bash
# 固定 IPATool 2.8.0 的协议实现，使用文件会话和 stdin IPC，不调用其 CLI/系统钥匙串。
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if [[ "${PLATFORM_NAME:-macosx}" != macosx ]]; then exit 0; fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REVISION=72c47d538b726df397fbf17bb3af809d69ef51b7
SOURCE="$PROJECT_DIR/.build/storebridge/$REVISION/source"
if [[ ! -d "$SOURCE/.git" ]]; then
    mkdir -p "$(dirname "$SOURCE")"
    git clone --no-checkout https://github.com/majd/ipatool.git "$SOURCE"
fi
git -C "$SOURCE" checkout --detach "$REVISION"
cp "$SCRIPT_DIR/storebridge/download_info.go" "$SOURCE/pkg/appstore/ipadown_download_info.go"
mkdir -p "$SOURCE/cmd/ipadownbridge"
cp "$SCRIPT_DIR/storebridge/main.go" "$SOURCE/cmd/ipadownbridge/main.go"
# 运行时与账号数据一起保存在 ipaDown 私有目录，不更改 HOME。
python3 - "$SOURCE" <<'PY'
import pathlib,sys
root=pathlib.Path(sys.argv[1])
for name,var in [('internal/sap/assets/assets.go','root'),('internal/sap/unicorn/cache_runtime.go','cache')]:
    p=root/name
    s=p.read_text()
    marker=f'{var}, err := os.UserCacheDir()'
    patch=marker+f'\n\tif custom := os.Getenv("IPADOWN_STORE_CACHE"); custom != "" {{ {var}, err = custom, nil }}'
    if 'IPADOWN_STORE_CACHE' not in s:
        assert marker in s, f'Unexpected upstream source in {name}'
        p.write_text(s.replace(marker,patch,1))
PY
FINGERPRINT="$(cat "$SCRIPT_DIR/storebridge/main.go" "$SCRIPT_DIR/storebridge/download_info.go" "$SCRIPT_DIR/build_storebridge.sh" | shasum -a 256 | cut -d ' ' -f 1)"
CACHE="$PROJECT_DIR/.build/storebridge/$REVISION/$FINGERPRINT"
mkdir -p "$CACHE"
PARTS=()
for ARCH in ${ARCHS:-arm64 x86_64}; do
    case "$ARCH" in arm64) GO_ARCH=arm64;; x86_64) GO_ARCH=amd64;; *) exit 1;; esac
    PART="$CACHE/storebridge-$ARCH"
    if [[ ! -f "$PART" ]]; then
        (cd "$SOURCE" && CGO_ENABLED=1 GOOS=darwin GOARCH="$GO_ARCH" CGO_CFLAGS="-mmacosx-version-min=26.0" CGO_LDFLAGS="-mmacosx-version-min=26.0" go build -trimpath -o "$PART.tmp" ./cmd/ipadownbridge)
        mv "$PART.tmp" "$PART"
    fi
    PARTS+=("$PART")
done
if [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
    DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
    LICENSES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/StoreBridgeLicenses"
    mkdir -p "$DEST" "$LICENSES"
    if [[ "${#PARTS[@]}" == 1 ]]; then cp "${PARTS[0]}" "$DEST/storebridge"; else lipo -create "${PARTS[@]}" -output "$DEST/storebridge"; fi
    chmod 755 "$DEST/storebridge"
    cp "$SOURCE/LICENSE" "$LICENSES/IPATool.txt"
    # Include transitive module licenses distributed in the executable.
    (cd "$SOURCE" && go list -m -f '{{if .Dir}}{{.Path}}|{{.Dir}}{{end}}' all) | while IFS='|' read -r MODULE DIRECTORY; do
        if [[ -z "$DIRECTORY" ]]; then continue; fi
        SAFE_NAME="${MODULE//\//_}"
        for FILE in "$DIRECTORY"/LICENSE* "$DIRECTORY"/COPYING* "$DIRECTORY"/NOTICE*; do
            if [[ -f "$FILE" ]]; then cp -f "$FILE" "$LICENSES/${SAFE_NAME}_$(basename "$FILE")"; fi
        done
    done
    if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
        codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime --timestamp=none --entitlements "$SCRIPT_DIR/storebridge/StoreBridge.entitlements" "$DEST/storebridge"
    fi
fi
