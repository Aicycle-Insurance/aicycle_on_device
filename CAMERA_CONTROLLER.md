# Luồng chụp ảnh — `CameraController`

Tài liệu mô tả máy trạng thái chụp ảnh trong
[`camera_controller.dart`](lib/src/features/camera/presentation/controller/camera_controller.dart),
bao gồm cả message hiển thị (`_setMessage`) theo từng bước.

Mọi message hiển thị qua `_setMessage(CameraMessage(message, type))`. `type`
quyết định màu/icon tooltip: `guide / info / warning / loading / success`.

---

## Sơ đồ thiết kế tổng thể (bản vẽ)

### Bản vẽ 1 — Giai đoạn chụp ảnh toàn cảnh (đọc biển số)

```mermaid
flowchart TD
    A["check góc và xác định góc<br/>người dùng đang đứng"]
    B["'Vui lòng di chuyển về góc chéo ...'"]
    C["'Lùi camera ra xa để chụp ảnh toàn cảnh xe'"]
    D["'Hãy giữ yên điện thoại. AI đang nhận diện biển số'"]
    E["Call API nhận diện biển số,<br/>lưu ảnh tại thời điểm call"]
    F["'Vui lòng di chuyển camera để biển số<br/>rõ nét trong khung hình'"]
    G["Hiện nháy, tự động chụp ảnh. Hiện thông báo<br/>'Biển số hợp lệ, chụp ảnh thành công'<br/>Lưu ảnh tại thời điểm call API và ảnh vừa chụp tự động<br/>để đẩy lên server sau khi Hoàn thành"]

    A --> B
    B -->|"chưa đủ bộ phận"| C
    B -->|"đủ bộ phận"| D
    D --> E
    E --> F
    F -->|"(delay 2s)"| D
    F -->|"đọc được biển số"| G
```

### Bản vẽ 2 — Giai đoạn soi tổn thất (overview + chi tiết)

```mermaid
flowchart TD
    A["chụp ảnh toàn cảnh đầu tiên"]
    B["'Đưa camera lại gần vị trí tổn thất.<br/>Nếu không có tổn thất, hãy chuyển sang vị trí khác'"]
    C["Nhận diện được tổn thất"]
    D["'Các tổn thất đã được ghi nhận. Vui lòng kiểm tra<br/>và xác nhận' (Button Thiếu tổn thất / Xác nhận)"]
    E["Chụp ảnh"]
    F["Tự động chụp"]
    G["'Hãy đưa camera lại gần vị trí tổn thất còn thiếu'"]
    H["'Di chuyển camera đến gần vùng có tổn thất<br/>để chụp ảnh chi tiết' (delay 3s)"]
    I["Tự động chụp"]
    J["'Các tổn thất đã được ghi nhận. Vui lòng kiểm tra<br/>và xác nhận' (Button Thiếu tổn thất / Xác nhận)"]
    K["Chụp ảnh"]
    L["Tự động chụp"]
    M["'Hãy đưa camera lại gần vị trí tổn thất còn thiếu'"]
    N["'Tiếp tục di chuyển camera đến<br/>vùng có tổn thất khác'"]

    A --> B
    B --> C
    C --> D
    D -->|"Bấm xác nhận"| E
    D -->|"Không bấm gì sau 5s"| F
    D -->|"Bấm 'Thiếu tổn thất'"| G
    E --> H
    F --> H
    H -->|"Nhận diện được tổn thất"| J
    H -->|"Không Nhận diện được tổn thất sau 3s"| I
    I -->|"Nhận diện được tổn thất"| J
    I -->|"sau 3s vẫn k nhận diện được tổn thất"| J
    J -->|"Bấm xác nhận"| K
    J -->|"Không bấm gì sau 5s"| L
    J -->|"Bấm 'Thiếu tổn thất'"| M
    K --> N
    L --> N
    N --> C
```

> 2 sơ đồ trên là **bản thiết kế gốc**. Một vài chi tiết được nói rõ hơn / khác
> với code hiện tại: OCR biển số chạy **on-device** (không phải "call API");
> delay giữ yên hiện là **3s** (không phải 2s). Phần dưới mô tả đúng theo code.

---

## Tổng quan: 2 giai đoạn lớn

