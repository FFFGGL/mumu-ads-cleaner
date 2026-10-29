# lib_mumu.ps1 — MuMu 模拟器环境探测与 ADB 公共函数库
# 用法： . "$PSScriptRoot\lib_mumu.ps1"   （dot-source 后调用其中的函数）
# 依赖：Windows PowerShell 5.1+ / PowerShell 7，模拟器运行时需要开启 ADB 调试（设置 -> 开发者/ADB）

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# ---------------- 安装目录探测 ----------------
function Find-MuMuInstallDir {
    [CmdletBinding()]
    param([string[]]$ExtraCandidate = @())

    $cand = @()
    if ($ExtraCandidate) { $cand += $ExtraCandidate }

    # 1) 注册表卸载项（32/64 位）
    $regPaths = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($rp in $regPaths) {
        try {
            Get-ItemProperty $rp -ErrorAction SilentlyContinue |
                Where-Object { ($_.DisplayName -like '*MuMu*') -and $_.InstallLocation } |
                ForEach-Object { $cand += $_.InstallLocation }
        } catch {}
    }

    # 2) 运行中的进程
    try {
        Get-Process -Name 'MuMuNxDevice','MuMuPlayer','MuMuNxMain','MuMu' -ErrorAction SilentlyContinue |
            ForEach-Object { try { $cand += (Split-Path $_.Path -Parent) } catch {} }
    } catch {}

    # 3) 常见安装位置
    foreach ($drive in @('C','D','E','F','G')) {
        $cand += @(
            "${drive}:\Program Files\Netease\MuMu",
            "${drive}:\Program Files\Netease\MuMuPlayer",
            "${drive}:\Program Files (x86)\Netease\MuMu",
            "${drive}:\Netease\MuMu",
            "${drive}:\MuMu",
            "${drive}:\Program Files\MuMu"
        )
    }

    $root = $null
    foreach ($c in ($cand | Where-Object { $_ } | Select-Object -Unique)) {
        try {
            $p = $c.TrimEnd('\')
            if (Test-Path (Join-Path $p 'nx_main')) { $root = $p; break }
            if (Test-Path (Join-Path $p 'nx_device')) { $root = $p; break }
            # 进程路径可能直接指向 nx_main 子目录
            if ((Split-Path $p -Leaf) -ieq 'nx_main') { $root = (Split-Path $p -Parent); break }
        } catch {}
    }
    return $root
}

# ---------------- adb 可执行文件 ----------------
function Find-MuMuAdb {
    param([string]$InstallDir)

    if ($InstallDir) {
        $p = Join-Path $InstallDir 'nx_main\adb.exe'
        if (Test-Path $p) { return (Resolve-Path $p).Path }
        $p = Join-Path $InstallDir 'adb.exe'
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }
    # 环境变量 adb
    $cmd = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    #  scoop / 常见位置
    foreach ($p in @("$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
                     "$env:USERPROFILE\platform-tools\adb.exe",
                     "C:\platform-tools\adb.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# ---------------- Android 版本（12 / 15） ----------------
function Get-MuMuAndroidVersion {
    param([string]$InstallDir)
    if (-not $InstallDir) { return $null }
    $nx = Join-Path $InstallDir 'nx_device'
    if (-not (Test-Path $nx)) { return $null }
    $dirs = Get-ChildItem -Path $nx -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d' }
    $majors = $dirs | ForEach-Object { ($_.Name -split '\.')[0] } | Sort-Object -Descending -Unique
    if ($majors) { return ($majors -join ',') }
    return $null
}

# ---------------- ADB 端口探测 ----------------
function Find-MuMuAdbPort {
    param([hashtable]$NetstatHint)

    $ports = @()

    # 1) 从监听端口反查进程（MuMu 多开默认 16384 + index*32，老版本常见 7555）
    try {
        $conns = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
        foreach ($c in $conns) {
            if ($c.LocalPort -lt 1024 -and $c.LocalPort -ne 5555) { continue }
            try {
                $proc = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
            } catch { $proc = $null }
            if ($proc -and $proc.ProcessName -match 'MuMu|NxDevice|NxMain|adb|Nemu') {
                $ports += $c.LocalPort
            }
        }
    } catch {}

    # 2) 常见候选端口
    $ports += @(7555, 16384, 16416, 16448, 16480, 16512, 5555, 5557, 5565, 62001, 62025)
    return ($ports | Where-Object { $_ } | Select-Object -Unique)
}

# ---------------- 连接设备 ----------------
function Connect-MuMuAdb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Adb,
        [string]$Device,
        [int[]]$CandidatePorts
    )

    if ($Device) {
        & $Adb connect $Device | Out-Null
        $line = (& $Adb devices) -join "`n"
        if ($line -match [regex]::Escape(($Device -split ':')[0])) { return $Device }
        throw "无法连接设备 $Device 。请确认模拟器已启动且已开启 ADB 调试。`n$line"
    }

    if (-not $CandidatePorts -or $CandidatePorts.Count -eq 0) { $CandidatePorts = Find-MuMuAdbPort }
    foreach ($port in $CandidatePorts) {
        foreach ($h in @('127.0.0.1', 'localhost')) {
            $addr = ('{0}:{1}' -f $h, $port)
            $null = & $Adb connect $addr 2>$null
            $devs = (& $Adb devices) -join "`n"
            $esc = [regex]::Escape($addr)
            if (($devs -match $esc) -and ($devs -notmatch ($esc + '\s+offline'))) {
                if ($devs -match ($esc + '\s+device')) { return $addr }
            }
        }
    }
    throw "未找到可用的 ADB 设备。已尝试端口：$($CandidatePorts -join ', ')。请在模拟器设置中开启 ADB/远程调试后重试，或用 -Device <ip:port> 指定。"
}

# ---------------- 执行 adb 命令 ----------------
function Invoke-Adb {
    param(
        [Parameter(Mandatory)][string]$Adb,
        [string]$Device,
        [Parameter(Mandatory)][string[]]$ArgList
    )
    if ($Device) { $all = @('-s', $Device) + $ArgList } else { $all = $ArgList }
    $out = & $Adb @all 2>&1
    return $out
}

function Invoke-AdbShell {
    param(
        [Parameter(Mandatory)][string]$Adb,
        [string]$Device,
        [Parameter(Mandatory)][string]$Command
    )
    return (Invoke-Adb -Adb $Adb -Device $Device -ArgList @('shell', $Command))
}

# ---------------- 获取 root 权限 ----------------
function Enable-AdbRoot {
    param([Parameter(Mandatory)][string]$Adb, [string]$Device)

    $who = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'id -u') -join ''
    if ($who -match '^\s*0\s*$') { return $true }
    $null = Invoke-Adb -Adb $Adb -Device $Device -ArgList @('root')
    Start-Sleep -Seconds 3
    if ($Device) { $null = & $Adb connect $Device }
    Start-Sleep -Seconds 1
    $who = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'id -u') -join ''
    return ($who -match '^\s*0\s*$')
}

