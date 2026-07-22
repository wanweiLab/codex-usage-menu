#!/bin/zsh
set -euo pipefail

APP_NAME="Codex Pulse.app"
LEGACY_APP_NAME="Codex Usage.app"
INSTALL_ROOT="${INSTALL_DIR:-$HOME/Applications}"
TARGET="$INSTALL_ROOT/$APP_NAME"
LEGACY_TARGET="$INSTALL_ROOT/$LEGACY_APP_NAME"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "错误：此卸载脚本仅支持 macOS。" >&2
    exit 1
fi

REMOVED=0
for candidate in "$TARGET" "$LEGACY_TARGET"; do
    if [[ -e "$candidate" ]]; then
        if [[ "$candidate" != */"$APP_NAME" && "$candidate" != */"$LEGACY_APP_NAME" ]]; then
            echo "错误：拒绝删除无法确认的路径。" >&2
            exit 1
        fi
        rm -rf "$candidate"
        echo "已卸载：$candidate"
        REMOVED=1
    fi
done

if [[ "$REMOVED" == "0" ]]; then
    echo "未找到已安装应用：$TARGET"
fi