```mermaid
flowchart TD
    A["GIAI ĐOẠN 1: CHỤP ẢNH TOÀN CẢNH (panorama)<br/>inspectionPhase == null → carDamage OFF, OCR ON<br/>Mục tiêu: canh đủ bộ phận + đọc được biển số → tự chụp"]
    B["GIAI ĐOẠN 2: SOI TỔN THẤT (inspection)<br/>inspectionPhase != null → carDamage ON, OCR OFF<br/>panoramicGuide → scanning → detectionReady → capturing → detailGuide → continueOrChange"]
    A -->|"chụp toàn cảnh xong"| B
    B -->|"completeCurrentAngle() · rời góc"| A
```

---

## Cổng vào: `onStreamingData(frame)`

Mỗi frame YOLO (~30fps) được phân loại theo `type` / `modelId`:

```mermaid
flowchart TD
    F["frame đến"] --> G{"_captureStarted?"}
    G -->|"chưa bấm 'Bắt đầu chụp ảnh xe'"| SKIP["BỎ QUA"]
    G -->|rồi| T{"type?"}

    T -->|"classify (carCorner)"| C["Xác định góc (segment)"]
    C --> C1{"góc đổi & chưa khoá?"}
    C1 -->|"góc đã có ảnh / 4-góc OFF & đã có ảnh đầu"| C2["startDamageScanning() → GĐ2"]
    C1 -->|"ngược lại"| C3["updateMessage() → GĐ1"]

    T -->|ocr| O["readable? cập nhật _latestPlateReadable<br/>nếu readable → updateMessage()"]

    T -->|"detect2 (carPart)"| P["lọc viewport, cập nhật bộ phận thấy được<br/>biển rời khung → readable=false → updateMessage()"]

    T -->|"detect (carDamage)"| D["lọc viewport → _maybeShowDetectionReady()"]
```

---

## GIAI ĐOẠN 1 — `updateMessage()` (canh khung + đọc biển)

Chỉ chạy khi `inspectionPhase == null`.

- `hasPlate` = thấy "Biển số xe"
- `allPresent` = thấy Biển + Cửa + Cản trước

```mermaid
flowchart TD
    U["updateMessage()"] --> Q1{"thấy biển?"}
    Q1 -->|không| M1["msg: initialGuide (guide)<br/>'Di chuyển về góc chéo …'"]
    Q1 -->|có| Q2{"thấy cửa?"}
    Q2 -->|chưa| M2["msg: moveBackGuide (info)<br/>'Lùi camera ra xa…'"]
    Q2 -->|"có (allPresent)"| H["set _holdStillShownAt (lần đầu)<br/>đo tối thiểu 3s"]

    H --> Q3{"readable && đã giữ ≥3s?"}
    Q3 -->|có| CAP["★ _triggerAutoCapture()"]
    Q3 -->|không| Q4{"_platePromptShown<br/>(đã quá 5s)?"}
    Q4 -->|có| M3["msg: movePlateClearGuide (warning)<br/>'Di chuyển để biển rõ nét…'"]
    Q4 -->|không| M4["msg: holdStillGuide (loading)<br/>'Giữ yên… đang nhận diện biển số'<br/>+ _ensurePlateReadTimer (5s)"]
```

### `_triggerAutoCapture()` ★ — chụp ảnh toàn cảnh

```mermaid
flowchart TD
    T0["_triggerAutoCapture()"] --> T1["reset readable / _holdStillShownAt, huỷ timer"]
    T1 --> T2["capturePhoto(immediate:true) 💥 BLINK trắng<br/>lưu ảnh → _panoramicCapturedSegments + _completedSegments<br/>_firstPanoramicCaptured=true · _classificationLocked=true"]
    T2 --> T3["msg: plateValidCaptured (success)<br/>'Biển số hợp lệ, chụp thành công' — giữ 3s"]
    T3 --> T4["setInspectionPhase(panoramicGuide) → GĐ2<br/>msg: inspectDamageGuide (info)<br/>+ _startNoDetectionTimer (10s)"]
```

---

## GIAI ĐOẠN 2 — Soi tổn thất (máy trạng thái `InspectionPhase`)

