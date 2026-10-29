<#
.SYNOPSIS
    屏蔽 MuMu 模拟器冷启动开屏广告（把广告索引 imageManager.json 设为只读，使其无法更新）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File block_startup_ad.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File block_startup_ad.ps1 -Undo   # 恢复（取消只读）
#>
[CmdletBinding()]
param(
    [string]$Path,
    [switch]$Undo
)

$ErrorActionPreference = 'Stop'
if (-not $Path) { $Path = Join-Path $env:APPDATA 'Netease\MuMuPlayer\data\startupImage\imageManager.json' }

$dir = Split-Path $Path -Parent
if (-not (Test-Path $dir)) {
    Write-Host "[!] 目录不存在：$dir" -ForegroundColor Yellow
    Write-Host '    说明：该目录由模拟器冷启动时创建。请先启动一次 MuMu 模拟器再运行本脚本。'
    $ans = Read-Host '    是否现在创建目录并写入空的只读索引？(y/N)'
    if ($ans -notmatch '^[yY]') { exit 1 }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    '{}' | Set-Content -Encoding ASCII $Path
}

if (-not (Test-Path $Path)) {
    '{}' | Set-Content -Encoding ASCII $Path
    Write-Host "[*] 索引文件不存在，已创建空索引：$Path"
}

if ($Undo) {
    attrib -R "$Path" | Out-Null
    Write-Host "[OK] 已取消只读：$Path （模拟器下次冷启动会重新拉取开屏广告）" -ForegroundColor Green
} else {
    attrib +R "$Path" | Out-Null
    $attr = (Get-ItemProperty -Path $Path).Attributes
    if ($attr -band [System.IO.FileAttributes]::ReadOnly) {
        Write-Host "[OK] 已设为只读：$Path" -ForegroundColor Green
        Write-Host '    开屏广告索引无法被更新，冷启动不再出现开屏广告。'
        Write-Host '    回滚：本脚本加 -Undo 参数。'
        Write-Host '    注意：模拟器升级/重装会重建该文件，届时需重新执行。'
    } else {
        Write-Host "[x] 设置只读失败，请检查权限或以管理员身份运行。" -ForegroundColor Red
        exit 2
    }
}
