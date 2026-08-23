#!/usr/bin/env bash
# Ghi trace hiệu năng iOS trên MÁY THẬT bằng Instruments. Không cần sửa code app.
#
#   ./tool/measure_ios.sh <bundleId> <số_giây> <nhãn_lần_đo>
#   ./tool/measure_ios.sh com.example.example 900 baseline
#
# iOS không cho bên thứ ba đọc nhiệt độ pin và không có `adb` tương đương.
# Hai nguồn thay thế, cả hai đều KHÔNG cần sửa code app:
#   1. Instruments (script này) — CPU/GPU/năng lượng + track Thermal State.
#   2. Console.app lọc 'ThermalGovernor' — mốc đổi bậc nhiệt, do SDK tự NSLog.
set -euo pipefail

BUNDLE="${1:?thiếu bundleId}"
DURATION="${2:-900}"
LABEL="${3:-run}"

OUT_DIR="build/perf"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
TRACE="$OUT_DIR/${LABEL}-${STAMP}.trace"

DEVICE_ID="$(xcrun devicectl list devices 2>/dev/null \
  | awk 'NR>2 && /available/ {print $(NF-2); exit}')"
[ -n "$DEVICE_ID" ] || { echo "Không thấy iPhone nào đã pair."; exit 1; }
echo "Thiết bị: $DEVICE_ID"

# ── 1. Ghi trace năng lượng/CPU song song với phiên thao tác tay ──────────────
echo "Ghi trace ${DURATION}s → $TRACE"
echo "   (thao tác trên máy ngay bây giờ)"
xcrun xctrace record \
  --template 'Power Profiler' \
  --device "$DEVICE_ID" \
  --attach "$BUNDLE" \
  --time-limit "${DURATION}s" \
  --output "$TRACE" || echo "xctrace lỗi — vẫn kéo CSV bên dưới."

# ── 2. Mốc đổi bậc nhiệt do SDK ghi ──────────────────────────────────────────
echo
echo "Mở Console.app → chọn thiết bị → search 'ThermalGovernor' → Start streaming."
echo "Sẽ thấy: ThermalGovernor: thermal tier normal → warm"

echo
echo "Mở trace: open $TRACE"