```mermaid
stateDiagram-v2
    [*] --> panoramicGuide

    panoramicGuide: panoramicGuide\nmsg inspectDamageGuide (info)\nnut [X]=quet  [Chuyen goc]
    scanning: scanning\nmsg null
    detectionReady: detectionReady\nmsg damageDetectedGuide (info)\nnut [Xac nhan][Thieu ton that]\n5s -> tu confirmDamage
    capturingDamage: capturingDamage\ncapturePhoto (BLINK, tru auto 5s)
    detailGuide: detailGuide\nmsg detailPhotoGuide (info)
    continueOrChange: continueOrChange\nmsg continueToNextDamage / moveCameraToMissing (info)

    panoramicGuide --> scanning: co detection / bam X
    scanning --> detectionReady: co detection
    scanning --> rgoc: 10s khong thay ton that
    detectionReady --> capturingDamage: Xac nhan (hoac auto 5s)
    detectionReady --> continueOrChange: Thieu ton that (rejectDamage)
    capturingDamage --> detailGuide: vua chup anh tong quan
    capturingDamage --> continueOrChange: vua chup anh chi tiet
    detailGuide --> detectionReady: co ton that (trong 3s)
    detailGuide --> capturingDamage: het 3s, tu chup chi tiet
    detailGuide --> continueOrChange: da auto-chup & van trong
    continueOrChange --> scanning: sau 5s

    rgoc: completeCurrentAngle()\nve GD1
    rgoc --> [*]
```

### 10s không thấy tổn thất — `_onNoDetectionTimeout()`

```mermaid
flowchart TD
    N0["_onNoDetectionTimeout()<br/>(pha scanning / panoramicGuide)"] --> N1["msg: noDamageDetectedGuide (warning)<br/>'Tổn thất chưa nhận diện…'"]
    N1 -->|"giữ 5s"| N2["completeCurrentAngle() — RỜI GÓC"]
```

### Rời góc — `completeCurrentAngle()`

```mermaid
flowchart TD
    R0["completeCurrentAngle()"] --> R1["huỷ mọi timer<br/>_classificationLocked=false<br/>setInspectionPhase(null) → về GĐ1"]
    R1 --> R2{"config 4 góc?"}
    R2 -->|BẬT| R3["msg: guide tới góc chưa xong tiếp theo<br/>(frontLeft/Right…) hoặc null nếu đã đủ 4 góc"]
    R2 -->|TẮT| R4["msg: null (user tự do di chuyển)"]
```

---

## Bảng message ↔ type ↔ ngữ cảnh

| Message (StringSheet) | type | Khi nào |
|---|---|---|
| `*Guide` (frontLeft/Right…) | guide | GĐ1: chưa thấy biển / điều hướng góc |
| `moveBackGuide` | info | GĐ1: thấy biển, chưa thấy cửa |
| `holdStillGuide` | loading | GĐ1: đủ bộ phận, đang đọc biển (≥3s mới chụp) |
| `movePlateClearGuide` | warning | GĐ1: quá 5s chưa đọc được biển |
| `plateValidCaptured` | success | Chụp toàn cảnh xong (giữ 3s) |
| `inspectDamageGuide` | info | Vào panoramicGuide |
| `damageDetectedGuide` | info | detectionReady |
| `moveCameraToMissing` | info | Bấm "Thiếu tổn thất" |
| `detailPhotoGuide` | info | detailGuide |
| `continueToNextDamage` | info | Sau khi chụp chi tiết / auto-capture trống |
| `noDamageDetectedGuide` | warning | 10s không thấy tổn thất (trước khi rời góc) |
| `null` | — | scanning, hoặc rời góc (4-góc TẮT / đã đủ góc) |

---

## Các điểm chụp ảnh & blink

| Đường chụp | Lệnh | Blink? |
|---|---|---|
| Toàn cảnh từ biển số | `capturePhoto(immediate:true)` | ✅ |
| Thủ công (nút shutter) | `capturePhoto(immediate:true)` | ✅ |
| Xác nhận tổn thất (bấm tay) | `capturePhoto(immediate:true, flashTick:true)` | ✅ |
| Auto-chụp tổn thất sau 5s | `confirmDamage(flashTick:false)` | ❌ (cố ý) |
| Auto-chụp ảnh chi tiết | `capturePhoto(flashTick:false)` | ❌ (cố ý) |

> Blink được vẽ **ngay trước** lệnh native capture (`notifyListeners()` sau khi
> tăng `_captureFlashTick`) để đồng bộ đúng khoảnh khắc chụp.

---

## Ghi chú gating OCR (canh khung biển số)

- Ảnh toàn cảnh chỉ được crop theo **trục dọc** preview (`cropTop`/`cropBottom`
  = dải giữa 2 thanh trên/dưới), tương ứng trục X của buffer landscape.
- OCR (native) chỉ coi là "đọc được biển" khi box biển nằm trọn trong dải
  viewport (trục X) **và** cách mép trái/phải màn hình (trục Y) ≥ `ocrEdgeMargin`
  (0.05) — tránh chụp khi xe canh lệch sát mép.
