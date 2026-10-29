<#
.SYNOPSIS
    只读探测 MuMu 模拟器环境：安装目录、adb 路径、Android 镜像版本、ADB 端口、root 状态、launcher 数据库路径。
    不做任何修改，可安全运行。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File detect_mumu.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File detect_mumu.ps1 -Device 127.0.0.1:16384
#>
[CmdletBinding()]
param(
    [string]$InstallDir,
    [string]$Device,
    [string]$Adb
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib_mumu.ps1')

Write-Host '=== MuMu 环境探测（只读）===' -ForegroundColor Magenta

if (-not $InstallDir) { $InstallDir = Find-MuMuInstallDir }
if ($InstallDir) { Write-Host "[OK] 安装目录   : $InstallDir" -ForegroundColor Green }
else             { Write-Host '[!] 安装目录   : 未探测到（可用 -InstallDir 指定）' -ForegroundColor Yellow }

if (-not $Adb) { $Adb = Find-MuMuAdb -InstallDir $InstallDir }
if ($Adb) { Write-Host "[OK] adb        : $Adb" -ForegroundColor Green }
else      { Write-Host '[x] adb        : 未找到（安装 platform-tools 或用 -Adb 指定）' -ForegroundColor Red }

$ver = Get-MuMuAndroidVersion -InstallDir $InstallDir
if ($ver) { Write-Host "[OK] 镜像版本   : Android $ver" -ForegroundColor Green }
else      { Write-Host '[!] 镜像版本   : 未探测到' -ForegroundColor Yellow }

$startupJson = Join-Path $env:APPDATA 'Netease\MuMuPlayer\data\startupImage\imageManager.json'
if (Test-Path $startupJson) {
    $ro = ((Get-ItemProperty $startupJson).Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0
    if ($ro) { Write-Host "[OK] 开屏广告   : 索引已只读（已屏蔽） - $startupJson" -ForegroundColor Green }
    else     { Write-Host "[!] 开屏广告   : 索引可写（未屏蔽） - $startupJson" -ForegroundColor Yellow }
} else {
    Write-Host "[!] 开屏广告   : 索引文件不存在，模拟器尚未冷启动过 - $startupJson" -ForegroundColor Yellow
}

if (-not $Adb) { Write-Host '=== 无 adb，跳过设备探测 ===' -ForegroundColor Magenta; exit 0 }

try {
    $ports = Find-MuMuAdbPort
    Write-Host "[*] 候选端口   : $($ports -join ', ')"
    if (-not $Device) { $Device = Connect-MuMuAdb -Adb $Adb -CandidatePorts $ports }
    Write-Host "[OK] 已连接设备: $Device" -ForegroundColor Green
} catch {
    Write-Host "[x] 设备连接   : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$model  = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'getprop ro.product.model') -join ''
$sdk    = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'getprop ro.build.version.sdk') -join ''
$rel    = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'getprop ro.build.version.release') -join ''
Write-Host "[OK] 设备       : $model / Android $rel (SDK $sdk)" -ForegroundColor Green

$uid = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'id -u') -join ''
if ($uid -match '^\s*0\s*$') { Write-Host '[OK] shell      : root' -ForegroundColor Green }
else {
    Write-Host "[!] shell      : 非 root (uid=$uid)，尝试 adb root ..." -ForegroundColor Yellow
    if (Enable-AdbRoot -Adb $Adb -Device $Device) { Write-Host '[OK] shell      : 已提权为 root' -ForegroundColor Green }
    else { Write-Host '[!] shell      : 仍非 root，pm disable / 数据库写入会受限' -ForegroundColor Yellow }
}

$prop = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'getprop nemud.player_engine') -join ''
if ($prop -eq 'WOAPRO') { Write-Host '[OK] 搜索栏属性 : nemud.player_engine=WOAPRO（推广栏已关闭）' -ForegroundColor Green }
else { Write-Host "[!] 搜索栏属性 : nemud.player_engine='$prop'（默认环境，推广栏会出现）" -ForegroundColor Yellow }

$store = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'pm list packages -d') -join "`n"
if ($store -match 'com\.mumu\.store') { Write-Host '[OK] 广告来源包 : com.mumu.store 已禁用' -ForegroundColor Green }
else { Write-Host '[!] 广告来源包 : com.mumu.store 处于启用状态' -ForegroundColor Yellow }

$db = Get-LauncherDbPath -Adb $Adb -Device $Device
if ($db) {
    Write-Host "[OK] 桌面数据库 : $db" -ForegroundColor Green
    $rows = (Invoke-AdbShell -Adb $Adb -Device $Device -Command "sqlite3 $db 'SELECT _id,title,appWidgetProvider FROM favorites ORDER BY _id;'") -join "`n"
    if ($rows) {
        Write-Host '--- favorites 表 ---'
        Write-Host $rows
        if ($rows -match 'AdBanner|DailyDiscovery|mumu\.store') { Write-Host '[!] 数据库中存在广告项' -ForegroundColor Yellow }
        else { Write-Host '[OK] 数据库无广告项' -ForegroundColor Green }
    }
} else {
    Write-Host '[!] 桌面数据库 : 未找到 app.lawnchair 的 launcher 数据库' -ForegroundColor Yellow
}

Write-Host '=== 探测结束 ===' -ForegroundColor Magenta
