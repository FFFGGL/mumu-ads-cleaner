#!/usr/bin/env python3
"""MuMu 模拟器去广告 —— Python 版主流程（不依赖 PowerShell，跨平台）。

与 PowerShell 脚本等价，但更适合在受限环境（例如禁止调用 PowerShell 的沙箱）里由 AI/脚本驱动。
优先使用模拟器自带的 `mumu-cli.exe`（无需知道 ADB 端口、shell 自带 root），回退到 `adb.exe`。

用法:
    python clean_mumu.py --install-dir "D:\\Program Files\\Netease\\MuMu"
    python clean_mumu.py --install-dir ... --mode full          # 彻底禁用 com.mumu.store
    python clean_mumu.py --install-dir ... --no-module          # 不装 KernelSU 模块（重启后属性会失效）
    python clean_mumu.py --install-dir ... --block-startup-ad   # 同时屏蔽开屏广告

流程: 探测 -> 连接 -> root -> 备份 -> 关闭搜索推广栏 -> 禁用广告组件
      -> 清理 Lawnchair 数据库 -> 重启桌面 -> 安装 KernelSU 模块（持久化）-> 验证
"""
import argparse
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL_DIR = os.path.dirname(HERE)
REMOVE_ADS_SQL = os.path.join(SKILL_DIR, "assets", "remove_ads.sql")
BUILD_MODULE = os.path.join(HERE, "build_ksu_module.py")

AD_COMPONENTS = [
    "com.mumu.store/.widget.appWidgetProvider.AdBannerWidgetProvider",
    "com.mumu.store/.widget.appWidgetProvider.DailyDiscoveryWidgetProvider",
    "com.mumu.store/.widget.appWidgetProvider.HotActivityWidgetProvider",
    "com.mumu.store/.widget.appWidgetProvider.FlashSaleWidgetProvider",
    "com.mumu.store/.widget.receiver.WidgetOperateReceiver",
]

CANDIDATE_DIRS = [
    r"D:\Program Files\Netease\MuMu",
    r"C:\Program Files\Netease\MuMu",
    r"D:\Program Files\Netease\MuMuPlayer",
    r"C:\Program Files\Netease\MuMuPlayer",
]

STARTUP_JSON = os.path.join(
    os.environ.get("APPDATA", ""), "Netease", "MuMuPlayer", "data", "startupImage", "imageManager.json"
)


def log(msg, tag="*"):
    print(f"[{tag}] {msg}", flush=True)


def run(cmd, check=False):
    return subprocess.run(cmd, capture_output=True, text=True, errors="replace")


def detect_install_dir(explicit=None):
    for d in ([explicit] if explicit else []) + CANDIDATE_DIRS:
        if d and os.path.isdir(os.path.join(d, "nx_main")):
            return d
    return None


class Device:
    """封装 adb / mumu-cli 两种通道。"""

    def __init__(self, install_dir, vmindex=0, device=None):
        self.install_dir = install_dir
        self.vmindex = vmindex
        self.cli = os.path.join(install_dir, "nx_main", "mumu-cli.exe") if install_dir else None
        self.adb = os.path.join(install_dir, "nx_main", "adb.exe") if install_dir else "adb"
        if not os.path.isfile(self.adb):
            self.adb = "adb"
        self.dev = device

    # --- 连接 ---
    def connect(self):
        if self.dev:
            run([self.adb, "connect", self.dev])
            return self.dev
        if self.cli and os.path.isfile(self.cli):
            r = run([self.cli, "adb", "-v", str(self.vmindex), "-c", "devices"])
            m = re.search(r"(\d+\.\d+\.\d+\.\d+:\d+)\s+device", r.stdout or "")
            if m:
                self.dev = m.group(1)
                log(f"通过 mumu-cli 发现设备: {self.dev}")
                return self.dev
        for port in (16384, 16416, 7555, 5555, 16448, 16480):
            addr = f"127.0.0.1:{port}"
            out = run([self.adb, "connect", addr]).stdout or ""
            if "connected" in out or "already connected" in out:
                r = run([self.adb, "-s", addr, "shell", "id", "-u"])
                if "0" in (r.stdout or "").strip():
                    self.dev = addr
                    log(f"已连接: {addr}")
                    return addr
        raise SystemExit("未找到可用设备。请确认模拟器已启动（mumu-cli control launch -v 0）并开启 ADB 调试。")

    def shell(self, cmd):
        if self.cli and os.path.isfile(self.cli) and self.dev is None:
            r = run([self.cli, "sh", "-v", str(self.vmindex), "-c", cmd])
        else:
            r = run([self.adb, "-s", self.dev, "shell", cmd])
        return (r.stdout or "").strip()

    def adb_cmd(self, *args):
        return (run([self.adb, "-s", self.dev, *args]).stdout or "").strip()

    def ensure_root(self):
        if self.shell("id -u") == "0":
            log("shell 已具备 root 权限", "OK")
            return True
        self.adb_cmd("root")
        time.sleep(3)
        if self.dev:
            run([self.adb, "connect", self.dev])
        ok = self.shell("id -u") == "0"
        log("adb root 成功" if ok else "未获得 root，组件禁用可能失败", "OK" if ok else "!")
        return ok


