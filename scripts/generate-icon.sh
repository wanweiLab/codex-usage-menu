#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SOURCE_ICON="$PROJECT_DIR/Resources/AppIcon.png"
OUTPUT_ICON="$PROJECT_DIR/Resources/AppIcon.icns"
APPICON_MANIFEST="$PROJECT_DIR/Resources/AppIcon.appiconset/Contents.json"
# actool 在 macOS 26 上会把部分临时输出规范化到 /tmp；固定使用该路径，
# 避免系统 TMPDIR 与实际输出目录不一致。
WORK_DIR="$(mktemp -d "/private/tmp/codex-pulse-icon.XXXXXX")"
ASSET_CATALOG="$WORK_DIR/Assets.xcassets"
APPICON_SET="$ASSET_CATALOG/AppIcon.appiconset"
COMPILED_DIR="$WORK_DIR/compiled"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "错误：macOS .icns 生成仅支持 macOS。" >&2
    exit 1
fi

for tool in sips xcrun; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "错误：缺少 $tool。" >&2
        exit 1
    fi
done

if ! xcrun --find actool >/dev/null 2>&1; then
    echo "错误：没有找到 Xcode Asset Catalog 编译器（actool）。" >&2
    exit 1
fi

if [[ ! -f "$SOURCE_ICON" ]]; then
    echo "错误：没有找到图标源文件：$SOURCE_ICON" >&2
    exit 1
fi

if [[ ! -f "$APPICON_MANIFEST" ]]; then
    echo "错误：没有找到图标资源清单：$APPICON_MANIFEST" >&2
    exit 1
fi

mkdir -p "$APPICON_SET" "$COMPILED_DIR"
cp "$APPICON_MANIFEST" "$APPICON_SET/Contents.json"
sips -z 1024 1024 "$SOURCE_ICON" --out "$APPICON_SET/AppIcon-1024.png" >/dev/null

# macOS 26 的 iconutil 无法稳定回编传统 iconset，改用 Apple 的
# Asset Catalog 编译链生成兼容的新式 .icns。
xcrun actool \
    --compile "$COMPILED_DIR" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$WORK_DIR/partial.plist" \
    "$ASSET_CATALOG" >/dev/null

cp "$COMPILED_DIR/AppIcon.icns" "$OUTPUT_ICON"
echo "$OUTPUT_ICON"
