#!/bin/bash
# 一键编译并安装到真机：iPhone 用数据线连 Mac 并解锁，手表戴着、解锁、在手机旁边。
# 用法：./install.sh          （手机和手表都装）
#       ./install.sh watch    （只装手表）
#       ./install.sh phone    （只装手机）
set -euo pipefail
cd "$(dirname "$0")"
TARGET="${1:-all}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "▶︎ 查找设备…"
xcrun devicectl list devices --json-output "$TMP/devices.json" >/dev/null
read -r PHONE WATCH < <(python3 - "$TMP/devices.json" <<'EOF'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
def pick(kind):
    for d in devices:
        hw = d.get("hardwareProperties", {})
        if hw.get("reality") == "physical" and hw.get("deviceType") == kind:
            # iPhone 必须是已连接状态；手表通过 iPhone 中转，配对即可
            state = d.get("connectionProperties", {}).get("tunnelState", "")
            if kind == "iPhone" and state != "connected":
                return "-"
            return hw.get("udid", "-")
    return "-"
print(pick("iPhone"), pick("appleWatch"))
EOF
)
echo "  iPhone: $PHONE"
echo "  手表:   $WATCH"
if [[ "$TARGET" != "watch" && "$PHONE" == "-" ]]; then echo "✗ iPhone 没有连接：请用数据线连上 Mac、解锁手机，稍等几秒再运行"; exit 1; fi
if [[ "$TARGET" != "phone" && "$WATCH" == "-" ]]; then echo "✗ 没找到手表，请确认手表已配对、解锁并开启开发者模式"; exit 1; fi

[[ -d OneMore.xcodeproj ]] || ./generate.sh
# bundle ID 前缀在 Config/Signing.xcconfig 里配置
PREFIX=$(grep -E '^BUNDLE_ID_PREFIX' Config/Signing.xcconfig | cut -d= -f2 | xargs)

echo "▶︎ 编译（第一次需要几分钟）…"
xcodebuild -project OneMore.xcodeproj -scheme OneMore -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build/device \
  -allowProvisioningUpdates build -quiet
APP=build/device/Build/Products/Debug-iphoneos/OneMore.app

if [[ "$TARGET" != "watch" ]]; then
  echo "▶︎ 安装到 iPhone…"
  xcrun devicectl device install app --device "$PHONE" "$APP" >/dev/null
fi
if [[ "$TARGET" != "phone" ]]; then
  echo "▶︎ 安装到手表（可能要一两分钟）…"
  xcrun devicectl device install app --device "$WATCH" "$APP/Watch/OneMoreWatch.app" >/dev/null
  xcrun devicectl device process launch --device "$WATCH" "$PREFIX.onemore.watchkitapp" >/dev/null 2>&1 || true
fi
echo "✓ 完成"
