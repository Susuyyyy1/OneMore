#!/bin/bash
# 从 project.yml 生成 OneMore.xcodeproj（修改 project.yml 或新增/删除源文件后运行）
# 需要 XcodeGen：brew install xcodegen（或把官方 release 解压到 tools/xcodegen/）
set -euo pipefail
cd "$(dirname "$0")"
if [[ -x tools/xcodegen/bin/xcodegen ]]; then
  XCODEGEN=tools/xcodegen/bin/xcodegen
elif command -v xcodegen >/dev/null; then
  XCODEGEN=xcodegen
else
  echo "✗ 没有找到 XcodeGen。请先安装：brew install xcodegen"
  echo "  或从 https://github.com/yonaskolb/XcodeGen/releases 下载 xcodegen.zip，解压到 tools/xcodegen/"
  exit 1
fi
"$XCODEGEN" generate --spec project.yml
