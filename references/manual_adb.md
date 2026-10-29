# 手动执行流程与排错（脚本不可用时的备用路径）

以下命令均在 **Windows PowerShell** 中执行。示例安装目录 `D:\Program Files\Netease\MuMu\`，
设备地址示例 `192.168.31.222:5555`，请自行替换。

## 0. 前置

- 模拟器设置中开启 **ADB / 远程调试**（部分版本叫“网络调试”），记下 IP 与端口
- 需要 root 操作的，先在设置里开启 **ROOT**

## 1. 连接

```powershell
$adb = "D:\Program Files\Netease\MuMu\nx_main\adb.exe"
$dev = "192.168.31.222:5555"
& $adb connect $dev
& $adb -s $dev devices
& $adb -s $dev root          # 需要 root 时
Start-Sleep -Seconds 2
& $adb connect $dev
& $adb -s $dev shell id -u   # 返回 0 表示 root 成功
```

端口探测（不知道端口时）：

```powershell
Get-NetTCPConnection -State Listen |
  ForEach-Object { $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                   if ($p -and $p.ProcessName -match 'MuMu|NxDevice|NxMain') { $_.LocalPort } } |
  Select-Object -Unique
```

MuMu 多开端口规律：`16384 + index*32`；老版本常见 `7555`。

## 2. 备份

```powershell
$bak = "D:\backup\manual-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Force $bak | Out-Null
& $adb -s $dev pull /data/data/app.lawnchair/databases/launcher_4_7_6_1.db "$bak\launcher_4_7_6_1.db.bak"
& $adb -s $dev pull /data/data/app.lawnchair/shared_prefs/com.android.launcher3.prefs.xml "$bak\com.android.launcher3.prefs.xml.bak"
```

## 3. 查看广告项

```powershell
& $adb -s $dev shell "sqlite3 /data/data/app.lawnchair/databases/launcher_4_7_6_1.db 'SELECT _id,title,appWidgetProvider,intent FROM favorites ORDER BY _id;'"
```

典型输出：

```
9||com.mumu.store/com.mumu.store.widget.appWidgetProvider.AdBannerWidgetProvider|
10||com.mumu.store/com.mumu.store.widget.appWidgetProvider.DailyDiscoveryWidgetProvider|
11|游戏中心||#Intent;...component=com.mumu.store/.MainActivity;end
```

## 4. 关闭搜索推广栏 + 停止桌面

```powershell
& $adb -s $dev shell "setprop nemud.player_engine WOAPRO; am force-stop app.lawnchair; input keyevent HOME"
```

## 5. 禁用广告来源

保留小工具（推荐）：

```powershell
& $adb -s $dev shell pm disable com.mumu.store/.widget.appWidgetProvider.AdBannerWidgetProvider
& $adb -s $dev shell pm disable com.mumu.store/.widget.appWidgetProvider.DailyDiscoveryWidgetProvider
& $adb -s $dev shell pm disable com.mumu.store/.widget.appWidgetProvider.HotActivityWidgetProvider
& $adb -s $dev shell pm disable com.mumu.store/.widget.appWidgetProvider.FlashSaleWidgetProvider
& $adb -s $dev shell pm disable com.mumu.store/.widget.receiver.WidgetOperateReceiver
```

彻底去广告（小工具下载入口会失效）：

```powershell
& $adb -s $dev shell pm disable-user --user 0 com.mumu.store
```

> 提示：执行彻底方案前，先把谷歌安装器、RE 管理器下载安装好。

## 6. 清理桌面数据库

SQL 文件方式可避免 PowerShell 引号问题：

```powershell
@'
DELETE FROM favorites
WHERE appWidgetProvider LIKE 'com.mumu.store/%'
   OR intent LIKE '%component=com.mumu.store/.MainActivity%';
'@ | Set-Content -Encoding ASCII "$bak\remove_mumu_launcher_ads.sql"

