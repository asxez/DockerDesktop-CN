#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"

pause_exit() {
    echo
    read -n 1 -s -r -p "按任意键退出..." || true
    echo
}

if [[ -z "${DOCKER_DESKTOP_SKIP_ELEVATION:-}" && ${EUID} -ne 0 ]]; then
    echo "需要管理员权限，正在请求 sudo..."
    if ! sudo -v; then
        echo "未获得管理员权限，已取消。"
        pause_exit
        exit 1
    fi
    exec sudo -E bash "$SCRIPT_PATH" "$@"
fi

ORIGINAL_USER="${SUDO_USER:-${USER:-$(id -un 2>/dev/null || echo root)}}"
if [[ -n "${DOCKER_DESKTOP_HOME:-}" ]]; then
    ORIGINAL_HOME="$DOCKER_DESKTOP_HOME"
elif [[ "$ORIGINAL_USER" == "root" ]]; then
    ORIGINAL_HOME="$HOME"
else
    ORIGINAL_HOME="$(dscl . -read "/Users/$ORIGINAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || true)"
    [[ -n "$ORIGINAL_HOME" ]] || ORIGINAL_HOME="/Users/$ORIGINAL_USER"
fi

PACKAGE_DIR="$SCRIPT_DIR"
VERSION="$(cat "$PACKAGE_DIR/version.txt" 2>/dev/null || true)"

for file in app.asar Info.plist; do
    if [[ ! -f "$PACKAGE_DIR/$file" ]]; then
        echo "汉化包不完整，缺少 $file"
        pause_exit
        exit 1
    fi
done

RESOURCES="${DOCKER_DESKTOP_RESOURCES:-}"
if [[ -z "$RESOURCES" ]]; then
    for candidate in \
        "/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/Contents/Resources" \
        "$ORIGINAL_HOME/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/Contents/Resources"
    do
        if [[ -f "$candidate/app.asar" ]]; then
            RESOURCES="$candidate"
            break
        fi
    done
fi
if [[ -z "$RESOURCES" || ! -f "$RESOURCES/app.asar" ]]; then
    echo "未找到 Docker Desktop，请先安装后重试。"
    pause_exit
    exit 1
fi

APP_CONTENTS="$(cd "$RESOURCES/.." && pwd)"
INFO_PLIST="$APP_CONTENTS/Info.plist"

if [[ -n "$VERSION" && -f "$INFO_PLIST" ]]; then
    INSTALLED_VERSION="$(defaults read "$INFO_PLIST" CFBundleShortVersionString 2>/dev/null || true)"
    echo "汉化包版本：$VERSION；当前 Docker Desktop 版本：${INSTALLED_VERSION:-未知}"
    if [[ -n "$INSTALLED_VERSION" && "$INSTALLED_VERSION" != "$VERSION"* && -z "${DOCKER_DESKTOP_FORCE:-}" ]]; then
        read -r -p "版本不一致，是否继续？(y/N) " answer
        if [[ ! "$answer" =~ ^[yY] ]]; then
            echo "已取消。"
            pause_exit
            exit 1
        fi
    fi
fi

if [[ -z "${DOCKER_DESKTOP_SKIP_STOP:-}" ]]; then
    echo "正在关闭 Docker Desktop..."
    osascript -e 'tell application "Docker" to quit' >/dev/null 2>&1 || true
    pkill -f "Docker Desktop.app/Contents/MacOS/Docker Desktop" >/dev/null 2>&1 || true
    sleep 3
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$ORIGINAL_HOME/Library/Application Support/DockerDesktop-CN/backup/$STAMP"
mkdir -p "$BACKUP_DIR"

echo "正在备份原文件..."
cp -f "$RESOURCES/app.asar" "$BACKUP_DIR/app.asar"
cp -f "$INFO_PLIST" "$BACKUP_DIR/Info.plist"
if [[ -d "$RESOURCES/app.asar.unpacked" ]]; then
    cp -R "$RESOURCES/app.asar.unpacked" "$BACKUP_DIR/app.asar.unpacked"
fi
printf '%s\n' "$RESOURCES" > "$BACKUP_DIR/install-path.txt"
chown -R "$ORIGINAL_USER" "$BACKUP_DIR" 2>/dev/null || true

echo "正在替换 app.asar..."
cp -f "$PACKAGE_DIR/app.asar" "$RESOURCES/app.asar"

if [[ -d "$PACKAGE_DIR/app.asar.unpacked" ]]; then
    echo "正在替换 app.asar.unpacked..."
    rm -rf "$RESOURCES/app.asar.unpacked"
    cp -R "$PACKAGE_DIR/app.asar.unpacked" "$RESOURCES/app.asar.unpacked"
    chmod -R a+rX "$RESOURCES/app.asar.unpacked"
fi

echo "正在替换 Info.plist..."
cp -f "$PACKAGE_DIR/Info.plist" "$INFO_PLIST"
chmod 644 "$RESOURCES/app.asar" "$INFO_PLIST"

if command -v shasum >/dev/null 2>&1; then
    INSTALLED_HASH="$(shasum -a 256 "$RESOURCES/app.asar" | awk '{print $1}')"
    PACKAGE_HASH="$(shasum -a 256 "$PACKAGE_DIR/app.asar" | awk '{print $1}')"
    if [[ "$INSTALLED_HASH" != "$PACKAGE_HASH" ]]; then
        echo "app.asar 校验失败，请双击 恢复原版.command 还原后重试。"
        pause_exit
        exit 1
    fi
fi

echo "汉化完成！"
echo "备份目录：$BACKUP_DIR"
echo "如需恢复原版，请双击 恢复原版.command。"

if [[ -z "${DOCKER_DESKTOP_NO_LAUNCH:-}" ]]; then
    read -r -p "是否现在启动 Docker Desktop？(Y/n) " answer
    if [[ ! "$answer" =~ ^[nN] ]]; then
        open -a Docker >/dev/null 2>&1 || echo "请手动启动 Docker Desktop。"
    fi
fi

pause_exit
