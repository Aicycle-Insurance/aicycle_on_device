# Kịch bản đo hiệu năng — nhiệt & tải

Đo **không cần thêm code vào app**. Chỉ dùng DevTools + công cụ ngoài của hệ
điều hành.

---

## 0. DevTools đo được gì, KHÔNG đo được gì

Đây là điều phải nắm trước khi lên kế hoạch, vì DevTools chỉ nhìn thấy phía
Dart/Flutter — toàn bộ inference chạy trên luồng native (Kotlin executor /
Swift DispatchQueue) là **vùng mù** của nó.

| Mảng đã sửa | DevTools đo được? |
|---|---|
| **Tách rebuild overlay** | ✅ **Đo trực tiếp, rất tốt.** Đây đúng là việc DevTools sinh ra để làm |
| **Cache `previewPath`** | 🟡 Gián tiếp — thấy qua thời gian UI thread giảm, không tách riêng được |
| **Thermal governor** | ❌ **Không đo được gì cả** |

Cụ thể DevTools **không** cho bạn:
- nhiệt độ máy / thermal state
- CPU% và GPU% của luồng native (nơi 3 model chạy)
- native heap / bitmap memory (nơi rò bộ nhớ thật sự xảy ra)
- mức tiêu thụ pin

CPU profiler của DevTools chỉ profile **Dart isolate**. Inference không xuất
hiện ở đó.

**Hệ quả:** DevTools một mình đủ để chứng minh phần tách rebuild, nhưng **không
chứng minh được governor hạ nhiệt**. Muốn có con số nhiệt cho báo cáo thì phải
dùng công cụ ngoài ở mục 3 và 4 — cả hai đều **không cần sửa code**.

---

## 1. Hai cấu hình cần so

| Tên | Commit |
|---|---|
| `baseline` | `fa4552f` — trước thermal governor, trước tách rebuild |
| `optimized` | `HEAD` |

Cả hai build **`--profile`**. Debug build chậm 3–10×, kết luận sai hoàn toàn.

---

## 2. Điều kiện đo — sai ở đây thì mọi con số vô nghĩa

| Yếu tố | Yêu cầu | Vì sao |
|---|---|---|
| Build | `--profile` | debug làm lệch hoàn toàn |
| Sạc | **Rút sạc** | sạc tự sinh nhiệt, che mất tín hiệu cần đo |
| Pin | > 50 %, chênh < 10 % giữa 2 lần | pin thấp → SoC bị hạ xung |
| Nhiệt khởi điểm | máy nguội về baseline | **sai số lớn nhất khi so A/B** |
| Độ sáng | khoá thủ công, cùng mức | auto-brightness đổi cả tải lẫn nhiệt |
| Nhiệt độ phòng | cùng phòng, chênh < 2 °C | |
| App nền | kill hết | |
| Ốp lưng | tháo, hoặc giữ nguyên cả 2 lần | ốp giữ nhiệt |

**Xác nhận máy đã nguội** (Android): `adb shell dumpsys battery | grep temperature`
→ đợi về ±0.5 °C so với lúc bắt đầu lần trước, thường 15–20 phút.
iOS: để máy nghỉ 15–20 phút và kiểm tra Console.app không còn log
`ThermalGovernor` báo bậc > normal.

---

## 3. Kịch bản thao tác (giống hệt cho mọi lần đo)

Tổng **15 phút**, bấm giờ.

| Phút | Thao tác |
|---|---|
| 0:00 | Mở app → vào màn camera. Bắt đầu ghi. |
| 0:00–0:30 | Chờ model load, tooltip đầu tiên hiện |
| 0:30 | Bấm "Bắt đầu chụp ảnh xe" |
| 0:30–3:00 | **Góc 1**: căn toàn cảnh tới khi tự chụp → soi tổn thất → xác nhận 2 lần |
| 3:00–5:30 | **Góc 2** (góc chéo), lặp lại |
| 5:30–8:00 | **Góc 3** |
| 8:00–10:30 | **Góc 4** |
| 10:30–15:00 | **Pha tải liên tục**: giữ camera chĩa vào vùng có tổn thất, không bấm gì, để model chạy liên tục |
| 15:00 | Dừng ghi, thoát màn camera |

