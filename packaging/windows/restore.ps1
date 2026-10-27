param(
    [string]$BackupPath = "",
    [switch]$SkipElevation,
    [switch]$NoLaunch,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) { Write-Host "[*] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Err([string]$Message) { Write-Host "[-] $Message" -ForegroundColor Red }

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $SkipElevation -and -not (Test-Admin)) {
    Write-Step "需要管理员权限，正在重新启动恢复程序..."
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    if ($BackupPath) { $argList += @("-BackupPath", "`"$BackupPath`"") }
    if ($NoLaunch) { $argList += "-NoLaunch" }
    if ($NoPause) { $argList += "-NoPause" }
    try {
        Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList
    } catch {
        Write-Err "无法获取管理员权限：$($_.Exception.Message)"
        if (-not $NoPause) { Read-Host "按回车退出" | Out-Null }
    }
    exit
}

try {
    Write-Host ""
    Write-Host "Docker Desktop 汉化恢复程序" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor DarkGray

    $backupRoot = Join-Path $env:LOCALAPPDATA "DockerDesktop-CN\backup"
    if ($BackupPath) {
        if (-not (Test-Path $BackupPath)) { throw "备份目录不存在：$BackupPath" }
        $BackupPath = (Resolve-Path -Path $BackupPath).Path
    } else {
        if (-not (Test-Path $backupRoot)) { throw "没有找到任何备份，无需恢复。" }
        $backups = @(Get-ChildItem -Path $backupRoot -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName "install-path.txt")
        } | Sort-Object Name -Descending)
        if ($backups.Count -eq 0) { throw "没有找到任何有效备份，无需恢复。" }

        Write-Host "检测到以下备份：" -ForegroundColor Yellow
        for ($i = 0; $i -lt $backups.Count; $i++) {
            $pathFile = Join-Path $backups[$i].FullName "install-path.txt"
            $installPath = (Get-Content -Path $pathFile -Raw).Trim()
            Write-Host ("  [{0}] {1}  ->  {2}" -f ($i + 1), $backups[$i].Name, $installPath)
        }
        $choice = Read-Host "请选择要恢复的备份编号（直接回车选择最新）"
        if (-not $choice) { $choice = "1" }
        $index = 0
        if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $backups.Count) {
            throw "无效的选择：$choice"
        }
        $BackupPath = $backups[$index - 1].FullName
    }

    $pathFile = Join-Path $BackupPath "install-path.txt"
    if (-not (Test-Path $pathFile)) { throw "备份目录缺少 install-path.txt：$BackupPath" }
    $InstallRoot = (Get-Content -Path $pathFile -Raw).Trim()
    if (-not (Test-Path $InstallRoot)) { throw "原安装目录已不存在：$InstallRoot" }

    $resourcesDir = Join-Path $InstallRoot "frontend\resources"
    $asarPath = Join-Path $resourcesDir "app.asar"
    $unpackedPath = Join-Path $resourcesDir "app.asar.unpacked"
    $exePath = Join-Path $InstallRoot "frontend\Docker Desktop.exe"

    $backupAsar = Join-Path $BackupPath "app.asar"
    $backupExe = Join-Path $BackupPath "Docker Desktop.exe"
    $backupUnpacked = Join-Path $BackupPath "app.asar.unpacked"

    if (-not (Test-Path $backupAsar)) { throw "备份中缺少 app.asar：$BackupPath" }
    if (-not (Test-Path $backupExe)) { throw "备份中缺少 Docker Desktop.exe：$BackupPath" }

    Write-Step "恢复目录：$InstallRoot"
    Write-Step "使用备份：$BackupPath"

    $running = @(Get-Process -Name "Docker Desktop", "com.docker.backend", "com.docker.build", "com.docker.dev-envs" -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        Write-Step "正在关闭 Docker Desktop..."
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }

    Write-Step "正在恢复 app.asar..."
    Copy-Item -Path $backupAsar -Destination $asarPath -Force

    if (Test-Path $backupUnpacked) {
        Write-Step "正在恢复 app.asar.unpacked..."
        if (Test-Path $unpackedPath) { Remove-Item -Path $unpackedPath -Recurse -Force }
        Copy-Item -Path $backupUnpacked -Destination $unpackedPath -Recurse -Force
    } elseif (Test-Path $unpackedPath) {
        Remove-Item -Path $unpackedPath -Recurse -Force
    }

    Write-Step "正在恢复 Docker Desktop.exe..."
    Copy-Item -Path $backupExe -Destination $exePath -Force

    Write-Ok "恢复完成！"

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
