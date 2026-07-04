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
    D -->|"Không bấm gì sau mỗi 5s"| F
    D -->|"Bấm 'Thiếu tổn thất'"| G
    E --> H
    F -->|"Chụp ngầm, vẫn giữ D"| D
    H -->|"Nhận diện được tổn thất"| J
    H -->|"Không Nhận diện được tổn thất sau 3s"| I
    I -->|"Chụp ngầm, vẫn giữ H"| H
    J -->|"Bấm xác nhận"| K
    J -->|"Không bấm gì sau mỗi 5s"| L
    J -->|"Bấm 'Thiếu tổn thất'"| M
    K --> N
    L -->|"Chụp ngầm, vẫn giữ J"| J
    N --> C
```

> 2 sơ đồ trên đang phản ánh flow theo feedback mới của khách. Một vài chi tiết
> được nói rõ hơn / khác với bản vẽ ban đầu: OCR biển số chạy **on-device**
> (không phải "call API"); delay giữ yên hiện là **3s** (không phải 2s).
> Phần dưới mô tả đúng theo code.

---

## Tổng quan: 2 giai đoạn lớn

```mermaid
flowchart TD
    A["GIAI ĐOẠN 1: CHỤP ẢNH TOÀN CẢNH (panorama)<br/>inspectionPhase == null → carDamage OFF, OCR ON<br/>Mục tiêu: canh đủ bộ phận + đọc được biển số → tự chụp"]
    B["GIAI ĐOẠN 2: SOI TỔN THẤT (inspection)<br/>inspectionPhase != null → carDamage ON, OCR OFF<br/>panoramicGuide → scanning → detectionReady → capturing → detailGuide"]
    A -->|"chụp toàn cảnh xong"| B
    B -->|"classifier nhận diện góc khác<br/>→ _autoSwitchToDetectedSegment()"| A
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
    C --> C0{"đang khoá góc<br/>và detect góc khác?"}
    C0 -->|"có, ở pha cho phép auto-switch"| C4["_autoSwitchToDetectedSegment()<br/>hoàn tất góc cũ, kích hoạt góc mới"]
    C0 -->|"không"| C1{"góc đổi & chưa khoá?"}
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

    H --> Q3{"readable && đã giữ ≥3s<br/>&& prompt rõ biển đã hiện đủ 3s?"}
    Q3 -->|có| CAP["★ _triggerAutoCapture()"]
    Q3 -->|không| Q4{"_platePromptShown<br/>(đã quá 5s)?"}
    Q4 -->|có| M3["msg: movePlateClearGuide (warning)<br/>'Di chuyển để biển rõ nét…'<br/>giữ tối thiểu 3s"]
    Q4 -->|không| M4["msg: holdStillGuide (loading)<br/>'Giữ yên… đang nhận diện biển số'<br/>+ _ensurePlateReadTimer (5s)"]
```

### `_triggerAutoCapture()` ★ — chụp ảnh toàn cảnh

```mermaid
flowchart TD
    T0["_triggerAutoCapture()"] --> T1["reset readable / _holdStillShownAt, huỷ timer"]
    T1 --> T2["capturePhoto(immediate:true) 💥 BLINK trắng<br/>lưu ảnh → _panoramicCapturedSegments + _completedSegments<br/>_firstPanoramicCaptured=true · _classificationLocked=true"]
    T2 --> T3["msg: plateValidCaptured (success)<br/>'Biển số hợp lệ, chụp thành công' — giữ 3s"]
    T3 --> T4["setInspectionPhase(panoramicGuide) → GĐ2<br/>msg: inspectDamageGuide (info)<br/>+ _startNoDetectionWarningTimer (10s)"]
