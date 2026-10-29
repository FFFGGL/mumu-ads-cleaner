# MuMu 模拟器去广告 — 技术参考

来源于吾爱破解原帖《[原创工具] MuMu模拟器去广告+美化》（thread-2121262，作者 许我浅笑而安），
教程在 **V6.4.6** 完成、**V6.5.3** 测试有效，社区反馈 6.6.4 仍有效，其它版本需自测。

## 1. 三类广告与对应位置

| 广告 | 载体 | 关键位置 |
|------|------|----------|
| 冷启动开屏广告 | Windows 端下载型 campaign overlay | `%APPDATA%\Netease\MuMuPlayer\data\startupImage\imageManager.json` |
| 桌面顶部搜索/推广栏 | Android 系统属性 | 属性 `nemud.player_engine`（改为 `WOAPRO` 后不出现） |
| 桌面广告 Widget、每日发现、游戏中心图标 | `app.lawnchair` 桌面 SQLite | `/data/user/0/app.lawnchair/databases/launcher*.db` 的 `favorites` 表 |
| 启动弹窗广告、搜索框广告列表 | `com.mumu.store` 动态提供 | 不在数据库中，靠禁用包/组件消除 |
| 冷启动背景图、中心 LOGO、LOGO 文字 | Qt 资源包 | `<安装目录>\nx_device\<版本>\shell\rcc\NxDeviceResource.rcc` |

## 2. 关键标识

- 桌面包名：`app.lawnchair`（MuMu 定制 Lawnchair）
- 广告来源包名：`com.mumu.store`
- 桌面数据库：`/data/data/app.lawnchair/databases/launcher_4_7_6_1.db`
  - Android 15 实测也可能是 `launcher_4_7_6.db`；统一用 `launcher*.db` 通配
  - 等价路径：`/data/user/0/app.lawnchair/databases/launcher*.db`
- `favorites` 表中的广告项：

| _id | 内容 | 说明 |
|-----|------|------|
| 9 | `AdBannerWidgetProvider` | 大图广告轮播组件 |
| 10 | `DailyDiscoveryWidgetProvider` | 每日新发现 |
| 11 | 游戏中心 | intent 指向 `com.mumu.store/.MainActivity` |

- 干净状态参考（`_id` 1–8 + 12）：设置、图库、文件、浏览器、应用分身、小工具、RE文件管理器、谷歌安装器、KernelSU

### 需要禁用的组件（保留主包）

```
com.mumu.store/.widget.appWidgetProvider.AdBannerWidgetProvider
com.mumu.store/.widget.appWidgetProvider.DailyDiscoveryWidgetProvider
com.mumu.store/.widget.appWidgetProvider.HotActivityWidgetProvider
com.mumu.store/.widget.appWidgetProvider.FlashSaleWidgetProvider
com.mumu.store/.widget.receiver.WidgetOperateReceiver
```

保留 `com.mumu.store` 主包启用的原因：小工具里的**谷歌安装器**、**RE 文件管理器**以及应用商店下载入口依赖它。
若不需要这些工具，可直接 `pm disable-user --user 0 com.mumu.store`（`-Mode Full`）。

## 3. 属性与 root 方案

- `nemud.player_engine` 是运行时属性，`setprop` 后**重启模拟器即失效**；持久化要靠：
  - KernelSU / Magisk 模块（推荐，脚本 `build_ksu_module.py` 生成）
  - 或写入 `/data/adb/service.d/99-hide-mumu-lawnchair-search.sh`（需 Magisk/KernelSU 环境）
- `resetprop` 优先（KernelSU 在 `/data/adb/ksu/bin/resetprop`，Magisk 在 `/data/adb/magisk/resetprop`），
  不可用时退回 `setprop`
- Android 15 开启 ROOT 后自带 KernelSU；Android 12 需自行安装 Magisk。
  **旧版面具（25/26）安装模块会报解压错误，需 v30.7+**（参考 https://github.com/ayasa520/Magisk）

## 4. 开屏美化（可选，非去广告必需）

路径：

- Android 15：`<安装目录>\nx_device\15.0\shell\rcc\NxDeviceResource.rcc`
- Android 12：`<安装目录>\nx_device\12.0\shell\rcc\NxDeviceResource.rcc`

内部资源：

| 用途 | Android 15 | Android 12 |
|------|-----------|-----------|
| 横屏启动图 | `/resources/images/nx/device/jpeg/img_startup_landscape_15.jpeg` | `/resources/images/nx/device/jpeg/img_startup_landscape.jpeg` |
| 竖屏启动图 | `/resources/images/nx/device/jpeg/img_startup_vertical_15.jpeg` | `/resources/images/nx/device/jpeg/img_startup_vertical.jpeg` |
| 中心 LOGO | `/resources/images/nx/ic_white_logo.svg` | 同 |
| LOGO 下方文字 | `/resources/images/ic_mumu_name.svg` | 同 |

- 去 LOGO/文字：删除 `<svg></svg>` 标签内的内容（保留空 svg 标签）
- 左上角图标复用同一 LOGO 资源，改透明后左上角图标不显示属正常现象
- VIP 账号使用另一套资源，需自行搜索替换
- **模拟器更新会覆盖 rcc 文件，需备份改好的文件并在更新后重新替换**

## 5. 其它实用信息

- MuMu 离线安装包按组件下载接口：`https://api.mumu.nie.netease.com/api/v2/download/nx`
- 模拟器自带命令行：`nx_main\mumu-cli.exe`、`nx_main\adb.exe`
  - `mumu-cli.exe sh -v 0 -c '<shell 命令>'` 可直接对第 0 台设备执行 shell，无需先 `adb connect`
- 共享文件夹：一般在电脑“文档”目录，模拟器菜单内有路径提示；`download` 子目录用于 KernelSU/Magisk 选择模块

## 6. 风险与注意

- 修改前务必备份 `launcher*.db` 与 `com.android.launcher3.prefs.xml`（脚本默认自动备份）
- 还原数据库后必须修复权限：`chmod 660` + `chown` 为原 owner（脚本通过 `stat -c %u:%g` 自动获取）
- 桌面数据库名与组件名随版本变化，清理前先 `SELECT _id,title,appWidgetProvider,intent FROM favorites` 核对
- 模拟器大版本升级后所有改动可能失效，需重新执行
