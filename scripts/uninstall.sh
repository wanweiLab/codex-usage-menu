#!/bin/zsh
set -euo pipefail

APP_NAME="Codex Usage.app"
INSTALL_ROOT="${INSTALL_DIR:-$HOME/Applications}"
TARGET="$INSTALL_ROOT/$APP_NAME"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "错误：此卸载脚本仅支持 macOS。" >&2
    exit 1
fi

if [[ ! -e "$TARGET" ]]; then
    echo "未找到已安装应用：$TARGET"
    exit 0
fi

if [[ "$TARGET" != */"$APP_NAME" ]]; then
    echo "错误：拒绝删除无法确认的路径。" >&2
    exit 1
fi

rm -rf "$TARGET"
echo "已卸载：$TARGET"
