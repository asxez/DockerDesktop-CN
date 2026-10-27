param(
    [string]$InstallRoot = "",
    [switch]$SkipElevation,
    [switch]$NoLaunch,
    [switch]$NoPause,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) { Write-Host "[*] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message) { Write-Host "[-] $Message" -ForegroundColor Red }

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $SkipElevation -and -not (Test-Admin)) {
    Write-Step "需要管理员权限，正在重新启动安装程序..."
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    if ($InstallRoot) { $argList += @("-InstallRoot", "`"$InstallRoot`"") }
    if ($NoLaunch) { $argList += "-NoLaunch" }
    if ($NoPause) { $argList += "-NoPause" }
    if ($Force) { $argList += "-Force" }
    try {
        Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList
    } catch {
        Write-Err "无法获取管理员权限：$($_.Exception.Message)"
        if (-not $NoPause) { Read-Host "按回车退出" | Out-Null }
    }
    exit
}

$packageDir = $PSScriptRoot
$packageAsar = Join-Path $packageDir "app.asar"
$packageUnpacked = Join-Path $packageDir "app.asar.unpacked"
$packageExe = Join-Path $packageDir "Docker Desktop.exe"
$versionFile = Join-Path $packageDir "version.txt"

function Get-DockerInstallRoots {
    $roots = @()
    if ($env:ProgramFiles) { $roots += (Join-Path $env:ProgramFiles "Docker\Docker") }
    if ($env:LOCALAPPDATA) { $roots += (Join-Path $env:LOCALAPPDATA "Programs\DockerDesktop") }
    foreach ($key in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Docker Desktop",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Docker Desktop"
    )) {
        try {
            $item = Get-ItemProperty -Path $key -ErrorAction Stop
            if ($item.InstallLocation) { $roots += $item.InstallLocation }
        } catch {
        }
    }
    $roots | Where-Object { $_ -and (Test-Path (Join-Path $_ "frontend\resources\app.asar")) } | Select-Object -Unique
}

try {
    Write-Host ""
    Write-Host "Docker Desktop 汉化安装程序" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor DarkGray

    foreach ($file in @($packageAsar, $packageExe)) {
        if (-not (Test-Path $file)) {
            throw "汉化包不完整，缺少文件：$file"
        }
    }

    $targetVersion = ""
    if (Test-Path $versionFile) {
        $targetVersion = (Get-Content -Path $versionFile -Raw).Trim()
    }

    if ($InstallRoot) {
        if (-not (Test-Path $InstallRoot)) { throw "指定的安装目录不存在：$InstallRoot" }
        $InstallRoot = (Resolve-Path -Path $InstallRoot).Path
    } else {
        $roots = @(Get-DockerInstallRoots)
        if ($roots.Count -eq 0) {
            throw "未找到 Docker Desktop。请先安装 Docker Desktop，或使用 -InstallRoot 指定安装目录。"
        }
        if ($roots.Count -eq 1) {
            $InstallRoot = $roots[0]
        } else {
            Write-Host "检测到多个 Docker Desktop 安装目录：" -ForegroundColor Yellow
            for ($i = 0; $i -lt $roots.Count; $i++) {
                Write-Host ("  [{0}] {1}" -f ($i + 1), $roots[$i])
            }
            $choice = Read-Host "请选择要汉化的目录编号"
            $index = 0
            if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $roots.Count) {
                throw "无效的选择：$choice"
            }
            $InstallRoot = $roots[$index - 1]
        }
    }

    $resourcesDir = Join-Path $InstallRoot "frontend\resources"
    $asarPath = Join-Path $resourcesDir "app.asar"
    $unpackedPath = Join-Path $resourcesDir "app.asar.unpacked"
    $exePath = Join-Path $InstallRoot "frontend\Docker Desktop.exe"

    if (-not (Test-Path $asarPath)) { throw "不是有效的 Docker Desktop 安装目录：$asarPath 不存在" }
    if (-not (Test-Path $exePath)) { throw "找不到 Docker Desktop.exe：$exePath" }

    Write-Step "安装目录：$InstallRoot"
    if ($targetVersion) {
        $installedVersion = (Get-Item -Path $exePath).VersionInfo.ProductVersion
        Write-Step "汉化包版本：$targetVersion；当前 Docker Desktop 版本：$installedVersion"
        if ($installedVersion -and $installedVersion -notlike "$targetVersion*" -and -not $Force) {
            Write-Warn "汉化包版本与当前 Docker Desktop 版本不一致，可能导致 Docker Desktop 无法启动。"
            $answer = Read-Host "仍要继续吗？(y/N)"
            if ($answer -notmatch "^[yY]") { throw "用户取消安装" }
        }
    }

    $running = @(Get-Process -Name "Docker Desktop", "com.docker.backend", "com.docker.build", "com.docker.dev-envs" -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        Write-Step "正在关闭 Docker Desktop..."
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $stillRunning = @(Get-Process -Name "Docker Desktop", "com.docker.backend" -ErrorAction SilentlyContinue)
        if ($stillRunning.Count -gt 0) {
            throw "Docker Desktop 仍在运行，请手动退出后重试。"
        }
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupRoot = Join-Path $env:LOCALAPPDATA "DockerDesktop-CN\backup\$stamp"
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    Write-Step "正在备份原文件到：$backupRoot"
    Copy-Item -Path $asarPath -Destination (Join-Path $backupRoot "app.asar") -Force
    Copy-Item -Path $exePath -Destination (Join-Path $backupRoot "Docker Desktop.exe") -Force
    if (Test-Path $unpackedPath) {
        Copy-Item -Path $unpackedPath -Destination (Join-Path $backupRoot "app.asar.unpacked") -Recurse -Force
    }
    Set-Content -Path (Join-Path $backupRoot "install-path.txt") -Value $InstallRoot -Encoding UTF8

    Write-Step "正在替换 app.asar..."
    Copy-Item -Path $packageAsar -Destination $asarPath -Force

    if (Test-Path $packageUnpacked) {
        Write-Step "正在替换 app.asar.unpacked..."
        if (Test-Path $unpackedPath) {
            Remove-Item -Path $unpackedPath -Recurse -Force
        }
        Copy-Item -Path $packageUnpacked -Destination $unpackedPath -Recurse -Force
    }

    Write-Step "正在替换 Docker Desktop.exe..."
    Copy-Item -Path $packageExe -Destination $exePath -Force

    Write-Step "正在校验文件..."
    $installedAsarHash = (Get-FileHash -Path $asarPath -Algorithm SHA256).Hash
    $packageAsarHash = (Get-FileHash -Path $packageAsar -Algorithm SHA256).Hash
    if ($installedAsarHash -ne $packageAsarHash) {
        throw "app.asar 校验失败，请使用 恢复原版.bat 还原后重试。"
    }

    Write-Ok "汉化完成！"
    Write-Host "备份目录：$backupRoot" -ForegroundColor Gray
    Write-Host "如需恢复原版，请双击 恢复原版.bat。" -ForegroundColor Gray

    if (-not $NoLaunch) {
        Write-Host ""
        $answer = Read-Host "是否现在启动 Docker Desktop？(Y/n)"
        if ($answer -notmatch "^[nN]") {
            Start-Process -FilePath $exePath
        }
    }
} catch {
    Write-Host ""
    Write-Err $_.Exception.Message
    $script:Failed = $true
}

if (-not $NoPause) {
    Write-Host ""
    Read-Host "按回车退出" | Out-Null
}

if ($script:Failed) { exit 1 }