# ---------------- 定位 launcher 数据库 ----------------
function Get-LauncherDbPath {
    param([Parameter(Mandatory)][string]$Adb, [string]$Device)

    $candidates = @(
        '/data/data/app.lawnchair/databases/launcher_4_7_6_1.db',
        '/data/user/0/app.lawnchair/databases/launcher_4_7_6_1.db',
        '/data/data/app.lawnchair/databases/launcher_4_7_6.db',
        '/data/user/0/app.lawnchair/databases/launcher_4_7_6.db'
    )
    foreach ($c in $candidates) {
        $r = (Invoke-AdbShell -Adb $Adb -Device $Device -Command "test -f $c && echo OK") -join ''
        if ($r -match 'OK') { return $c }
    }
    # 通配查找
    $found = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'ls /data/user/0/app.lawnchair/databases/ 2>/dev/null') -join "`n"
    $m = [regex]::Match($found, 'launcher[\w\.]*\.db')
    if ($m.Success) { return "/data/user/0/app.lawnchair/databases/$($m.Value)" }
    return $null
}

# ---------------- 输出辅助 ----------------
function Write-Step { param([string]$Msg) Write-Host "[*] $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn2{ param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Err2 { param([string]$Msg) Write-Host "[x] $Msg" -ForegroundColor Red }