```

---

## GIAI ĐOẠN 2 — Soi tổn thất (máy trạng thái `InspectionPhase`)

```mermaid
stateDiagram-v2
    [*] --> panoramicGuide

    panoramicGuide: panoramicGuide\nmsg inspectDamageGuide (info)\nkhong co nut Chuyen goc
    scanning: scanning\nmsg null
    detectionReady: detectionReady\nmsg damageDetectedGuide (info)\nnut [Xac nhan][Thieu ton that]\nmoi 5s -> chup ngam
    capturingDamage: capturingDamage\ncapturePhoto khi bam Xac nhan
    detailGuide: detailGuide\nmsg detailPhotoGuide (info)
    continueOrChange: continueOrChange\nmsg continueToNextDamage / moveCameraToMissing (info)

    panoramicGuide --> scanning: co detection
    panoramicGuide --> rgoc: classifier detect goc khac
    scanning --> detectionReady: co detection
    scanning --> warning: 10s khong thay ton that
    scanning --> rgoc: classifier detect goc khac
    panoramicGuide --> warning: 10s khong thay ton that
    warning --> detectionReady: co detection
    detectionReady --> detectionReady: moi 5s chup ngam
    detectionReady --> capturingDamage: Xac nhan
    detectionReady --> continueOrChange: Thieu ton that (rejectDamage)
    capturingDamage --> detailGuide: vua chup anh tong quan
    capturingDamage --> continueOrChange: vua chup anh chi tiet
    detailGuide --> detectionReady: co ton that (tai moc 3s)
    detailGuide --> detailGuide: het 3s khong detection -> chup ngam
    continueOrChange --> detectionReady: co detection moi
    continueOrChange --> rgoc: classifier detect goc khac
    continueOrChange --> scanning: sau 5s

    warning: warning\nmsg noDamageDetectedGuide\nkhong tu roi goc
    rgoc: _autoSwitchToDetectedSegment()\nhoan tat goc cu, kich hoat goc moi
    rgoc --> [*]
```

### 10s không thấy tổn thất — warning-only

```mermaid
flowchart TD
    N0["_onNoDetectionWarningTimeout()<br/>(pha scanning / panoramicGuide)"] --> N1["msg: noDamageDetectedGuide (warning)<br/>'Tổn thất chưa nhận diện…'"]
    N1 --> N2["Tiếp tục chờ detection<br/>không tự completeCurrentAngle()"]
```

### Tự động chuyển góc — `_autoSwitchToDetectedSegment()`

```mermaid
flowchart TD
    R0["Classifier detect góc khác<br/>khi đang panoramicGuide / scanning / continueOrChange"] --> R1["huỷ timer, đánh dấu góc cũ completed<br/>setInspectionPhase(null)"]
    R1 --> R2["set _activeSegmentIndex = góc mới"]
    R2 --> R3{"góc mới bỏ qua panorama?"}
    R3 -->|có| R4["lock góc mới<br/>startDamageScanning()"]
    R3 -->|không| R5["updateMessage() để canh/chụp panorama góc mới"]
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
| `continueToNextDamage` | info | Sau khi user xác nhận ảnh chi tiết |
| `noDamageDetectedGuide` | warning | 10s không thấy tổn thất (chỉ cảnh báo, không tự rời góc) |
| `null` | — | scanning, hoặc rời góc (4-góc TẮT / đã đủ góc) |

---

## Các điểm chụp ảnh & blink

| Đường chụp | Lệnh | Blink? |
|---|---|---|
| Toàn cảnh từ biển số | `capturePhoto(immediate:true)` | ✅ |
| Thủ công (nút shutter) | `capturePhoto(immediate:true)` | ✅ |
| Xác nhận tổn thất (bấm tay) | `capturePhoto(immediate:true, flashTick:true)` | ✅ |
| Auto-chụp ngầm mỗi 5s khi đang xác nhận tổn thất | `capturePhoto(immediate:true, flashTick:false)` | ❌ (cố ý) |
| Auto-chụp ảnh chi tiết mỗi 3s khi detailGuide không có detection | `capturePhoto(immediate:true, flashTick:false)` | ❌ (cố ý) |

> Blink được vẽ **ngay trước** lệnh native capture (`notifyListeners()` sau khi
> tăng `_captureFlashTick`) để đồng bộ đúng khoảnh khắc chụp.

---

## Ghi chú gating OCR (canh khung biển số)

- Ảnh toàn cảnh được crop theo viewport preview dưới aspect-fill. Native tính lại
  crop rect normalized chính xác như `capturePhoto`, bao gồm offset do cover/crop.
- OCR chỉ coi là "đọc được biển" khi toàn bộ bbox biển số nằm trong crop rect đó
  sau khi inset margin an toàn ở cả 2 trục. Nhờ vậy biển số đọc được nhưng bị lẹm
  ở mép ảnh crop sẽ không được dùng để xác nhận ảnh toàn cảnh hợp lệ.
