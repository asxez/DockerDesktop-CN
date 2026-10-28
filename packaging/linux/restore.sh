#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"

pause_exit() {
    echo
    read -r -p "按回车键退出..." || true
}

if [[ -z "${DOCKER_DESKTOP_SKIP_ELEVATION:-}" && ${EUID} -ne 0 ]]; then
    echo "需要 root 权限，正在请求 sudo..."
    if ! sudo -v; then
        echo "未获得 root 权限，已取消。"
        pause_exit
        exit 1
    fi
    exec sudo -E bash "$SCRIPT_PATH" "$@"
fi

ORIGINAL_USER="${SUDO_USER:-${USER:-root}}"
if [[ -n "${DOCKER_DESKTOP_HOME:-}" ]]; then
    ORIGINAL_HOME="$DOCKER_DESKTOP_HOME"
elif [[ "$ORIGINAL_USER" == "root" ]]; then
    ORIGINAL_HOME="$HOME"
else
    ORIGINAL_HOME="$(getent passwd "$ORIGINAL_USER" 2>/dev/null | cut -d: -f6 || true)"
    [[ -n "$ORIGINAL_HOME" ]] || ORIGINAL_HOME="/home/$ORIGINAL_USER"
fi

BACKUP_ROOT="$ORIGINAL_HOME/.local/share/DockerDesktop-CN/backup"
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

if [[ -z "${DOCKER_DESKTOP_SKIP_STOP:-}" ]]; then
    echo "正在关闭 Docker Desktop..."
    if command -v systemctl >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
        sudo -u "$ORIGINAL_USER" systemctl --user stop docker-desktop >/dev/null 2>&1 || true
    fi
    pkill -f '/opt/docker-desktop' >/dev/null 2>&1 || true
    sleep 2
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

echo "恢复完成！"

if [[ -z "${DOCKER_DESKTOP_NO_LAUNCH:-}" ]]; then
    read -r -p "是否现在启动 Docker Desktop？(Y/n) " answer
    if [[ ! "$answer" =~ ^[nN] ]]; then
        if command -v systemctl >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
            sudo -u "$ORIGINAL_USER" systemctl --user start docker-desktop >/dev/null 2>&1 || true
        else
            echo "请手动启动 Docker Desktop。"
        fi
    fi
fi

pause_exit
