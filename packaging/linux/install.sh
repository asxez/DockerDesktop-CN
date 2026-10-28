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

PACKAGE_DIR="$SCRIPT_DIR"
VERSION="$(cat "$PACKAGE_DIR/version.txt" 2>/dev/null || true)"
RESOURCES="${DOCKER_DESKTOP_RESOURCES:-/opt/docker-desktop/resources}"

for file in app.asar; do
    if [[ ! -f "$PACKAGE_DIR/$file" ]]; then
        echo "汉化包不完整，缺少 $file"
        pause_exit
        exit 1
    fi
done

if [[ ! -f "$RESOURCES/app.asar" ]]; then
    echo "未找到 Docker Desktop，预期路径：$RESOURCES"
    echo "请先安装 Docker Desktop，或设置 DOCKER_DESKTOP_RESOURCES 指向资源目录。"
    pause_exit
    exit 1
fi

echo "安装目录：$RESOURCES"
if [[ -n "$VERSION" ]]; then
    echo "汉化包版本：$VERSION"
fi

if [[ -z "${DOCKER_DESKTOP_SKIP_STOP:-}" ]]; then
    echo "正在关闭 Docker Desktop..."
    if command -v systemctl >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
        sudo -u "$ORIGINAL_USER" systemctl --user stop docker-desktop >/dev/null 2>&1 || true
    fi
    pkill -f '/opt/docker-desktop' >/dev/null 2>&1 || true
    sleep 2
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$ORIGINAL_HOME/.local/share/DockerDesktop-CN/backup/$STAMP"
mkdir -p "$BACKUP_DIR"

echo "正在备份原文件..."
cp -f "$RESOURCES/app.asar" "$BACKUP_DIR/app.asar"
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
chmod 644 "$RESOURCES/app.asar"

if command -v sha256sum >/dev/null 2>&1; then
    INSTALLED_HASH="$(sha256sum "$RESOURCES/app.asar" | awk '{print $1}')"
    PACKAGE_HASH="$(sha256sum "$PACKAGE_DIR/app.asar" | awk '{print $1}')"
    if [[ "$INSTALLED_HASH" != "$PACKAGE_HASH" ]]; then
        echo "app.asar 校验失败，请运行 restore.sh 还原后重试。"
        pause_exit
        exit 1
    fi
fi

echo "汉化完成！"
echo "备份目录：$BACKUP_DIR"
echo "如需恢复原版，请运行：sudo ./restore.sh"

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