& $adb -s $dev push "$bak\remove_mumu_launcher_ads.sql" /data/local/tmp/remove_mumu_launcher_ads.sql
& $adb -s $dev shell "sqlite3 /data/data/app.lawnchair/databases/launcher_4_7_6_1.db '.read /data/local/tmp/remove_mumu_launcher_ads.sql'"
```

设备无 `sqlite3` 时（部分 Android 15 镜像）：pull 到本机，用 Python 修改后 push 回去。

```powershell
& $adb -s $dev pull /data/data/app.lawnchair/databases/launcher_4_7_6_1.db "$bak\launcher.db"
python -c "import sqlite3;c=sqlite3.connect(r'$bak\launcher.db');c.execute(\"DELETE FROM favorites WHERE appWidgetProvider LIKE 'com.mumu.store/%' OR intent LIKE '%component=com.mumu.store/%'\");c.commit();c.close()"
$owner = (& $adb -s $dev shell "stat -c %u:%g /data/data/app.lawnchair/databases/launcher_4_7_6_1.db")
& $adb -s $dev push "$bak\launcher.db" /data/local/tmp/launcher_clean.db
& $adb -s $dev shell "cp /data/local/tmp/launcher_clean.db /data/data/app.lawnchair/databases/launcher_4_7_6_1.db && chmod 660 /data/data/app.lawnchair/databases/launcher_4_7_6_1.db && chown $owner /data/data/app.lawnchair/databases/launcher_4_7_6_1.db"
```

## 7. 重启桌面

```powershell
& $adb -s $dev shell am force-stop app.lawnchair
& $adb -s $dev shell input keyevent 3
Start-Sleep -Seconds 3
# 没回桌面时：
& $adb -s $dev shell am start -a android.intent.action.MAIN -c android.intent.category.HOME
```

## 8. 验证

```powershell
& $adb -s $dev shell pm list packages -d                       # 应能看到 com.mumu.store（Full 模式）
& $adb -s $dev shell "sqlite3 /data/data/app.lawnchair/databases/launcher_4_7_6_1.db 'SELECT _id,title,appWidgetProvider FROM favorites ORDER BY _id;'"
& $adb -s $dev shell uiautomator dump /sdcard/ui_check.xml
& $adb -s $dev pull /sdcard/ui_check.xml "$bak\ui_check.xml"
Select-String -Path "$bak\ui_check.xml" -Pattern "广告轮播|每日新发现|游戏中心|searchAdListView|com.mumu.store"
```

无输出即表示界面已无广告元素。处理后常见残留：搜索框仍在，但只显示普通占位“搜索游戏和应用”。

## 9. 恢复

```powershell
& $adb -s $dev shell am force-stop app.lawnchair
& $adb -s $dev push "$bak\launcher_4_7_6_1.db.bak" /data/local/tmp/launcher_4_7_6_1.db
& $adb -s $dev shell "cp /data/local/tmp/launcher_4_7_6_1.db /data/data/app.lawnchair/databases/launcher_4_7_6_1.db && chown u0_a18:u0_a18 /data/data/app.lawnchair/databases/launcher_4_7_6_1.db && chmod 660 /data/data/app.lawnchair/databases/launcher_4_7_6_1.db"
& $adb -s $dev shell pm enable com.mumu.store
& $adb -s $dev shell input keyevent 3
```

还原时的 owner（`u0_a18:u0_a18`）以实际 `stat -c %u:%g` 输出为准。

## 10. 排错

| 现象 | 原因 / 处理 |
|------|-------------|
| `adb connect` 后 offline | 模拟器未授权调试；重启模拟器或撤销 USB 调试授权后重连 |
| `pm disable` 报 `SecurityException` / 不生效 | 未获得 root，执行 `adb root` 后重连再试 |
| `sqlite3: not found` | 改用本机 Python 修改后回传（见第 6 节） |
| 桌面数据库名对不上 | 用 `ls /data/user/0/app.lawnchair/databases/` 查看实际文件名 |
| 重启模拟器后搜索栏又出现 | `nemud.player_engine` 是运行时属性，需刷模块或写 `service.d` 持久化 |
| 刷模块报解压错误 | Magisk 版本过旧，换 v30.7+ |
| 广告清理后桌面图标残留空白 | 再跑一次数据库清理 + `am force-stop app.lawnchair` |
| 模拟器更新后改动失效 | 重新执行清理；rcc 美化需重新替换备份文件 |