def launcher_db(dev):
    for p in (
        "/data/user/0/app.lawnchair/databases/launcher_4_7_6_1.db",
        "/data/data/app.lawnchair/databases/launcher_4_7_6_1.db",
        "/data/user/0/app.lawnchair/databases/launcher_4_7_6.db",
    ):
        if "OK" in dev.shell(f"test -f {p} && echo OK"):
            return p
    listing = dev.shell("ls /data/user/0/app.lawnchair/databases/")
    m = re.search(r"launcher[\w.]*\.db", listing)
    return f"/data/user/0/app.lawnchair/databases/{m.group(0)}" if m else None


def block_startup_ad(undo=False):
    if not STARTUP_JSON or not os.path.exists(STARTUP_JSON):
        log(f"开屏广告索引不存在，跳过: {STARTUP_JSON}", "!")
        return
    if undo:
        subprocess.run(["attrib", "-R", STARTUP_JSON], capture_output=True)
        log("已取消开屏广告索引只读")
    else:
        subprocess.run(["attrib", "+R", STARTUP_JSON], capture_output=True)
        log(f"开屏广告索引已设为只读: {STARTUP_JSON}", "OK")


def main() -> int:
    ap = argparse.ArgumentParser(description="MuMu 模拟器去广告（Python 版）")
    ap.add_argument("--install-dir", help="模拟器安装目录，默认自动探测")
    ap.add_argument("--vmindex", type=int, default=0, help="模拟器编号，默认 0")
    ap.add_argument("--device", help="显式指定 adb 地址，如 127.0.0.1:16384")
    ap.add_argument("--mode", choices=["component", "full"], default="component",
                    help="component=只禁广告组件（保留小工具，默认）；full=禁用整个 com.mumu.store")
    ap.add_argument("--backup-dir", help="备份目录，默认 ~/MuMuBackup/<时间戳>")
    ap.add_argument("--no-module", action="store_true", help="不安装 KernelSU 模块（重启后属性失效）")
    ap.add_argument("--block-startup-ad", action="store_true", help="同时屏蔽冷启动开屏广告")
    ap.add_argument("--reboot", action="store_true", help="装完模块后自动重启模拟器验证")
    args = ap.parse_args()

    install_dir = detect_install_dir(args.install_dir)
    if not install_dir:
        raise SystemExit("未找到 MuMu 安装目录，请用 --install-dir 指定。")
    log(f"模拟器目录: {install_dir}")

    if args.block_startup_ad:
        block_startup_ad()

    dev = Device(install_dir, args.vmindex, args.device)
    dev.connect()
    dev.ensure_root()

    db = launcher_db(dev)
    backup = args.backup_dir or os.path.join(
        os.path.expanduser("~"), "MuMuBackup", time.strftime("manual-%Y%m%d-%H%M%S"))
    os.makedirs(backup, exist_ok=True)
    if db:
        dev.adb_cmd("pull", db, os.path.join(backup, os.path.basename(db) + ".bak"))
        log(f"数据库已备份 -> {backup}", "OK")
    dev.adb_cmd("pull", "/data/data/app.lawnchair/shared_prefs/com.android.launcher3.prefs.xml",
                os.path.join(backup, "com.android.launcher3.prefs.xml.bak"))

    # 1) 关闭顶部搜索推广栏
    prop = dev.shell("resetprop nemud.player_engine WOAPRO 2>/dev/null || setprop nemud.player_engine WOAPRO; "
                     "getprop nemud.player_engine")
    log(f"nemud.player_engine = {prop}", "OK" if prop == "WOAPRO" else "!")

    dev.shell("am force-stop app.lawnchair; am force-stop com.mumu.store")

    # 2) 禁用广告来源
    if args.mode == "full":
        log(dev.shell("pm disable-user --user 0 com.mumu.store") or "已禁用 com.mumu.store", "OK")
    else:
        for c in AD_COMPONENTS:
            log(f"  {c.split('/')[-1]} -> {dev.shell('pm disable ' + c)}")

    # 3) 清理桌面数据库
    if db:
        if os.path.isfile(REMOVE_ADS_SQL):
            dev.adb_cmd("push", REMOVE_ADS_SQL, "/data/local/tmp/remove_ads.sql")
            dev.shell(f"sqlite3 {db} '.read /data/local/tmp/remove_ads.sql'")
        rows = dev.shell(f"sqlite3 {db} 'SELECT _id,title,appWidgetProvider FROM favorites ORDER BY _id;'")
        log("favorites 表现状:\n" + rows)
        log("数据库已无广告项", "OK" if "mumu.store" not in rows else "仍存在广告项")

    # 4) 重启桌面
    dev.shell("am force-stop app.lawnchair")
    time.sleep(2)
    dev.shell("input keyevent 3")
    time.sleep(2)

    # 5) 持久化：KernelSU 模块
    if not args.no_module:
        if "ksud" in dev.shell("ls /data/adb"):
            zip_path = os.path.join(backup, "mumu-ads-cleaner-v1.0.zip")
            run([sys.executable, BUILD_MODULE, "-o", backup])
            dev.adb_cmd("push", zip_path, "/data/local/tmp/mumu-ads-cleaner.zip")
            out = dev.shell("/data/adb/ksud module install /data/local/tmp/mumu-ads-cleaner.zip")
            ok = "successfully" in out or "Done" in out
            log("KernelSU 模块已安装（重启后生效）" if ok else f"模块安装返回: {out[-200:]}", "OK" if ok else "!")
            if ok and args.reboot and dev.cli and os.path.isfile(dev.cli):
                log("重启模拟器以验证 ...")
                run([dev.cli, "control", "restart", "-v", str(dev.vmindex)])
                time.sleep(40)
                run([dev.adb, "connect", dev.dev])
                dev.adb_cmd("root")
                time.sleep(3)
                run([dev.adb, "connect", dev.dev])
                log("重启后 nemud.player_engine = " + dev.shell("getprop nemud.player_engine"), "OK")
                log("模块目录: " + dev.shell("ls /data/adb/modules"), "OK")
        else:
            log("未检测到 KernelSU（/data/adb/ksud），跳过模块；重启模拟器后需重跑本脚本", "!")

    # 6) 界面验证
    dev.shell("uiautomator dump /sdcard/ui_check.xml")
    ui = os.path.join(backup, "ui_check.xml")
    dev.adb_cmd("pull", "/sdcard/ui_check.xml", ui)
    if os.path.isfile(ui):
        text = open(ui, encoding="utf-8", errors="replace").read()
        hits = [k for k in ("广告轮播", "每日新发现", "游戏中心", "searchAdListView", "com.mumu.store") if k in text]
        log("界面无广告元素" if not hits else f"界面仍匹配到: {hits}", "OK" if not hits else "!")

    log(f"完成。备份目录: {backup}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
