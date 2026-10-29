---
name: mumu-ads-cleaner
description: 去除 MuMu 模拟器（网易 MuMu Player / MuMuNxDevice）的开屏广告与桌面广告，并可选美化冷启动画面。当用户提到 MuMu 模拟器广告、桌面顶部搜索推广栏、广告轮播 Widget、每日新发现、游戏中心图标、启动弹窗广告、Lawnchair 桌面清理、com.mumu.store 禁用，或要求对 MuMu 模拟器去广告 / 美化冷启动画面 / 回滚这些改动时使用。在 Windows 上通过 ADB 与 PowerShell 执行，支持 ROOT（KernelSU/Magisk 模块）与免 ROOT 两种方案。
---

# MuMu 模拟器去广告与美化

## 用途

处理 MuMu 模拟器（Windows）里的三类广告，并可选美化冷启动画面：

1. **冷启动开屏广告** — 把 Windows 端广告索引文件设为只读，使其无法更新。
2. **桌面广告** — 顶部搜索/推广栏、广告轮播 Widget、每日新发现、游戏中心图标、启动弹窗。
3. **冷启动画面美化** — 替换横/竖屏启动背景，去掉中心 LOGO 与文字（可选）。

核心原理、路径表、组件清单、版本差异见 `references/technical.md`；
脚本不可用时的完整手动命令流程与排错表见 `references/manual_adb.md`。

## 何时使用

用户请求形如：「MuMu 模拟器怎么去广告」「把 MuMu 桌面的游戏中心和每日发现去掉」
「模拟器开屏广告太烦」「MuMu 启动画面换成自定义壁纸」「把去广告的改动改回去」。

## 执行前先确认

动手前先确认两件事（若用户未说明，按默认假设继续并在结果中说明另一种做法）：

1. **模拟器 Android 版本**：12 还是 15（决定 Magisk 还是 KernelSU、数据库文件名）。可用探测脚本自动判断。
2. **是否愿意开启 ROOT**：
   - 愿意 → 走**模块方案**（开机自动生效，最省事）
   - 不愿意 / ROOT 失败 → 走 **ADB 方案**（重启模拟器后 `nemud.player_engine` 会失效，需重跑）

默认假设：Android 15 + 开启 ROOT。

## 工作流

