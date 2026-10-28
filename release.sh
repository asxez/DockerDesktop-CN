#!/usr/bin/env bash
set -euo pipefail

target_repo="asxez/DockerDesktop-CN"
root_dir=$(pwd)
asar_bin="./node_modules/.bin/asar"

rm -rf tmp && mkdir -p dist tmp

# repo latest release
release=$(gh release view --repo "${target_repo}" --json tagName --jq .tagName 2>/dev/null || true)

# docker desktop latest version / build path
wget -q -O tmp/release-notes.md https://github.com/docker/docs/raw/refs/heads/main/content/manuals/desktop/release-notes.md
read -r version build_path < <(python - tmp/release-notes.md <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(
    r'{{<[^\n]*?all=true[^\n]*?version="([^"]+)"[^\n]*?build_path="([^"]+)"',
    text,
)
if match:
    print(match.group(1), match.group(2))
PY
)

if [[ -z "${version}" || -z "${build_path}" ]]; then
    echo "无法从 release-notes.md 解析 Docker Desktop 版本或下载路径" >&2
    exit 1
fi
echo "Docker Desktop latest: ${version} (build_path=${build_path}), current release: ${release:-none}"

if [[ "${release}" == "${version}" ]]; then
    echo "We already have the latest version"
    exit 0
fi

# install 7z
if [[ ! -e "./7z/7zz" ]]; then
    mkdir -p 7z
    wget -q -O 7z/7z.tar.xz https://github.com/ip7z/7zip/releases/download/26.00/7z2600-linux-x64.tar.xz
    tar -xf 7z/7z.tar.xz -C 7z
fi

# install requirements
if [[ ! -x "${asar_bin}" ]]; then
    npm install
fi
if ! python -c "import black" >/dev/null 2>&1; then
    pip install -r requirements.txt
fi

download() {
    local output=$1
    local url=$2
    if [[ -s "${output}" ]]; then
        return
    fi
    wget -q --show-progress --tries=3 --timeout=120 -O "${output}" "${url}"
    if [[ ! -s "${output}" ]]; then
        echo "下载失败: ${url}" >&2
        exit 1
    fi
}

# download dd
download "dist/DockerDesktop-${version}-Windows-x86.exe" "https://desktop.docker.com/win/main/amd64${build_path}Docker%20Desktop%20Installer.exe"
download "dist/DockerDesktop-${version}-Windows-arm.exe" "https://desktop.docker.com/win/main/arm64${build_path}Docker%20Desktop%20Installer.exe"
download "dist/DockerDesktop-${version}-Mac-apple.dmg" "https://desktop.docker.com/mac/main/arm64${build_path}Docker.dmg"
download "dist/DockerDesktop-${version}-Mac-intel.dmg" "https://desktop.docker.com/mac/main/amd64${build_path}Docker.dmg"
download "dist/DockerDesktop-${version}-Debian-x86.deb" "https://desktop.docker.com/linux/main/amd64${build_path}docker-desktop-amd64.deb"

function asar_header_hash() {
    node -e 'const disk=require("asar/lib/disk"); const crypto=require("crypto"); const header=disk.readArchiveHeaderSync(process.argv[1]).header; process.stdout.write(crypto.createHash("sha256").update(JSON.stringify(header)).digest("hex"));' "$1"
}

function patch_windows_integrity() {
    local asar_path=$1
    local exe_path=$2
    local new_hash
    new_hash=$(asar_header_hash "${asar_path}")

    python - "${exe_path}" "${new_hash}" <<'PY'
import re
import sys
from pathlib import Path

exe_path = Path(sys.argv[1])
new_hash = sys.argv[2].encode("ascii")
pattern = re.compile(rb'("file":"resources\\\\app\.asar","alg":"SHA256","value":")([0-9a-fA-F]{64})(")')
data = exe_path.read_bytes()
matches = list(pattern.finditer(data))
if not matches:
    print(f"warning: app.asar integrity metadata not found in {exe_path}", file=sys.stderr)
    sys.exit(0)

backup_path = exe_path.with_name(exe_path.name + ".bak")
if not backup_path.exists():
    backup_path.write_bytes(data)

with exe_path.open("r+b") as writer:
    for match in matches:
        writer.seek(match.start(2))
        writer.write(new_hash)
PY
}