Đoạn 10:30–15:00 là chỗ bộc lộ rõ nhất hiệu quả governor.

⚠️ Đoạn đó **phải luôn có tổn thất trong khung**. Nếu model không thấy gì, flow
nhảy sang warning và đổi pha — kịch bản 2 lần đo sẽ lệch nhau.

**Triệt tiêu biến thiên do người thao tác:** thay xe thật bằng **video quay sẵn
phát trên màn hình thứ hai** (độ sáng khoá). Kém thực tế hơn nhưng hai lần đo
nhìn thấy đúng cùng một chuỗi hình.

---

## 4. DevTools — từng bước

Môi trường tham chiếu: Flutter 3.44.8, DevTools 2.57.0.

### 4.0 Chuẩn bị

**Bắt buộc dùng máy thật.** Simulator/emulator không có GPU và nhiệt thật, số đo
vô nghĩa.

```bash
flutter devices                      # lấy device id
cd example
flutter run --profile -d <device_id>
```

Khi console hiện `A Dart VM Service on ... is available at: http://127.0.0.1:...`
thì **bấm phím `d`** trong terminal đó → DevTools mở trên trình duyệt.
(VS Code: Command Palette → `Dart: Open DevTools`.)

> Vì sao phải `--profile`: bản debug có assert + JIT chưa tối ưu, chậm 3–10×.
> Con số rebuild vẫn đúng nhưng thời gian frame thì sai hoàn toàn.

### 4.1 Hai lần chạy riêng — đừng gộp

`Track Widget Builds` **tự nó thêm overhead** vào mỗi lần dựng widget. Nếu bật
nó rồi đọc luôn thời gian frame thì con số bị thổi phồng.

| Lần chạy | Bật gì | Đọc gì |
|---|---|---|
| **A** | Track Widget Builds **ON** | số lần rebuild (mục 4.2) |
| **B** | Track Widget Builds **OFF** | thời gian frame, jank (mục 4.3) |

### 4.2 Lần chạy A — đếm rebuild (bằng chứng chính)

1. DevTools → tab **Performance**.
2. Mở menu **Enhanced Tracing** (nút ở thanh công cụ phía trên biểu đồ frames).
3. Tick **Track Widget Builds**.
4. Trên máy: đi tới **pha soi tổn thất** (đã chụp toàn cảnh xong, đang có
   bounding box đỏ/vàng chạy trên màn hình). Giữ yên camera ~30 giây.
5. Trong biểu đồ **Flutter Frames**, click chọn một frame bất kỳ trong khoảng đó.
6. Xem tab **Rebuild Stats** ở panel dưới → bảng "widget — số lần rebuild".

Kỳ vọng:

| Widget | baseline | optimized |
|---|---|---|
| `BoundingBoxOverlay` | cao | cao — **đúng**, box phải chạy mỗi frame |
| `CarPartLabelOverlay` | cao | cao — đúng |
| `CameraBottomBar` | **cao** | **0** |
| `CarProgressRing` | **cao** | **0** |
| `CameraTopBar` | **cao** | **0** |
| `CaptureFreezeOverlay` | **cao** | **0** |
| `CameraToolTip` | **cao** | **0** |

Nếu ở `optimized` mà 4 dòng dưới vẫn cao → việc tách builder chưa ăn, cần kiểm
tra lại.

**Chụp màn hình bảng Rebuild Stats của cả hai bản, đặt cạnh nhau.** Đây là hình
thuyết phục nhất trong báo cáo.

### 4.3 Lần chạy B — thời gian frame & jank

Tắt Track Widget Builds, restart app, lặp lại kịch bản.

