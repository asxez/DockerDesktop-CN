# -*- coding: utf-8 -*-
#
# Copyright (C) 2024 ASXE  All Rights Reserved
#
# @Time    : 2024/8/9 下午4:17
# @Author  : ASXE

import json
import multiprocessing
import os
import platform
import plistlib
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from common import log


class DDProcessor:
    def __init__(self, get=True):
        self.get = get
        self.resource_path = self.get_resource_path()
        if self.resource_path is None:
            sys.exit()
        if self.get:
            log.info('正在备份文件...')
            self.cp_asar(self.get)
            log.info('开始解包...')
            self.extract_asar()
        else:
            log.info('开始打包...')
            self.pack_asar()
            log.info('正在替换文件...')
            self.cp_asar(self.get)
            log.info('汉化完成')

    @staticmethod
    def get_resource_path():
        system = platform.system()
        if system == "Windows":
            import winreg

            try:
                reg_key = winreg.OpenKey(
                    winreg.HKEY_LOCAL_MACHINE, rf"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Docker Desktop"
                )
                install_path, _ = winreg.QueryValueEx(reg_key, "InstallLocation")  # 获取安装路径
                winreg.CloseKey(reg_key)

                return Path(f"{install_path}/frontend/resources")
            except FileNotFoundError:
                log.warn('未找到Docker Desktop')
                return None
        elif system == "Darwin":
            potential_paths = [
                Path("/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/Contents/Resources"),
                Path("~/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/Contents/Resources").expanduser(),
            ]
            for path in potential_paths:
                if path.exists():
                    return path
        else:
            log.error(f"unsupported system: {system}")
            return None

    def cp_asar(self, get):
        cwd = Path.cwd()
        try:
            asar_unpacked = Path.cwd() / "app.asar.unpacked"
            if get:
                self.remove_work_path(cwd / "app")
                if asar_unpacked.exists():
                    shutil.rmtree(asar_unpacked)
                resource_unpacked = self.resource_path / "app.asar.unpacked"
                if resource_unpacked.exists():
                    shutil.copytree(resource_unpacked, asar_unpacked)
                shutil.copy(self.resource_path / "app.asar", cwd)
                shutil.copy(self.resource_path / "app.asar", cwd / "app-backup.asar")
            else:
                integrity_path = self.get_integrity_path()
                self.check_asar_integrity_writable(cwd / "app.asar", integrity_path)
                shutil.copy(cwd / "app.asar", self.resource_path)
                local_unpacked = cwd / "app.asar.unpacked"
                target_unpacked = self.resource_path / "app.asar.unpacked"
                if local_unpacked.exists():
                    if target_unpacked.exists():
                        shutil.rmtree(target_unpacked)
                    shutil.copytree(local_unpacked, target_unpacked)
                self.update_asar_integrity(cwd / "app.asar", integrity_path)
        except Exception as e:
            log.error(f"文件复制时出错: {str(e)}")
            sys.exit()

    def get_integrity_path(self):
        system = platform.system()
        if system == "Windows":
            return self.resource_path.parent / "Docker Desktop.exe"
        if system == "Darwin":
            return self.resource_path.parent / "Info.plist"
        return None

    @staticmethod
    def remove_work_path(path: Path):
        cwd = Path.cwd().resolve()
        target = path.resolve()
        if target.parent != cwd:
            raise ValueError(f"拒绝删除工作目录外的路径: {target}")
        if target.exists():
            if target.is_dir():
                shutil.rmtree(target)
            else:
                target.unlink()

    @staticmethod
    def extract_asar():
        asar_command = DDProcessor.get_asar_command()
        if asar_command is None:
            subprocess.run(["npm", "install", "-g", "asar"], check=True)
            asar_command = DDProcessor.get_asar_command()
        if asar_command is None:
            log.error('未找到 asar 命令，即将退出')
            sys.exit()

        result = subprocess.run([asar_command, "extract", "app.asar", "app"])
        if result.returncode != 0:
            log.error('执行解包命令出错，即将退出')
            sys.exit()
        else:
            log.info('解包成功')

    @staticmethod
    def pack_asar():
        asar_command = DDProcessor.get_asar_command()
        if asar_command is None:
            log.error('未找到 asar 命令，即将退出')
            sys.exit()

        command = [asar_command, "pack", "app", "app.asar"]
        unpack_pattern = DDProcessor.get_unpack_pattern(
            Path("app-backup.asar"), Path("app"), asar_command, Path("app.asar.unpacked")
        )
        if unpack_pattern:
            command.extend(["--unpack", unpack_pattern])
            DDProcessor.remove_work_path(Path("app.asar.unpacked"))

        result = subprocess.run(command)
        if result.returncode != 0:
            log.error('执行打包命令出错，即将退出')
            sys.exit()
        else:
            log.info('打包成功')

    @staticmethod
    def get_asar_command():
        local_bin = Path.cwd() / "node_modules" / ".bin"
        candidates = (
            [local_bin / "asar.cmd", local_bin / "asar", "asar.cmd", "asar"]
            if platform.system() == "Windows"
            else [local_bin / "asar", "asar"]
        )
        for candidate in candidates:
            command = str(candidate)
            if isinstance(candidate, Path) and candidate.exists():
                return command
            resolved = shutil.which(command)
            if resolved:
                return resolved
        return None

    @staticmethod
    def update_asar_integrity(asar_path: Path, integrity_path: Path):
        system = platform.system()
        if system == "Darwin":
            DDProcessor.update_macos_asar_integrity(asar_path, integrity_path)
            return
        if system != "Windows":
            return
        if not integrity_path.exists():
            log.warn(f"未找到 Docker Desktop 可执行文件，跳过 asar 完整性更新: {integrity_path}")
            return

        new_hash = DDProcessor.get_asar_integrity_hash(asar_path).encode("ascii")
        integrity_pattern = re.compile(
            rb'("file":"resources\\\\app\.asar","alg":"SHA256","value":")([0-9a-fA-F]{64})(")'
        )
        data = integrity_path.read_bytes()
        old_hashes = {match.group(2).decode("ascii").lower() for match in integrity_pattern.finditer(data)}
        if not old_hashes:
            log.warn("未找到 app.asar 完整性校验信息，跳过更新")
            return

        matches = list(integrity_pattern.finditer(data))
        if all(match.group(2).lower() == new_hash for match in matches):
            log.info("asar 完整性校验已是最新")
            return

        try:
            with integrity_path.open("r+b"):
                pass
        except PermissionError as e:
            raise PermissionError(f"没有权限更新 asar 完整性校验，请使用管理员权限运行脚本: {integrity_path}") from e

        backup_path = integrity_path.with_name(integrity_path.name + ".bak")
        if not backup_path.exists():
            try:
                shutil.copy2(integrity_path, backup_path)
            except PermissionError:
                backup_path = Path.cwd() / (integrity_path.name + ".bak")
                if not backup_path.exists():
                    shutil.copy2(integrity_path, backup_path)
                log.warn(f"安装目录不可写，已将 Docker Desktop.exe 备份到: {backup_path}")
        with integrity_path.open("r+b") as writer:
            for match in matches:
                writer.seek(match.start(2))
                writer.write(new_hash)
        old_hash_text = ", ".join(sorted(old_hashes))
        log.info(f"已更新 asar 完整性校验: {old_hash_text} -> {new_hash.decode('ascii')}")

    @staticmethod
    def update_macos_asar_integrity(asar_path: Path, info_plist_path: Path):
        if not info_plist_path or not info_plist_path.exists():
            log.warn(f"未找到 Docker Desktop Info.plist，跳过 asar 完整性更新: {info_plist_path}")
            return

        raw = info_plist_path.read_bytes()
        plist_format = plistlib.FMT_BINARY if raw.startswith(b"bplist") else plistlib.FMT_XML
        plist = plistlib.loads(raw)
        integrity = plist.get("ElectronAsarIntegrity")
        if not isinstance(integrity, dict):
            log.warn("未找到 ElectronAsarIntegrity，跳过 macOS asar 完整性更新")
            return

        archive_key = next((key for key in integrity if key.lower() == "resources/app.asar"), "Resources/app.asar")
        entry = integrity.get(archive_key)
        if not isinstance(entry, dict):
            entry = {"algorithm": "SHA256"}
            integrity[archive_key] = entry

        new_hash = DDProcessor.get_asar_integrity_hash(asar_path)
        old_hash = entry.get("hash")
        if old_hash == new_hash:
            log.info("macOS asar 完整性校验已是最新")
            return

        try:
            with info_plist_path.open("r+b"):
                pass
        except PermissionError as e:
            raise PermissionError(f"没有权限更新 macOS asar 完整性校验，请使用管理员权限运行脚本: {info_plist_path}") from e

        backup_path = info_plist_path.with_name(info_plist_path.name + ".bak")
        if not backup_path.exists():
            shutil.copy2(info_plist_path, backup_path)

        entry["algorithm"] = "SHA256"
        entry["hash"] = new_hash
        info_plist_path.write_bytes(plistlib.dumps(plist, fmt=plist_format, sort_keys=False))
        log.info(f"已更新 macOS asar 完整性校验: {old_hash} -> {new_hash}")

    @staticmethod
    def check_asar_integrity_writable(asar_path: Path, integrity_path: Path):
        system = platform.system()
        if system == "Darwin":
            DDProcessor.check_macos_asar_integrity_writable(asar_path, integrity_path)
            return
        if system != "Windows" or not integrity_path.exists():
            return

        new_hash = DDProcessor.get_asar_integrity_hash(asar_path).encode("ascii")
        integrity_pattern = re.compile(
            rb'("file":"resources\\\\app\.asar","alg":"SHA256","value":")([0-9a-fA-F]{64})(")'
        )
        matches = list(integrity_pattern.finditer(integrity_path.read_bytes()))
        if not matches or all(match.group(2).lower() == new_hash for match in matches):
            return

        try:
            with integrity_path.open("r+b"):
                pass
        except PermissionError as e:
            raise PermissionError(f"没有权限更新 asar 完整性校验，请使用管理员权限运行脚本: {integrity_path}") from e

    @staticmethod
    def check_macos_asar_integrity_writable(asar_path: Path, info_plist_path: Path):
        if not info_plist_path or not info_plist_path.exists():
            return

        plist = plistlib.loads(info_plist_path.read_bytes())
        integrity = plist.get("ElectronAsarIntegrity")
        if not isinstance(integrity, dict):
            return

        archive_key = next((key for key in integrity if key.lower() == "resources/app.asar"), None)
        entry = integrity.get(archive_key) if archive_key else None
        old_hash = entry.get("hash") if isinstance(entry, dict) else None
        if old_hash == DDProcessor.get_asar_integrity_hash(asar_path):
            return

        try:
            with info_plist_path.open("r+b"):
                pass
        except PermissionError as e:
            raise PermissionError(f"没有权限更新 macOS asar 完整性校验，请使用管理员权限运行脚本: {info_plist_path}") from e

    @staticmethod
    def get_asar_integrity_hash(asar_path: Path):
        asar_command = DDProcessor.get_asar_command()
        if asar_command is None:
            raise RuntimeError("未找到 asar 命令，无法计算 asar 完整性校验")

        script = (
            "const disk=require('asar/lib/disk');"
            "const crypto=require('crypto');"
            "const header=disk.readArchiveHeaderSync(process.argv[1]).header;"
            "process.stdout.write(crypto.createHash('sha256').update(JSON.stringify(header)).digest('hex'));"
        )
        result = subprocess.run(
            ["node", "-e", script, str(asar_path)], capture_output=True, check=True, text=True
        )
        return result.stdout.strip()

    @staticmethod
    def get_unpack_pattern(archive: Path, source_path: Path, asar_command: str, unpacked_path: Path):
        unpacked_paths = []
        if unpacked_path.exists():
            for item in unpacked_path.rglob("*"):
                if item.is_file():
                    unpacked_paths.append(str(item.relative_to(unpacked_path)))
        elif archive.exists():
            try:
                result = subprocess.run(
                    [asar_command, "list", str(archive), "--is-pack"],
                    capture_output=True,
                    check=True,
                    text=True,
                )
            except Exception as e:
                log.warn(f"读取原始 asar unpacked 清单失败，将尝试从 app.asar.unpacked 恢复: {str(e)}")
            else:
                for line in result.stdout.splitlines():
                    state, _, raw_path = line.partition(":")
                    if state.strip() == "unpack":
                        unpacked_paths.append(raw_path)

        unpacked_files = []
        seen = set()
        for raw_path in unpacked_paths:
            rel_path = raw_path.strip().lstrip("\\/").replace("\\", "/")
            if not rel_path or rel_path in seen:
                continue
            seen.add(rel_path)

            source_file = source_path / Path(*rel_path.split("/"))
            unpacked_file = unpacked_path / Path(*rel_path.split("/"))
            if not source_file.is_file() and unpacked_file.is_file():
                source_file.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(unpacked_file, source_file)
            if source_file.is_file():
                unpacked_files.append(f"{source_path.name}/{rel_path}")

        if not unpacked_files:
            return None
        log.info(f"保留原始 asar unpacked 文件: {len(unpacked_files)} 个")
        unpack_pattern = ",".join(unpacked_files)
        return "{" + unpack_pattern + "}" if "," in unpack_pattern else unpack_pattern


class FileProcessor:
    def __init__(self, root_path, config_path):
        self.root_path = root_path
        self.config_path = config_path

    def recursive_listdir(self):
        file_paths = []
        for root, _, files in os.walk(self.root_path):
            for file in files:
                if file.endswith('.js') or file.endswith('.cjs'):
                    file_paths.append(os.path.join(root, file))
        return file_paths

    def get_transformations(self):
        with open(self.config_path, 'r', encoding='utf-8') as f:
            transformations = json.loads(f.read())['all']
        for transformation in transformations:
            yield transformation

    @staticmethod
    def process_file(file_path, search, replacement):
        with open(file_path, 'r+', encoding='utf-8') as f:
            content = f.read()
            new_content = content.replace(search, replacement)
            if new_content != content:
                f.seek(0)
                f.write(new_content)
                f.truncate()
                return True
            else:
                return False

    def process_files(self, file_paths, search_pattern, replacement):
        cpu_count = multiprocessing.cpu_count()
        replaced = False
        with ThreadPoolExecutor(max_workers=cpu_count) as executor:
            futures = [executor.submit(self.process_file, file_path, search_pattern, replacement) for file_path in
                       file_paths]
            for future in futures:
                if future.result():
                    replaced = True
        return replaced
