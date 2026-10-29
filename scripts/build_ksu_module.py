#!/usr/bin/env python3
"""生成 MuMu 去广告的 KernelSU / Magisk 模块 zip（开机自动生效，不依赖第三方下载）。

用法:
    python build_ksu_module.py [-o 输出目录] [--version v1.0]

生成后：
  1. 模拟器设置里开启 ROOT（Android 15 会自动加载 KernelSU，Android 12 用 Magisk）
  2. 把 zip 拷到模拟器共享文件夹的 download 目录（一般在电脑“文档”目录，模拟器菜单里有路径提示）
  3. 打开 KernelSU / Magisk 应用 -> 模块 -> 从本地安装 -> 选择该 zip
  4. 重启模拟器
"""
import argparse
import os
import zipfile

MODULE_PROP = """id=mumu-ads-cleaner
name=MuMu Launcher Ads Cleaner
version={version}
versionCode={version_code}
author=mumu-ads-cleaner skill
description=Remove MuMu launcher ads and search bar; keep Google installer & RE manager entries.
updateJson=
"""

SERVICE_SH = """#!/system/bin/sh
# MuMu Launcher Ads Cleaner - boot service
# 开机后：把 MuMu 桌面识别环境改成 WOAPRO（去掉顶部搜索推广栏）
#        禁用 com.mumu.store 的广告组件（保留主包，小工具仍可下载谷歌安装器/RE 管理器）
#        清理 Lawnchair 桌面数据库中的广告记录，并重启桌面

MODDIR=$(dirname "$0")

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done

# MuMu 启动过程中可能重写 nemud.* 属性，这里在开机后的一段时间内反复设置
(
  i=0
  while [ $i -lt 20 ]; do
    if [ -x /data/adb/ksu/bin/resetprop ]; then
      /data/adb/ksu/bin/resetprop nemud.player_engine WOAPRO
    elif [ -x /data/adb/magisk/resetprop ]; then
      /data/adb/magisk/resetprop nemud.player_engine WOAPRO
    else
      resetprop nemud.player_engine WOAPRO 2>/dev/null || setprop nemud.player_engine WOAPRO
    fi
    i=$((i+1))
    sleep 3
  done
) &

# 等 package manager 可用
sleep 10

for c in AdBannerWidgetProvider DailyDiscoveryWidgetProvider HotActivityWidgetProvider FlashSaleWidgetProvider; do
  pm disable com.mumu.store/.widget.appWidgetProvider.$c >/dev/null 2>&1
done
pm disable com.mumu.store/.widget.receiver.WidgetOperateReceiver >/dev/null 2>&1

SQLITE=/system/bin/sqlite3
[ -x "$SQLITE" ] || SQLITE=$(command -v sqlite3)
if [ -n "$SQLITE" ]; then
  for d in /data/user/0/app.lawnchair/databases/launcher*.db /data/data/app.lawnchair/databases/launcher*.db; do
    [ -f "$d" ] && $SQLITE "$d" "DELETE FROM favorites WHERE appWidgetProvider LIKE 'com.mumu.store/%' OR intent LIKE '%component=com.mumu.store/%';"
  done
fi

sleep 2
am force-stop app.lawnchair
sleep 1
input keyevent 3
"""

POST_FS_DATA_SH = """#!/system/bin/sh
# post-fs-data 阶段提前设置属性，覆盖 MuMu 早期写入
resetprop nemud.player_engine WOAPRO 2>/dev/null || setprop nemud.player_engine WOAPRO
"""

UNINSTALL_SH = """#!/system/bin/sh
# 卸载模块时恢复
for c in AdBannerWidgetProvider DailyDiscoveryWidgetProvider HotActivityWidgetProvider FlashSaleWidgetProvider; do
  pm enable com.mumu.store/.widget.appWidgetProvider.$c >/dev/null 2>&1
done
pm enable com.mumu.store/.widget.receiver.WidgetOperateReceiver >/dev/null 2>&1
pm enable com.mumu.store >/dev/null 2>&1
am force-stop app.lawnchair
"""

CUSTOMIZE_SH = """#!/system/bin/sh
ui_print "*********************************************"
ui_print " MuMu Launcher Ads Cleaner"
ui_print " - 去掉顶部搜索推广栏 / 广告轮播 / 每日发现"
ui_print " - 保留谷歌安装器、RE 文件管理器等小工具"
ui_print " - 重启模拟器后自动生效"
ui_print "*********************************************"
"""

README = """MuMu Launcher Ads Cleaner (KernelSU / Magisk 模块)

安装：
  1. 模拟器设置 -> 开启 ROOT（Android 15 自带 KernelSU；Android 12 需自行安装 Magisk v30.7+）
  2. 把本 zip 拷入模拟器共享文件夹的 download 目录
  3. KernelSU / Magisk -> 模块 -> 从本地安装 -> 选择本 zip
  4. 重启模拟器

做了什么：
  - resetprop nemud.player_engine WOAPRO  -> 顶部 MuMu 搜索/推广栏不再出现
  - pm disable com.mumu.store 的 4 个广告 Widget Provider + 1 个 Receiver
    （主包保持启用，谷歌安装器/RE 管理器/应用商店下载入口仍可用）
  - 清理 /data/user/0/app.lawnchair/databases/launcher*.db 中 favorites 表的广告记录
  - am force-stop app.lawnchair + input keyevent 3 重启桌面

卸载：
  KernelSU / Magisk 中移除模块并重启，或手动执行：
    pm enable com.mumu.store
    pm enable com.mumu.store/.widget.appWidgetProvider.AdBannerWidgetProvider
    ...

注意：
  - 模拟器大版本更新后桌面包名/组件名/数据库名可能变化，需要重新核对。
  - 如果桌面数据库名不再是 launcher*.db，请修改 service.sh 中的路径。
"""


def main() -> int:
    ap = argparse.ArgumentParser(description="Build MuMu ads-cleaner KernelSU/Magisk module zip")
    ap.add_argument("-o", "--out", default=".", help="输出目录（默认当前目录）")
    ap.add_argument("--version", default="v1.0", help="版本号，如 v1.1")
    args = ap.parse_args()

    version_code = "".join(ch for ch in args.version if ch.isdigit()) or "100"

    os.makedirs(args.out, exist_ok=True)
    zip_path = os.path.join(args.out, f"mumu-ads-cleaner-{args.version}.zip")

    files = {
        "module.prop": MODULE_PROP.format(version=args.version, version_code=version_code),
        "service.sh": SERVICE_SH,
        "post-fs-data.sh": POST_FS_DATA_SH,
        "uninstall.sh": UNINSTALL_SH,
        "customize.sh": CUSTOMIZE_SH,
        "README.md": README,
    }

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, content in files.items():
            info = zipfile.ZipInfo(name, date_time=(2026, 8, 4, 12, 0, 0))
            info.external_attr = 0o755 << 16 if name.endswith(".sh") else 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, content.replace("\r\n", "\n"))

    print(f"[OK] 模块已生成: {zip_path}")
    print("    下一步：拷入模拟器共享文件夹 download 目录 -> KernelSU/Magisk 安装 -> 重启模拟器")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
