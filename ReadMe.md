# Docker Desktop 汉化包
本仓库提供 Docker Desktop 汉化包。Release 页面会随 Docker Desktop 版本发布对应平台安装程序和汉化包。

Docker汉化  Docker中文版  Docker Desktop汉化 Docker Windows Docker MAC

Windows x86 / Windows arm / macOS Apple Silicon / macOS Intel / Debian x86 均提供汉化包，以 Release 实际产物为准。

**注意: 自 4.39 版本后，汉化包会跟随 Docker Desktop 安装程序一起发布在 [Releases](https://github.com/asxez/DockerDesktop-CN/releases) 页面。**
<br>

<font color=red>已发布汉化脚本，有需要的自行前往，但请遵守仓库相关许可，否则后果自负。</font>

<font color=red><big><u>**注意：本仓库仍然会发布各个版本的汉化包！！！**</u></big></font>

<font color=red>汉化脚本仓库【 https://github.com/asxez/DDCS 】</font>

## 下载指南

**当前macOS intel系列似乎仍不可用**
Release 中的汉化包为 `app-*.zip`：

- `app-Windows-x86.zip`
- `app-Windows-arm.zip`
- `app-Mac-apple.zip`
- `app-Mac-intel.zip`
- `app-Debian-x86.zip`

汉化包内容：

- Windows 包含 `app.asar`、`app.asar.unpacked` 和已同步完整性校验的 `Docker Desktop.exe`。
- macOS 包含 `app.asar`、`app.asar.unpacked` 和已同步完整性校验的 `Info.plist`。
- Linux 包含 `app.asar` 和 `app.asar.unpacked`。

Docker Desktop 4.74.0 起，Windows 版会校验 `app.asar` 完整性。只替换 `app.asar` 会导致 Docker Desktop 无法启动，并出现 `Integrity check failed for asar archive`。Windows 用户必须同时替换 `app.asar`、`app.asar.unpacked` 和汉化包内的 `Docker Desktop.exe`。
macOS 同样会校验 `app.asar` 完整性，校验值位于内层 `Docker Desktop.app/Contents/Info.plist`。macOS 用户必须同时替换 `app.asar`、`app.asar.unpacked` 和汉化包内的 `Info.plist`。

## 使用方法

### Windows：先确认实际安装目录

下文 Windows 示例使用 `C:\Program Files\Docker\Docker` 作为安装根目录。如果 Docker Desktop 安装在其他位置，请将步骤中的安装根目录替换为实际路径。

在每用户安装场景中，安装根目录也可能是 `%LOCALAPPDATA%\Programs\DockerDesktop`（参见 [#82](https://github.com/asxez/DockerDesktop-CN/issues/82)）。安装在该位置时，需要备份和操作的文件为：

- `%LOCALAPPDATA%\Programs\DockerDesktop\frontend\resources\app.asar`
- `%LOCALAPPDATA%\Programs\DockerDesktop\frontend\resources\app.asar.unpacked`
- `%LOCALAPPDATA%\Programs\DockerDesktop\frontend\Docker Desktop.exe`

可以查看 Docker Desktop 快捷方式的“目标”确认可执行文件位置，再检查同一目录下的 `resources\app.asar` 与 `resources\app.asar.unpacked`。PATH 中的 `resources\bin` 路径、卸载项的 `InstallLocation` 也可以作为线索。以实际存在的文件为准，避免把汉化包复制到未使用的旧安装目录。

确认路径后，按下方步骤备份并操作三个文件。`app.asar.unpacked` 仍需按原步骤合并；完整性校验和恢复要求保持一致。

### 操作步骤
1. 关闭 Docker Desktop。
2. 下载当前 Docker Desktop 版本对应的 `app-*.zip` 汉化包并解压。
3. 备份原文件，方便回滚：
   - Windows: `C:\Program Files\Docker\Docker\frontend\resources\app.asar`
   - Windows: `C:\Program Files\Docker\Docker\frontend\resources\app.asar.unpacked`
   - Windows: `C:\Program Files\Docker\Docker\frontend\Docker Desktop.exe`
   - macOS: `/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/Contents/Resources/app.asar`
   - macOS: `/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/Contents/Resources/app.asar.unpacked`
   - macOS: `/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/Contents/Info.plist`
   - Debian/Ubuntu: `/opt/docker-desktop/resources/app.asar`
   - Debian/Ubuntu: `/opt/docker-desktop/resources/app.asar.unpacked`
4. 文件操作：
   - Windows: 将汉化包内的 `app.asar` 替换到 `C:\Program Files\Docker\Docker\frontend\resources\app.asar`
   - Windows: 将汉化包内的 `app.asar.unpacked` 合并到 `C:\Program Files\Docker\Docker\frontend\resources\app.asar.unpacked`，**注意：该处是合并，而非直接替换！**
   - Windows: 将汉化包内的 `Docker Desktop.exe` 替换到 `C:\Program Files\Docker\Docker\frontend\Docker Desktop.exe`
   - macOS: 将汉化包内的 `app.asar` 和 `app.asar.unpacked` 替换到 `/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/Contents/Resources`
   - macOS: 将汉化包内的 `Info.plist` 替换到 `/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/Contents/Info.plist`
   - Debian/Ubuntu: 将汉化包内的 `app.asar` 和 `app.asar.unpacked` 替换到 `/opt/docker-desktop/resources`
5. macOS 不要对 Docker Desktop 执行 ad-hoc 重签名。如果之前已经重签过，请先恢复备份或重装原版 Docker Desktop 后再替换。
6. 启动 Docker Desktop。

Windows 用户请使用管理员权限执行替换操作。恢复原版时，也需要将备份的 `Docker Desktop.exe`、`app.asar` 和 `app.asar.unpacked` 一起恢复。
macOS 用户恢复原版时，也需要将备份的 `Info.plist`、`app.asar` 和 `app.asar.unpacked` 一起恢复。

## 效果图
### Windows
![](images/4.74/w1.png)
![](images/4.74/w2.png)

### Mac
![img_1.png](images/4.38/img_1.png)
![img.png](images/4.38/img.png)

## 更多问题？
有问题的可以扫码加群咨询。
![](images/1.jpg)

## Stars
如果你觉得本仓库对你有用的话，请点上一颗star。