Biểu đồ **Flutter Frames**: mỗi cột là một frame, chia hai màu —
**xanh dương = UI thread** (chạy code Dart, build/layout) và
**xanh lá = Raster thread** (vẽ ra GPU). Đường ngang là ngưỡng 16 ms (60 Hz).

Ghi lại ở pha soi tổn thất:
- UI thread trung bình mỗi frame (ms) — đây là chỗ kỳ vọng giảm
- số cột vượt ngưỡng (frame giật), DevTools tô đậm

Muốn biết widget nào tốn: bật thêm **Enhanced Tracing → Track Layouts** hoặc
**Track Paints**, rồi xem tab **Timeline Events** của frame đang chọn.

**Lưu lại số liệu:** nút **Save** trên thanh công cụ Performance xuất ra file
JSON, mở lại được bằng nút Open. Lưu 2 file `baseline.json` / `optimized.json`
để đối chiếu sau, khỏi phải chạy lại.

### 4.4 Performance Overlay — kiểm tra nhanh trên máy

Bấm phím **`P`** trong terminal `flutter run` → hiện 2 đồ thị chồng lên app
ngay trên điện thoại (trên = GPU/raster, dưới = UI). Thanh đỏ = frame vượt
16 ms.

Không định lượng bằng DevTools nhưng tiện để quay video demo hoặc kiểm tra
nhanh mà không cần rời mắt khỏi máy.

### 4.5 Memory

Tab **Memory**, để chạy suốt 15 phút của kịch bản.

- **Dart Heap**: có leo dần suốt phiên không (rò phía Dart)
- **RSS**: tổng bộ nhớ tiến trình, ghi lại đỉnh
- Nút **GC** để ép thu gom: nếu ép GC mà heap không tụt → rò thật

⚠️ DevTools **không tách được** native bitmap / GPU memory. Phần nghi ngờ rò
nặng nhất (bitmap mỗi frame, image cache) phải xem bằng mục 5 (Android
`graphics_kb`/`native_heap_kb`) hoặc mục 6 (Instruments Allocations).

### 4.6 CPU Profiler — chỉ thấy phía Dart

Tab **CPU Profiler** → **Record** ~10 giây ở pha soi tổn thất → **Stop**.

Xem **Bottom Up** để biết hàm Dart nào tốn nhất. Kỳ vọng thấy
`onStreamingData` → `DetectionOutput.fromJson` → `_filterToViewport`.

⚠️ Đây **chỉ là Dart isolate**. Inference của 3 model chạy trên luồng native và
**không xuất hiện ở đây**. Đừng đọc biểu đồ này rồi kết luận "CPU thấp" — nó
không nhìn thấy phần tốn nhất.

### 4.7 So baseline với optimized

```bash
# Lần 1 — baseline
git stash                      # cất thay đổi đang dở
git checkout fa4552f
cd example && flutter run --profile -d <device_id>
#   … chạy kịch bản mục 3, Save JSON, chụp Rebuild Stats

# Lần 2 — optimized
git checkout performance
git stash pop
cd example && flutter run --profile -d <device_id>
#   … lặp lại y hệt
```

Giữa hai lần: **để máy nguội 15–20 phút** (mục 2).

## 5. Android — nhiệt & bộ nhớ native (không cần sửa code)

[`tool/measure_android.sh`](../tool/measure_android.sh) là script ngoài, chỉ gọi
`adb`, **không đụng gì vào app**.

```bash
# Terminal 1
flutter run --profile -d <device>

# Terminal 2 — chạy đúng lúc vào màn camera
./tool/measure_android.sh com.example.example 900 baseline
```

Xuất `build/perf/baseline-<stamp>.csv`, 5 giây/dòng:

| Cột | Đọc thế nào |
|---|---|
| `battery_c` | **đường cong nhiệt** — biểu đồ chủ đạo của báo cáo |
| `thermal_status` | 0=NONE…4=CRITICAL; HĐH bắt đầu throttle ở phút thứ mấy |
| `cpu_pct` | tải CPU cả process, **gồm cả luồng native** |
| `java_heap_kb` | răng cưa biên độ lớn ⇒ GC churn |
| `native_heap_kb`, `graphics_kb` | leo dần không tụt ⇒ rò bitmap |
| `pss_total_kb` | tổng bộ nhớ — đối chiếu nguy cơ OOM |

