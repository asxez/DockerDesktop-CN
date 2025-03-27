# Docker Desktop汉化包
本仓库提供最新版本Docker Desktop 汉化包。

Docker汉化  Docker中文版  Docker Desktop汉化 Docker Windows Docker MAC

~~Windows arm 用户只能使用脚本进行汉化。这个架构的汉化包本仓库不予提供。~~

**注意: 自 4.39 版本后, 汉化 Asar 包会跟随 DockerDesktop 安装程序一起发布在 [Releases](https://github.com/asxez/DockerDesktop-CN/releases) 页面**
<br>

<font color=red>已发布汉化脚本，有需要的自行前往，但请遵守仓库相关许可，否则后果自负。</font>

<font color=red><big><u>**注意：本仓库仍然会发布各个版本的汉化包！！！**</u></big></font>

<font color=red>汉化脚本仓库【 https://github.com/asxez/DDCS 】</font>

## 下载指南

- Windows
  - 使用 Intel/AMD 的 x64 芯片（**较为普遍**），则下载 DockerDesktop-x.x.x-Windows-x86.exe（本体）和 app-Windows-x86.asar（汉化包）
  - 使用 arm 芯片（**较为稀有**），则下载 DockerDesktop-x.x.x-Windows-arm.exe（本体）和 app-Windows-arm.asar（汉化包）
- Mac
  - 使用 M 系列芯片（**新款**），则下载 DockerDesktop-x.x.x-Mac-apple.dmg（本体）和 app-Mac-apple.asar （汉化包）
  - 使用 Intel x64 芯片（**2020前旧款**），则下载 DockerDesktop-x.x.x-Mac-intel.dmg（本体）和 app-Mac-intel.asar （汉化包）
- Linux 
  - Ubuntu/Debian  
    - 使用 Intel/AMD 的 x64 芯片（**较为普遍**），则下载 DockerDesktop-x.x.x-Debian-x86.deb（本体）和 app-Debian-x86.asar（汉化包）
    - 使用 arm 芯片（**较为稀有**），暂不支持
  - Fedora/Arch/RHEL 暂不支持

## 使用方法
1. 关闭Docker Desktop
2. 在Docker安装目录找到app.asar文件并将其备份，防止出现意外。
   - Windows下默认为`C:\Program Files\Docker\Docker\frontend\resources`
   - Macos下默认为`/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/Contents/Resources`
   - Ubuntu/Debian下默认为`/opt/docker-desktop/resources`
3. 将从本仓库下载的asar文件改名为app.asar后替换原文件

## 最新版本效果图
### Windows
![](images/4.38/w1.png)
![](images/4.38/w2.png)

### Mac
![img_1.png](images/4.38/img_1.png)
![img.png](images/4.38/img.png)

## 更多问题？
有问题的可以扫码加群咨询。
![](images/1.jpg)

## 历史更新
2025.2.8 更新4.38版本汉化包

2024.12.17 更新4.37版本汉化包

2024.11.20 更新4.36版本汉化包

2024.10.26 更新4.35版本汉化包

2024.9.3 更新4.34版本汉化包

2024.8.28 更新4.33 MAC版汉化包

2024.8.12 更新4.32 MAC版汉化包

2024.8.10 发布首个汉化脚本版本

2024.8.9 更新4.33版本汉化包

2024.7.9 更新4.32版本汉化包

2024.5.12 更新4.29、4.30版本汉化包

2024.3.24 创建本仓库并更新4.28版本汉化包

## Stars
如果你觉得本仓库对你有用的话，请点上一颗star。