function patch_macos_integrity() {
    local asar_path=$1
    local plist_path=$2
    local new_hash
    new_hash=$(asar_header_hash "${asar_path}")

    python - "${plist_path}" "${new_hash}" <<'PY'
import sys
import plistlib
from pathlib import Path

plist_path = Path(sys.argv[1])
new_hash = sys.argv[2]

if not plist_path.exists():
    print(f"warning: Info.plist not found in {plist_path}", file=sys.stderr)
    sys.exit(0)

raw = plist_path.read_bytes()
plist_format = plistlib.FMT_BINARY if raw.startswith(b"bplist") else plistlib.FMT_XML
plist = plistlib.loads(raw)
integrity = plist.get("ElectronAsarIntegrity")
if not isinstance(integrity, dict):
    print("warning: ElectronAsarIntegrity not found in Info.plist", file=sys.stderr)
    sys.exit(0)

archive_key = next((key for key in integrity if key.lower() == "resources/app.asar"), "Resources/app.asar")
entry = integrity.get(archive_key)
if not isinstance(entry, dict):
    entry = {"algorithm": "SHA256"}
    integrity[archive_key] = entry

entry["algorithm"] = "SHA256"
entry["hash"] = new_hash

backup_path = plist_path.with_name(plist_path.name + ".bak")
if not backup_path.exists():
    backup_path.write_bytes(raw)

plist_path.write_bytes(plistlib.dumps(plist, fmt=plist_format, sort_keys=False))
PY
}

function pack_asar() {
    local source_dir=$1
    local original_unpacked=$2
    local output_asar=$3
    local unpack_pattern=""

    if [ -d "${original_unpacked}" ]; then
        unpack_pattern=$(cd "${original_unpacked}" && find . -type f | sed "s#^\./#${source_dir}/#" | paste -sd, -)
    fi

    if [ -n "${unpack_pattern}" ]; then
        if [[ "${unpack_pattern}" == *,* ]]; then
            unpack_pattern="{${unpack_pattern}}"
        fi
        "${asar_bin}" pack "${source_dir}" "${output_asar}" --unpack "${unpack_pattern}"
    else
        "${asar_bin}" pack "${source_dir}" "${output_asar}"
    fi
}