Script còn in `gfxinfo` (jank / 95th percentile) và các mốc đổi bậc nhiệt mà
`ThermalGovernor` tự log ra logcat:

```bash
adb logcat -s ThermalGovernor:I
# ThermalGovernor: Thermal tier normal → warm
```

Log này **đã có sẵn trong code**, không phải thêm gì.

---

## 6. iOS — nhiệt & CPU/GPU (không cần sửa code)

iOS **không cho bên thứ ba đọc nhiệt độ pin**, không có `adb` tương đương. Hai
nguồn thay thế, cả hai đều zero-code:

### 6.1 Mốc đổi bậc nhiệt — Console.app

`ThermalGovernor` gọi `NSLog` mỗi lần đổi bậc (code đã có sẵn).

Console.app → chọn thiết bị ở cột trái → ô search gõ `ThermalGovernor` →
Start streaming. Sẽ thấy dòng có timestamp:
```
ThermalGovernor: thermal tier normal → warm
```
Đây chính là timeline nhiệt của iOS. Chụp lại kèm mốc phút.

### 6.2 Instruments

```bash
./tool/measure_ios.sh com.example.example 900 baseline
```
hoặc mở GUI: Instruments → chọn template → chọn thiết bị + app → Record.

| Template | Cho biết |
|---|---|
| **Power Profiler** | CPU/GPU/Display power theo thời gian, kèm track **Thermal State** |
| **Time Profiler** | inference hay UI thread đang ăn CPU (thấy được luồng native — thứ DevTools mù) |
| **Allocations** | persistent bytes; lọc `CVPixelBuffer` / JPEG data để soi rò |
| **Animation Hitches** | jank UI, đối chiếu chéo với DevTools |
| **Metal System Trace** | tải GPU khi 3 model chạy song song |

CLI cho template khác:
```bash
xcrun xctrace record --template 'Allocations' \
  --device <UDID> --attach com.example.example \
  --time-limit 900s --output build/perf/alloc.trace
```
Lấy UDID: `xcrun devicectl list devices`

---

## 7. Bảng kết quả đề xuất

| Chỉ số | Nguồn | baseline | optimized | Δ |
|---|---|---|---|---|
| Nhiệt độ pin sau 15 phút (°C) | Android script | | | |
| Thời điểm chạm thermal MODERATE (phút) | script / Console.app | | | |
| CPU trung bình phút 10–15 (%) | script / Time Profiler | | | |
| PSS đỉnh (MB) | script / Allocations | | | |
| Java heap dao động (MB) | script | | | |
| Jank ≥ 16 ms (% frame) | gfxinfo / DevTools | | | |
| **Rebuild `CameraBottomBar` / giây** | **DevTools** | | | |
| **UI thread ms/frame ở pha inspection** | **DevTools** | | | |

Chạy **3 lần mỗi cấu hình**, lấy trung vị. Nhiệt độ dao động 1–2 °C giữa các
lần là bình thường; một lần đo duy nhất không đủ kết luận.

---

## 8. Nếu chỉ dùng DevTools, không dùng gì khác

Vẫn ra được báo cáo, nhưng phạm vi kết luận hẹp lại:

**Kết luận được:** "Số widget rebuild ở pha soi tổn thất giảm từ N xuống M mỗi
giây; thời gian UI thread mỗi frame giảm từ X xuống Y ms."

**KHÔNG kết luận được:** bất cứ điều gì về nhiệt độ, về governor, hay về bộ nhớ
native. Muốn nói "app mát hơn" thì bắt buộc phải có mục 5 hoặc 6.

Chi phí thêm cho mục 5 gần như bằng 0 — script `adb` chạy song song, không sửa
code, không build lại.
