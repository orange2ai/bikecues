#!/bin/bash
# 咕咕骑车 正式发版关卡 —— 每次发版前必须完整通过一次
#
# 用法: scripts/release.sh [版本号，可选，如 0.2.0]
#
# 流程: 全量冒烟（编译+单测+装机产物+启动+骑行生命周期）
#       → 真机编译装机 → 人工实测清单
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== [发版] 第 1 步：全量冒烟测试 ==="
./scripts/smoke.sh

echo "=== [发版] 第 2 步：真机编译 + 装机 ==="
xcodebuild -project coucou.xcodeproj -scheme coucou -destination 'generic/platform=iOS' \
     -allowProvisioningUpdates build > /tmp/release_build.log 2>&1 \
  || { grep -E "error:" /tmp/release_build.log | sort -u | head -10; echo "❌ 真机编译失败"; exit 1; }
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "coucou.app" -path "*iphoneos*" -newermt "-3 minutes" | head -1)
if xcrun devicectl device install app --device 9FEED4F4-476D-58CE-B8E0-CB96EA35D3C2 "$APP" 2>&1 | grep -qiE "installed"; then
  echo "真机安装 ✓"
else
  echo "⚠️ 真机未连接，跳过装机——发版前必须人工补装并实测"
fi

echo "=== [发版] 第 3 步：人工实测清单（逐项打勾后才能提审/发布）==="
cat << 'LIST'
  [ ] 真机点 GO：3-2-1 倒数后正常开骑，不闪退
  [ ] 户外/骑行台骑 1 分钟：速度、距离与实际相符
  [ ] 锁屏 30 秒再解锁：记录不断、无异常
  [ ] 锁屏实时活动：卡片出现、数据刷新、结束消失
  [ ] 灵动岛：紧凑速度显示、长按展开正常
  [ ] 手表体能训练在跑时：心率实时显示（今天没戴表可跳过并在发版说明注明）
  [ ] 长按结束：结算页出现、撒花正常、数据写入苹果健康
  [ ] 杀 App 重启：无白屏、无残留实时活动
LIST

if [ -n "${1:-}" ]; then
  echo "=== [发版] 版本号: $1（请在 project.yml 更新 MARKETING_VERSION 后重新冒烟一次）==="
fi
echo -e "\n✅ 发版关卡完成（人工清单勾完才算真正通过）"
