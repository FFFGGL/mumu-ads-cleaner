<#
.SYNOPSIS
    清理 MuMu 模拟器桌面广告（顶部搜索推广栏、广告轮播 Widget、每日新发现、游戏中心图标、启动弹窗）。

.DESCRIPTION
    通过 ADB 完成：备份桌面数据库 -> 关闭 MuMu 搜索推广栏（nemud.player_engine=WOAPRO）
    -> 禁用 com.mumu.store 的广告组件（或整个包）-> 清理 Lawnchair favorites 表 -> 重启桌面 -> 验证。

    -Mode Component（默认）：只禁用广告组件，保留 com.mumu.store 主包，
        “小工具”里的谷歌安装器、RE 文件管理器、应用商店下载入口仍可用。
    -Mode Full：pm disable-user 整个 com.mumu.store，去广告最彻底，但小工具下载入口失效。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File clean_launcher_ads.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File clean_launcher_ads.ps1 -Device 192.168.31.222:5555 -Mode Full
#>
[CmdletBinding()]
param(
    [string]$InstallDir,
    [string]$Device,
    [string]$Adb,
    [string]$BackupDir,
    [ValidateSet('Component','Full')][string]$Mode = 'Component',
    [switch]$SkipBackup,
    [switch]$Persist,          # root 时写入 /data/adb/service.d 开机脚本（需 Magisk/KernelSU）
    [string]$Python = 'python'
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib_mumu.ps1')

Write-Host '=== MuMu 桌面广告清理 ===' -ForegroundColor Magenta

# --- 1. 环境 ---
if (-not $InstallDir) { $InstallDir = Find-MuMuInstallDir }
if ($InstallDir) { Write-Step "模拟器目录: $InstallDir" } else { Write-Warn2 '未自动定位到模拟器目录（不影响 ADB 方案）' }

if (-not $Adb) { $Adb = Find-MuMuAdb -InstallDir $InstallDir }
if (-not $Adb) { throw '未找到 adb.exe。请安装 platform-tools 或用 -Adb 指定路径。' }
Write-Step "adb: $Adb"

$ver = Get-MuMuAndroidVersion -InstallDir $InstallDir
if ($ver) { Write-Step "检测到 Android 镜像版本: $ver" }

if (-not $Device) {
    $Device = Connect-MuMuAdb -Adb $Adb -CandidatePorts (Find-MuMuAdbPort)
}
Write-Ok "已连接设备: $Device"

# --- 2. root ---
Write-Step '获取 root 权限...'
$isRoot = Enable-AdbRoot -Adb $Adb -Device $Device
if ($isRoot) { Write-Ok 'shell 已具备 root 权限' } else { Write-Warn2 '未获得 root：组件禁用(pm disable)可能失败，数据库清理也可能受限' }

# --- 3. 备份 ---
if (-not $BackupDir) { $BackupDir = Join-Path (Join-Path $env:USERPROFILE 'MuMuBackup') ("manual-" + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
if (-not $SkipBackup) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    Write-Step "备份到: $BackupDir"
    $db = Get-LauncherDbPath -Adb $Adb -Device $Device
    if ($db) {
        $localName = (Split-Path $db -Leaf) + '.bak'
        $null = Invoke-Adb -Adb $Adb -Device $Device -ArgList @('pull', $db, (Join-Path $BackupDir $localName))
        Write-Ok "数据库已备份: $localName"
    } else { Write-Warn2 '未找到 launcher 数据库，跳过数据库备份' }
    $null = Invoke-Adb -Adb $Adb -Device $Device -ArgList @('pull', '/data/data/app.lawnchair/shared_prefs/com.android.launcher3.prefs.xml', (Join-Path $BackupDir 'com.android.launcher3.prefs.xml.bak'))
}

# --- 4. 关闭 MuMu 搜索推广栏 ---
Write-Step '设置 nemud.player_engine=WOAPRO（关闭顶部搜索推广栏）...'
$rp = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'command -v resetprop || echo NONE') -join ''
if ($rp -match 'resetprop' -and $rp -notmatch 'NONE') {
    $null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'resetprop nemud.player_engine WOAPRO'
} else {
    $null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'setprop nemud.player_engine WOAPRO'
}
$cur = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'getprop nemud.player_engine') -join ''
Write-Step "当前属性值: $cur（若为 WOAPRO 生效；重启模拟器后会恢复，需 -Persist 或刷 KernelSU/Magisk 模块）"

