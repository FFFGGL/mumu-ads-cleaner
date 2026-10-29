# mumu-ads-cleaner

一个 [WorkBuddy](https://www.workbuddy.cn) / Claude 风格的 Skill：在 Windows 上通过 ADB 与 PowerShell 去除
**MuMu 模拟器**（网易 MuMu Player / MuMuNxDevice）的开屏广告与桌面广告，并可选美化冷启动画面。

技术内容整理自吾爱破解原帖《[原创工具] MuMu模拟器去广告+美化》（[thread-2121262](https://www.52pojie.cn/thread-2121262-1-1.html)，
作者 许我浅笑而安），原帖教程在 MuMu **V6.4.6** 完成、**V6.5.3** 验证，社区反馈 6.6.4 仍有效，其它版本请自测。

## 能做什么

| 目标 | 做法 | 是否需 ROOT |
|------|------|-------------|
| 冷启动开屏广告 | 广告索引 `imageManager.json` 设为只读 | 否 |
| 桌面顶部搜索/推广栏 | 系统属性 `nemud.player_engine=WOAPRO` | 否（持久化为是） |
| 广告轮播 Widget / 每日新发现 / 游戏中心图标 | 禁用 `com.mumu.store` 的 5 个广告组件 + 清理 Lawnchair 数据库 | 建议 |
| 启动弹窗广告 | 同上 | 建议 |
| 冷启动背景图、中心 LOGO | 修改 Qt 资源包 `NxDeviceResource.rcc` | 否 |

默认**保留** `com.mumu.store` 主包，因此小工具里的谷歌安装器、RE 文件管理器、应用商店下载入口仍可用。

## 安装

把整个目录放到 WorkBuddy 用户级 skills 目录即可：

```
%USERPROFILE%\.workbuddy\skills\mumu-ads-cleaner\
```

或项目级：`<项目>\.workbuddy\skills\mumu-ads-cleaner\`。

## 快速开始

```powershell
# 0) 只读体检：安装目录、adb、Android 版本、设备端口、root 状态、当前广告项
powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.workbuddy\skills\mumu-ads-cleaner\scripts\detect_mumu.ps1"

# 1) 屏蔽开屏广告（无需 ROOT）
powershell -ExecutionPolicy Bypass -File "...\scripts\block_startup_ad.ps1"          # -Undo 取消

# 2) 桌面广告 —— 方案 A：ROOT + 模块（开机自动生效）
python "...\scripts\build_ksu_module.py" -o "%USERPROFILE%\Downloads"
#    把 zip 拷到模拟器共享文件夹 download 目录 -> KernelSU / Magisk 安装 -> 重启模拟器

# 2) 桌面广告 —— 方案 B：ADB 直连
powershell -ExecutionPolicy Bypass -File "...\scripts\clean_launcher_ads.ps1"
#    常用参数：-Device <ip:port>  -Mode Full  -Persist  -BackupDir <目录>

# 3) 回滚
powershell -ExecutionPolicy Bypass -File "...\scripts\restore_mumu.ps1" -BackupDir "<步骤2的备份目录>" -RemoveBootScript
```

## 目录结构

```
SKILL.md                       触发条件 + 工作流 + 资源清单 + 注意事项
scripts/
  lib_mumu.ps1                 公共函数库（探测 / 连接 / root / 定位数据库）
  detect_mumu.ps1              只读环境探测
  block_startup_ad.ps1         开屏广告屏蔽与恢复
  clean_launcher_ads.ps1       桌面广告主流程（备份 → 清理 → 验证）
  restore_mumu.ps1             回滚
  build_ksu_module.py          生成 KernelSU / Magisk 模块 zip
assets/
  remove_ads.sql               清理 favorites 表的 SQL
references/
  technical.md                 原理、路径表、组件清单、版本差异、rcc 资源路径
  manual_adb.md                手动命令全流程与排错表
```

## 注意

- 脚本会自动备份 `launcher*.db` 与 `com.android.launcher3.prefs.xml` 到 `%USERPROFILE%\MuMuBackup\<时间戳>`
- `nemud.player_engine` 是运行时属性，重启模拟器会失效，持久化需刷模块或写 `service.d` 脚本
- 桌面包名、数据库名、组件名随版本变化，清理前先核对
- 模拟器大版本升级后改动可能失效，需重新执行

## 许可与声明

本项目仅整理公开的本地配置修改方法，不含任何第三方二进制或破解补丁，仅供学习交流。
对模拟器造成的任何影响由使用者自行承担。原帖版权归原作者所有。
