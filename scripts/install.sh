#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_NAME="Codex Usage.app"
INSTALL_ROOT="${INSTALL_DIR:-$HOME/Applications}"
DESTINATION="$INSTALL_ROOT/$APP_NAME"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-install.XXXXXX")"
STAGED_APP="$TEMP_ROOT/$APP_NAME"
BACKUP_APP="$INSTALL_ROOT/.Codex Usage.app.backup.$$"
BACKUP_CREATED=0

cleanup() {
    rm -rf "$TEMP_ROOT"
}

restore_backup() {
    if [[ "$BACKUP_CREATED" == "1" && ! -e "$DESTINATION" && -e "$BACKUP_APP" ]]; then
        mv "$BACKUP_APP" "$DESTINATION"
    fi
}

trap 'restore_backup; cleanup' EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "错误：Codex Usage 目前仅支持 macOS。" >&2
    exit 1
fi

for tool in swift codesign; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "错误：缺少 $tool。请先安装 Xcode Command Line Tools：xcode-select --install" >&2
        exit 1
    fi
done

find_codex() {
    local candidates=(
        "/Applications/ChatGPT.app/Contents/Resources/codex"
        "/Applications/Codex.app/Contents/Resources/codex"
        "$HOME/.local/bin/codex"
        "/opt/homebrew/bin/codex"
        "/usr/local/bin/codex"
    )

    if [[ -n "${CODEX_CLI_PATH:-}" && -x "$CODEX_CLI_PATH" ]]; then
        echo "$CODEX_CLI_PATH"
        return 0
    fi

    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    command -v codex 2>/dev/null || return 1
}

if ! CODEX_PATH="$(find_codex)"; then
    echo "错误：没有找到 Codex。请先安装并登录 ChatGPT 或 Codex。" >&2
    exit 1
fi

echo "找到 Codex：$CODEX_PATH"
echo "正在本机编译 Codex Usage…"
cd "$PROJECT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/CodexUsageMenu" "$STAGED_APP/Contents/MacOS/CodexUsageMenu"
cp "$PROJECT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
codesign --force --deep --sign - "$STAGED_APP"

codesign --verify --deep --strict "$STAGED_APP"
test -x "$STAGED_APP/Contents/MacOS/CodexUsageMenu"

mkdir -p "$INSTALL_ROOT"
if [[ -e "$DESTINATION" ]]; then
    mv "$DESTINATION" "$BACKUP_APP"
    BACKUP_CREATED=1
fi

mv "$STAGED_APP" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"

if [[ "$BACKUP_CREATED" == "1" ]]; then
    rm -rf "$BACKUP_APP"
    BACKUP_CREATED=0
fi

if [[ "${NO_LAUNCH:-0}" != "1" ]]; then
    open "$DESTINATION"
fi

echo "安装完成：$DESTINATION"
echo "应用会使用当前 Codex 登录读取额度，不会读取或保存登录令牌。"