### 步骤 0：环境探测

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.workbuddy\skills\mumu-ads-cleaner\scripts\detect_mumu.ps1"
```

输出模拟器安装目录、adb 路径、Android 镜像版本、可用 ADB 端口、root 状态、launcher 数据库路径。
探测失败时让用户在模拟器设置里开启「ADB / 远程调试」，并用 `-Device <ip:port>` 显式指定。

### 步骤 1：屏蔽开屏广告（无需 ROOT）

```powershell
powershell -ExecutionPolicy Bypass -File "...\scripts\block_startup_ad.ps1"
# 回滚：
powershell -ExecutionPolicy Bypass -File "...\scripts\block_startup_ad.ps1" -Undo
```

原理：`%APPDATA%\Netease\MuMuPlayer\data\startupImage\imageManager.json` 设为只读。
目录不存在（模拟器从未冷启动过）时，脚本会询问是否创建空索引并设为只读。

### 步骤 2：清理桌面广告

**方案 A（推荐，ROOT + 模块，开机自动生效）**

```powershell
python "...\scripts\build_ksu_module.py" -o "$env:USERPROFILE\Downloads"
```

1. 模拟器设置 → 开启 ROOT（Android 15 自动加载 KernelSU；Android 12 需自行安装 Magisk **v30.7+**，旧版会报解压错误）
2. 把生成的 `mumu-ads-cleaner-v1.0.zip` 拷到模拟器共享文件夹的 `download` 目录
   （一般在电脑「文档」目录，模拟器菜单内有路径提示）
3. KernelSU / Magisk → 模块 → 从本地安装 → 选择该 zip → 重启模拟器

**方案 B（ADB 直连，ROOT 或免 ROOT 均可）**

```powershell
powershell -ExecutionPolicy Bypass -File "...\scripts\clean_launcher_ads.ps1"
# 常用变体
... -Device 192.168.31.222:5555     # 指定设备
... -Mode Full                      # 彻底禁用 com.mumu.store（小工具下载入口会失效）
... -Persist                        # root 时写入 /data/adb/service.d 开机脚本
... -BackupDir D:\backup\mumu       # 指定备份目录
```

`-Mode Component`（默认）只禁用 5 个广告组件，**保留** `com.mumu.store` 主包，
因此小工具里的谷歌安装器、RE 文件管理器、应用商店下载入口仍可用 —— 这是默认推荐值。

脚本会自动：备份数据库与 prefs → 设置 `nemud.player_engine=WOAPRO` → 禁用组件 →
清理 `favorites` 表 → 重启桌面 → 用 `pm list packages -d` / SQL / `uiautomator dump` 三项验证。

设备端缺少 `/system/bin/sqlite3` 时，脚本自动改用 Python 在 Windows 侧改库再回传并修复权限
（需要 `python` 在 PATH，或用 `-Python` 指定）。

### 步骤 3：验证

- `pm list packages -d` 中出现 `com.mumu.store`（Full 模式）
- `favorites` 表查询结果中不再出现 `AdBannerWidgetProvider` / `DailyDiscoveryWidgetProvider` / `游戏中心` / `com.mumu.store`
- `uiautomator dump` 的 XML 匹配不到 `广告轮播|每日新发现|游戏中心|searchAdListView|com.mumu.store`
- 残留属正常：搜索框还在，但只显示「搜索游戏和应用」占位，不再有广告列表

### 步骤 4：可选 — 冷启动画面美化

修改 Qt 资源包 `NxDeviceResource.rcc`：

- Android 15：`<安装目录>\nx_device\15.0\shell\rcc\NxDeviceResource.rcc`
- Android 12：`<安装目录>\nx_device\12.0\shell\rcc\NxDeviceResource.rcc`

替换 `img_startup_landscape[_15].jpeg` / `img_startup_vertical[_15].jpeg` 换背景；
清空 `ic_white_logo.svg` 与 `ic_mumu_name.svg` 的 `<svg></svg>` 内容去掉 LOGO 与文字。

需要一个能编辑 Qt rcc 的工具（原帖提供 `MuMuRccResourceTool`），本 skill 不内置该工具。
向用户说明：用 rcc 工具打开 → 改完覆盖回原路径 → **备份改好的文件**，因为模拟器更新会覆盖它。
左上角图标复用同一 LOGO 资源，改为透明后左上角图标不显示属正常现象。

### 步骤 5：回滚

```powershell
powershell -ExecutionPolicy Bypass -File "...\scripts\restore_mumu.ps1" -BackupDir "$env:USERPROFILE\MuMuBackup\manual-XXXXXXXX-XXXXXX" -RemoveBootScript
... -OnlyReEnable                   # 只重新启用商店，不动数据库
```

模块方案回滚：在 KernelSU / Magisk 中移除模块并重启（卸载脚本会自动 `pm enable` 各组件）。

## 资源清单

| 文件 | 作用 |
|------|------|
| `scripts/lib_mumu.ps1` | 公共函数：安装目录/adb/Android 版本/端口探测、连接、root、定位 launcher 数据库 |
| `scripts/detect_mumu.ps1` | 只读环境探测，输出诊断信息 |
| `scripts/block_startup_ad.ps1` | 开屏广告：`imageManager.json` 只读（`-Undo` 取消） |
| `scripts/clean_launcher_ads.ps1` | 桌面广告主流程（含备份、清理、验证） |
| `scripts/restore_mumu.ps1` | 回滚：重新启用包与组件、还原数据库、移除开机脚本 |
| `scripts/build_ksu_module.py` | 生成 KernelSU/Magisk 去广告模块 zip（自带 service.sh，不依赖第三方下载） |
| `assets/remove_ads.sql` | 清理 `favorites` 表的 SQL |
| `references/technical.md` | 原理、路径表、组件清单、版本差异、rcc 资源路径、风险 |
| `references/manual_adb.md` | 手动命令全流程与排错表 |

## 注意

- 修改前必须备份 `launcher*.db` 与 `com.android.launcher3.prefs.xml`（脚本默认备份到 `~/MuMuBackup/<时间戳>`）
- 还原数据库后必须修复权限：`chmod 660` + `chown <原 owner>`（脚本用 `stat -c %u:%g` 自动获取）
- `nemud.player_engine` 是运行时属性，重启模拟器会失效 —— 持久化只能靠模块或 `service.d` 脚本
- 桌面包名（`app.lawnchair`）、数据库名（`launcher*.db`）、组件名随版本变化，清理前先 `SELECT` 核对
- 模拟器大版本升级后所有改动可能失效，需重新执行
- 原帖教程在 V6.4.6 完成、V6.5.3 验证，社区反馈 6.6.4 仍有效；其它版本请提示用户自测
