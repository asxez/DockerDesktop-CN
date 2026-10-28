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

BACKUP_ROOT="$ORIGINAL_HOME/Library/Application Support/DockerDesktop-CN/backup"
if [[ ! -d "$BACKUP_ROOT" ]]; then
    echo "没有找到任何备份，无需恢复。"
    pause_exit
    exit 1
fi

BACKUPS=()
while IFS= read -r dir; do
    if [[ -f "$dir/install-path.txt" ]]; then
        BACKUPS+=("$dir")
    fi
done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -print | sort -r)

if [[ ${#BACKUPS[@]} -eq 0 ]]; then
    echo "没有找到任何有效备份，无需恢复。"
    pause_exit
    exit 1
fi

echo "检测到以下备份："
for i in "${!BACKUPS[@]}"; do
    install_path="$(cat "${BACKUPS[$i]}/install-path.txt" 2>/dev/null || true)"
    echo "  [$((i + 1))] $(basename "${BACKUPS[$i]}")  ->  $install_path"
done

read -r -p "请选择要恢复的备份编号（直接回车选择最新）: " choice
choice="${choice:-1}"
if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#BACKUPS[@]} )); then
    echo "无效的选择：$choice"
    pause_exit
    exit 1
fi

BACKUP_DIR="${BACKUPS[$((choice - 1))]}"
RESOURCES="$(cat "$BACKUP_DIR/install-path.txt")"
if [[ ! -f "$RESOURCES/app.asar" ]]; then
    echo "原安装目录已不存在：$RESOURCES"
    pause_exit
    exit 1
fi
APP_CONTENTS="$(cd "$RESOURCES/.." && pwd)"
INFO_PLIST="$APP_CONTENTS/Info.plist"

if [[ -z "${DOCKER_DESKTOP_SKIP_STOP:-}" ]]; then
    echo "正在关闭 Docker Desktop..."
    osascript -e 'tell application "Docker" to quit' >/dev/null 2>&1 || true
    pkill -f "Docker Desktop.app/Contents/MacOS/Docker Desktop" >/dev/null 2>&1 || true
    sleep 3
fi

echo "正在恢复 app.asar..."
cp -f "$BACKUP_DIR/app.asar" "$RESOURCES/app.asar"

if [[ -d "$BACKUP_DIR/app.asar.unpacked" ]]; then
    echo "正在恢复 app.asar.unpacked..."
    rm -rf "$RESOURCES/app.asar.unpacked"
    cp -R "$BACKUP_DIR/app.asar.unpacked" "$RESOURCES/app.asar.unpacked"
elif [[ -d "$RESOURCES/app.asar.unpacked" ]]; then
    rm -rf "$RESOURCES/app.asar.unpacked"
fi

if [[ -f "$BACKUP_DIR/Info.plist" ]]; then
    echo "正在恢复 Info.plist..."
    cp -f "$BACKUP_DIR/Info.plist" "$INFO_PLIST"
fi

echo "恢复完成！"

if [[ -z "${DOCKER_DESKTOP_NO_LAUNCH:-}" ]]; then
    read -r -p "是否现在启动 Docker Desktop？(Y/n) " answer
    if [[ ! "$answer" =~ ^[nN] ]]; then
        open -a Docker >/dev/null 2>&1 || echo "请手动启动 Docker Desktop。"
    fi
fi

pause_exit
