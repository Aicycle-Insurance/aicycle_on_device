#!/usr/bin/env bash
# Thu số liệu nhiệt/CPU/RAM của app trong lúc chạy màn camera, xuất CSV.
#
#   ./tool/measure_android.sh <applicationId> <số_giây> <nhãn_lần_đo>
#   ./tool/measure_android.sh com.example.example 900 baseline
#
# Chạy SONG SONG với phiên thao tác tay trên máy. Kết thúc sẽ in đường dẫn CSV.
set -euo pipefail

PKG="${1:?thiếu applicationId}"
DURATION="${2:-900}"
LABEL="${3:-run}"
INTERVAL="${4:-5}"

OUT_DIR="build/perf"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
CSV="$OUT_DIR/${LABEL}-${STAMP}.csv"

PID="$(adb shell pidof "$PKG" | tr -d '\r')"
[ -n "$PID" ] || { echo "App chưa chạy: $PKG"; exit 1; }

# Reset bộ đếm pin + frame để số liệu chỉ tính từ bây giờ.
adb shell dumpsys batterystats --reset >/dev/null 2>&1 || true
adb shell dumpsys gfxinfo "$PKG" reset >/dev/null 2>&1 || true

echo "elapsed_s,battery_c,thermal_status,cpu_pct,pss_total_kb,java_heap_kb,native_heap_kb,graphics_kb" > "$CSV"
echo "Đang ghi → $CSV  (pid=$PID, ${DURATION}s)"

START=$(date +%s)
END=$((START + DURATION))
while [ "$(date +%s)" -lt "$END" ]; do
  T=$(( $(date +%s) - START ))

  BATT=$(adb shell dumpsys battery 2>/dev/null | awk '/temperature:/ {printf "%.1f", $2/10}')
  # getCurrentThermalStatus: 0=NONE 1=LIGHT 2=MODERATE 3=SEVERE 4=CRITICAL …
  THERM=$(adb shell dumpsys thermalservice 2>/dev/null \
          | awk -F'= *' '/Thermal Status/ {gsub(/[^0-9]/,"",$2); print $2; exit}')
  CPU=$(adb shell top -b -n 1 -p "$PID" 2>/dev/null | awk -v p="$PID" '$1==p {print $9; exit}')

  MEM=$(adb shell dumpsys meminfo "$PID" 2>/dev/null)
  PSS=$(echo "$MEM"  | awk '/^ *TOTAL PSS:/ {print $3; exit}')
  JAVA=$(echo "$MEM" | awk '/Java Heap:/    {print $3; exit}')
  NATIVE=$(echo "$MEM" | awk '/Native Heap:/{print $3; exit}')
  GFX=$(echo "$MEM"  | awk '/^ *Graphics:/  {print $2; exit}')

  echo "${T},${BATT:-},${THERM:-},${CPU:-},${PSS:-},${JAVA:-},${NATIVE:-},${GFX:-}" >> "$CSV"
  sleep "$INTERVAL"
done

echo
echo "── Frame stats (jank) ──"
adb shell dumpsys gfxinfo "$PKG" | sed -n '/Total frames rendered/,/95th percentile/p'
echo
echo "── Mốc đổi bậc nhiệt do SDK ghi ──"
adb logcat -d -s ThermalGovernor:I | tail -20
echo
echo "CSV: $CSV"