# unzip, extract, replace, pack
function ddcs() {
    pkg_name=$1
    # Windows-x86, Windows-arm, Mac-apple, Mac-intel, Debian-x86
    arch=$(echo "$pkg_name" | sed -nr 's/DockerDesktop-.+-(.+-.+)\..+/\1/p')

    rm -f "dist/app-${arch}.zip"
    rm -rf "tmp/${arch}" "tmp/app-${arch}" "tmp/app-${arch}.asar" "tmp/app-${arch}.asar.unpacked" "tmp/package-${arch}"
    ./7z/7zz x "dist/${pkg_name}" -y -o"tmp/${arch}" -bso0 -bd || true

    if [[ $arch == Windows* ]]; then
        # 4.97+ 的 Windows 安装器改为自定义 PE，app.asar 在 RT_RCDATA/DOCKERDESKTOP 中。
        if ! find "tmp/${arch}" -type f -name "app.asar" -print -quit | grep -q .; then
            echo "检测到新版 Docker Windows 安装器，正在提取内嵌组件..."
            python tools/extract_windows_payload.py "dist/${pkg_name}" "tmp/${arch}/.payload"
            payload=$(find "tmp/${arch}/.payload" -type f -name "DOCKERDESKTOP.7z" -print -quit)
            if [[ -z "${payload}" ]]; then
                echo "未找到 DOCKERDESKTOP 组件" >&2
                exit 1
            fi
            ./7z/7zz x "${payload}" -o"tmp/${arch}" -y -bso0 -bd
            rm -rf "tmp/${arch}/.payload"
        fi
    elif [[ $arch == Debian* ]]; then
        data_tar=$(find "tmp/${arch}" -maxdepth 2 -type f -name "data.tar*" -print -quit)
        if [[ -z "${data_tar}" ]]; then
            echo "未找到 Debian 安装包的 data.tar" >&2
            exit 1
        fi
        tar -xf "${data_tar}" -C "tmp/${arch}"
    elif [[ $arch != Mac* ]]; then
        echo "unknown arch"
        exit 1
    fi

    app_asar=$(find "tmp/${arch}" -type f -path "*/frontend/resources/app.asar" -print -quit)
    if [[ -z "${app_asar}" && $arch == Mac* ]]; then
        app_asar=$(find "tmp/${arch}" -type f -path "*/Docker Desktop.app/Contents/Resources/app.asar" -print -quit)
    fi
    if [[ -z "${app_asar}" && $arch == Debian* ]]; then
        app_asar=$(find "tmp/${arch}" -type f -path "*/opt/docker-desktop/resources/app.asar" -print -quit)
    fi
    if [[ -z "${app_asar}" ]]; then
        app_asar=$(find "tmp/${arch}" -type f -name "app.asar" -print -quit)
    fi
    if [[ -z "${app_asar}" ]]; then
        echo "未在安装包中找到 app.asar，解压目录内容：" >&2
        find "tmp/${arch}" -maxdepth 4 -print | head -100 >&2
        exit 1
    fi
    resources_dir=$(dirname "${app_asar}")
    mv "${app_asar}" "tmp/app-${arch}.asar"
    if [[ -d "${resources_dir}/app.asar.unpacked" ]]; then
        mv "${resources_dir}/app.asar.unpacked" "tmp/app-${arch}.asar.unpacked"
    fi

    if [[ $arch == Windows* ]]; then
        exe_path=$(find "tmp/${arch}" -type f -path "*/frontend/Docker Desktop.exe" -print -quit)
        if [[ -z "${exe_path}" ]]; then
            exe_path=$(find "tmp/${arch}" -type f -name "Docker Desktop.exe" -print -quit)
        fi
        if [[ -z "${exe_path}" ]]; then
            echo "未找到 Docker Desktop.exe" >&2
            exit 1
        fi
    elif [[ $arch == Mac* ]]; then
        plist_path=$(find "tmp/${arch}" -type f -path "*/Docker Desktop.app/Contents/Info.plist" -print -quit)
        if [[ -z "${plist_path}" ]]; then
            echo "未找到 macOS Info.plist" >&2
            exit 1
        fi
    fi

    "${asar_bin}" extract "tmp/app-${arch}.asar" "tmp/app-${arch}"
    python ddcs.py --root_path "tmp/app-${arch}" > /dev/null

    mkdir -p "tmp/package-${arch}"
    pack_asar "tmp/app-${arch}" "tmp/app-${arch}.asar.unpacked" "tmp/package-${arch}/app.asar"
    if [[ $arch == Windows* ]]; then
        patch_windows_integrity "tmp/package-${arch}/app.asar" "${exe_path}"
        cp "${exe_path}" "tmp/package-${arch}/Docker Desktop.exe"
        cp "packaging/windows/install.bat" "tmp/package-${arch}/安装汉化.bat"
        cp "packaging/windows/install.ps1" "tmp/package-${arch}/install.ps1"
        cp "packaging/windows/restore.bat" "tmp/package-${arch}/恢复原版.bat"
        cp "packaging/windows/restore.ps1" "tmp/package-${arch}/restore.ps1"
        cp "packaging/windows/使用说明.txt" "tmp/package-${arch}/使用说明.txt"
        printf '%s' "${version}" > "tmp/package-${arch}/version.txt"
    elif [[ $arch == Mac* ]]; then
        patch_macos_integrity "tmp/package-${arch}/app.asar" "${plist_path}"
        cp "${plist_path}" "tmp/package-${arch}/Info.plist"
        cp "packaging/macos/install.command" "tmp/package-${arch}/安装汉化.command"
        cp "packaging/macos/restore.command" "tmp/package-${arch}/恢复原版.command"
        cp "packaging/macos/使用说明.txt" "tmp/package-${arch}/使用说明.txt"
        printf '%s' "${version}" > "tmp/package-${arch}/version.txt"
        chmod +x "tmp/package-${arch}/安装汉化.command" "tmp/package-${arch}/恢复原版.command"
    elif [[ $arch == Debian* ]]; then
        cp "packaging/linux/install.sh" "tmp/package-${arch}/install.sh"
        cp "packaging/linux/restore.sh" "tmp/package-${arch}/restore.sh"
        cp "packaging/linux/使用说明.txt" "tmp/package-${arch}/使用说明.txt"
        printf '%s' "${version}" > "tmp/package-${arch}/version.txt"
        chmod +x "tmp/package-${arch}/install.sh" "tmp/package-${arch}/restore.sh"
    fi

    (
        cd "tmp/package-${arch}"
        "${root_dir}/7z/7zz" a -tzip "${root_dir}/dist/app-${arch}.zip" . -mcu=on -bso0 -bd
    )
    rm -rf "tmp/${arch}" "tmp/app-${arch}" "tmp/app-${arch}.asar" "tmp/app-${arch}.asar.unpacked" "tmp/package-${arch}"
}

ddcs "DockerDesktop-${version}-Windows-x86.exe"
ddcs "DockerDesktop-${version}-Windows-arm.exe"
ddcs "DockerDesktop-${version}-Mac-apple.dmg"
ddcs "DockerDesktop-${version}-Mac-intel.dmg"
ddcs "DockerDesktop-${version}-Debian-x86.deb"


notes="DockerDesktop ${version} 版本安装程序及汉化包.

Windows 汉化包内附 安装汉化.bat / 恢复原版.bat，双击即可自动完成备份、替换、校验和恢复。
macOS 汉化包内附 安装汉化.command / 恢复原版.command，双击并按提示授权即可。
Linux 汉化包内附 install.sh / restore.sh，执行 sudo ./install.sh 即可。

汉化脚本源码已合并到本仓库，使用方法见 ReadMe。"

gh release create "${version}" --repo "${target_repo}" --notes "$notes" ./dist/*