# --- 5. 停止桌面/商店 ---
$null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'am force-stop app.lawnchair'
$null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'am force-stop com.mumu.store'

# --- 6. 禁用广告来源 ---
if ($Mode -eq 'Full') {
    Write-Step 'Mode=Full：禁用整个 com.mumu.store ...'
    $r = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'pm disable-user --user 0 com.mumu.store') -join "`n"
    Write-Host $r
} else {
    Write-Step 'Mode=Component：仅禁用广告组件，保留商店主包 ...'
    $components = @(
        'com.mumu.store/.widget.appWidgetProvider.AdBannerWidgetProvider',
        'com.mumu.store/.widget.appWidgetProvider.DailyDiscoveryWidgetProvider',
        'com.mumu.store/.widget.appWidgetProvider.HotActivityWidgetProvider',
        'com.mumu.store/.widget.appWidgetProvider.FlashSaleWidgetProvider',
        'com.mumu.store/.widget.receiver.WidgetOperateReceiver'
    )
    foreach ($c in $components) {
        $r = (Invoke-AdbShell -Adb $Adb -Device $Device -Command "pm disable $c") -join ''
        Write-Host ('   ' + $c.Split('/')[-1] + ' -> ' + $r)
    }
}

# --- 7. 清理桌面数据库 ---
Write-Step '清理 Lawnchair 桌面数据库 ...'
$db = Get-LauncherDbPath -Adb $Adb -Device $Device
if (-not $db) {
    Write-Warn2 '未找到 launcher 数据库，跳过'
} else {
    Write-Step "数据库: $db"
    $hasSqlite3 = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'test -x /system/bin/sqlite3 && echo YES') -join ''
    $sqlLocal = Join-Path $PSScriptRoot '..\assets\remove_ads.sql'
    $null = Invoke-Adb -Adb $Adb -Device $Device -ArgList @('push', $sqlLocal, '/data/local/tmp/remove_ads.sql')
    if ($hasSqlite3 -match 'YES') {
        $null = Invoke-AdbShell -Adb $Adb -Device $Device -Command "sqlite3 $db '.read /data/local/tmp/remove_ads.sql'"
        Write-Ok '已在设备端执行清理 SQL'
    } else {
        Write-Warn2 '设备端无 sqlite3，改用本地 Python 处理（pull -> 改 -> push）'
        $tmpDb = Join-Path $env:TEMP 'launcher_mumu.db'
        $null = Invoke-Adb -Adb $Adb -Device $Device -ArgList @('pull', $db, $tmpDb)
        $pyFile = Join-Path $env:TEMP 'mumu_db_clean.py'
        @'
import sqlite3, sys
p = sys.argv[1]
con = sqlite3.connect(p)
cur = con.cursor()
cur.execute("DELETE FROM favorites WHERE appWidgetProvider LIKE 'com.mumu.store/%' OR intent LIKE '%component=com.mumu.store/%'")
con.commit()
for row in cur.execute("SELECT _id,title,appWidgetProvider FROM favorites ORDER BY _id"):
    print(row)
con.close()
'@ | Set-Content -Encoding ASCII $pyFile
        & $Python $pyFile $tmpDb
        $null = Invoke-Adb -Adb $Adb -Device $Device -ArgList @('push', $tmpDb, '/data/local/tmp/launcher_clean.db')
        $owner = (Invoke-AdbShell -Adb $Adb -Device $Device -Command "stat -c %u:%g $db") -join ''
        $null = Invoke-AdbShell -Adb $Adb -Device $Device -Command "cp /data/local/tmp/launcher_clean.db $db && chmod 660 $db && chown $owner $db"
        Write-Ok '数据库已回传并修复权限'
    }
}

