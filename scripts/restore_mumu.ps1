<#
.SYNOPSIS
    回滚 MuMu 去广告改动：重新启用 com.mumu.store 及其组件、还原桌面数据库、移除开机脚本。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File restore_mumu.ps1 -BackupDir "$env:USERPROFILE\MuMuBackup\manual-20260804-120000"
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File restore_mumu.ps1 -OnlyReEnable   # 只重新启用商店，不动数据库
#>
[CmdletBinding()]
param(
    [string]$BackupDir,
    [string]$InstallDir,
    [string]$Device,
    [string]$Adb,
    [switch]$OnlyReEnable,
    [switch]$RemoveBootScript
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib_mumu.ps1')

Write-Host '=== MuMu 去广告回滚 ===' -ForegroundColor Magenta

if (-not $InstallDir) { $InstallDir = Find-MuMuInstallDir }
if (-not $Adb) { $Adb = Find-MuMuAdb -InstallDir $InstallDir }
if (-not $Adb) { throw '未找到 adb.exe，请用 -Adb 指定。' }
if (-not $Device) { $Device = Connect-MuMuAdb -Adb $Adb -CandidatePorts (Find-MuMuAdbPort) }
Write-Ok "已连接: $Device"
$null = Enable-AdbRoot -Adb $Adb -Device $Device

# 1. 重新启用商店与组件
Write-Step '重新启用 com.mumu.store ...'
$null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'pm enable com.mumu.store'
foreach ($c in @(
    'com.mumu.store/.widget.appWidgetProvider.AdBannerWidgetProvider',
    'com.mumu.store/.widget.appWidgetProvider.DailyDiscoveryWidgetProvider',
    'com.mumu.store/.widget.appWidgetProvider.HotActivityWidgetProvider',
    'com.mumu.store/.widget.appWidgetProvider.FlashSaleWidgetProvider',
    'com.mumu.store/.widget.receiver.WidgetOperateReceiver')) {
    $null = Invoke-AdbShell -Adb $Adb -Device $Device -Command "pm enable $c"
}
Write-Ok '商店包与广告组件已恢复启用'

# 2. 移除开机脚本
if ($RemoveBootScript) {
    $null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'rm -f /data/adb/service.d/99-hide-mumu-lawnchair-search.sh'
    Write-Ok '已移除 /data/adb/service.d/99-hide-mumu-lawnchair-search.sh'
}

if ($OnlyReEnable) { Write-Host '=== 完成（仅重新启用）===' -ForegroundColor Magenta; exit 0 }

# 3. 还原数据库
if (-not $BackupDir) { Write-Warn2 '未提供 -BackupDir，跳过数据库还原'; exit 0 }
$bak = Get-ChildItem -Path $BackupDir -Filter 'launcher*.db.bak' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $bak) { Write-Warn2 "备份目录中没有 launcher*.db.bak：$BackupDir"; exit 0 }

$db = Get-LauncherDbPath -Adb $Adb -Device $Device
if (-not $db) { Write-Warn2 '设备端未找到 launcher 数据库，跳过还原'; exit 0 }

Write-Step "还原数据库 -> $db"
$null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'am force-stop app.lawnchair'
$null = Invoke-Adb -Adb $Adb -Device $Device -ArgList @('push', $bak.FullName, '/data/local/tmp/launcher_restore.db')
$owner = (Invoke-AdbShell -Adb $Adb -Device $Device -Command "stat -c %u:%g $db") -join ''
$null = Invoke-AdbShell -Adb $Adb -Device $Device -Command "cp /data/local/tmp/launcher_restore.db $db && chmod 660 $db && chown $owner $db"
$null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'input keyevent 3'
Write-Ok '数据库已还原，桌面已重启'
Write-Host '=== 完成 ===' -ForegroundColor Magenta