# --- 8. 可选：持久化开机脚本 ---
if ($Persist -and $isRoot) {
    Write-Step '写入 /data/adb/service.d/99-hide-mumu-lawnchair-search.sh ...'
    $sh = @'
#!/system/bin/sh
# 由 mumu-ads-cleaner skill 生成：开机自动去广告
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
i=0
while [ $i -lt 20 ]; do
  resetprop nemud.player_engine WOAPRO 2>/dev/null || setprop nemud.player_engine WOAPRO
  i=$((i+1)); sleep 3
done &
for c in AdBannerWidgetProvider DailyDiscoveryWidgetProvider HotActivityWidgetProvider FlashSaleWidgetProvider; do
  pm disable com.mumu.store/.widget.appWidgetProvider.$c >/dev/null 2>&1
done
pm disable com.mumu.store/.widget.receiver.WidgetOperateReceiver >/dev/null 2>&1
for d in /data/user/0/app.lawnchair/databases/launcher*.db; do
  [ -f "$d" ] && /system/bin/sqlite3 "$d" "DELETE FROM favorites WHERE appWidgetProvider LIKE 'com.mumu.store/%' OR intent LIKE '%component=com.mumu.store/%';"
done
am force-stop app.lawnchair
sleep 1
input keyevent 3
'@
    $shLocal = Join-Path $env:TEMP '99-hide-mumu-lawnchair-search.sh'
    $sh.Replace("`r`n","`n") | Set-Content -Encoding ASCII $shLocal -NoNewline
    $null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'mkdir -p /data/adb/service.d'
    $null = Invoke-Adb -Adb $Adb -Device $Device -ArgList @('push', $shLocal, '/data/adb/service.d/99-hide-mumu-lawnchair-search.sh')
    $null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'chmod 0755 /data/adb/service.d/99-hide-mumu-lawnchair-search.sh'
    Write-Ok '开机脚本已写入（需 Magisk/KernelSU 环境才会执行）'
}

# --- 9. 重启桌面 ---
Write-Step '重启桌面 ...'
$null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'am force-stop app.lawnchair'
Start-Sleep -Seconds 2
$null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'input keyevent 3'
Start-Sleep -Seconds 3

# --- 10. 验证 ---
Write-Host '=== 验证 ===' -ForegroundColor Magenta
$rows = ''
if ($db) { $rows = (Invoke-AdbShell -Adb $Adb -Device $Device -Command "sqlite3 $db 'SELECT _id,title,appWidgetProvider FROM favorites ORDER BY _id;'") -join "`n" }
if ($rows) {
    Write-Host 'favorites 表现状：'
    Write-Host $rows
    if ($rows -match 'AdBanner|DailyDiscovery|mumu.store') { Write-Warn2 '数据库中仍存在广告项' } else { Write-Ok '数据库已无广告项' }
}
$disabled = (Invoke-AdbShell -Adb $Adb -Device $Device -Command 'pm list packages -d') -join "`n"
if ($disabled -match 'com.mumu.store') { Write-Ok 'com.mumu.store 已处于禁用状态' }

$null = Invoke-AdbShell -Adb $Adb -Device $Device -Command 'uiautomator dump /sdcard/ui_check.xml'
$uiLocal = Join-Path $BackupDir 'ui_check.xml'
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }
$null = Invoke-Adb -Adb $Adb -Device $Device -ArgList @('pull', '/sdcard/ui_check.xml', $uiLocal)
if (Test-Path $uiLocal) {
    $hit = Select-String -Path $uiLocal -Pattern '广告轮播|每日新发现|游戏中心|searchAdListView|com.mumu.store' -ErrorAction SilentlyContinue
    if ($hit) { Write-Warn2 ('界面仍匹配到：' + (($hit | Select-Object -First 5) -join ' | ')) } else { Write-Ok '界面未检测到广告元素' }
}

Write-Host '=== 完成 ===' -ForegroundColor Magenta
Write-Host "备份目录: $BackupDir"
Write-Host '提示：nemud.player_engine 为运行时属性，重启模拟器后会恢复；需要持久化请使用 -Persist 或刷入 KernelSU/Magisk 模块（build_ksu_module.py）。'
