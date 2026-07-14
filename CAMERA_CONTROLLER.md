# Luồng chụp ảnh — `CameraController`

Tài liệu mô tả máy trạng thái chụp ảnh trong
[`camera_controller.dart`](lib/src/features/camera/presentation/controller/camera_controller.dart),
bao gồm cả message hiển thị (`_setMessage`) theo từng bước.

Mọi message hiển thị qua `_setMessage(CameraMessage(message, type))`. `type`
quyết định màu/icon tooltip: `guide / info / warning / loading / success`.
Tooltip đã hiển thị sẽ được giữ tối thiểu **3s** trước khi message/phase khác
được phép thay thế. Ngoại lệ: message phản hồi một sự kiện vừa xảy ra có thể
dùng `_setMessage(..., immediate: true)` để hiển thị ngay, ví dụ chụp thành
công và điều hướng sau thao tác của người dùng.

---

## Tổng quan: 2 giai đoạn lớn

```mermaid
flowchart TD
    A["GIAI ĐOẠN 1: CHỤP ẢNH TOÀN CẢNH<br/>inspectionPhase == null<br/>carDamage OFF · OCR ON<br/>Mục tiêu: đủ bộ phận + đọc được biển số → tự chụp"]
    B["GIAI ĐOẠN 2: SOI TỔN THẤT<br/>inspectionPhase != null<br/>carDamage ON · OCR OFF<br/>panoramicGuide → scanning → detectionReady → detailGuide"]

    A -->|"chụp toàn cảnh xong"| B
    B -->|"classifier nhận diện góc khác<br/>ở pha cho phép auto-switch"| A
```

---

## Cổng vào: `onStreamingData(frame)`

Mỗi frame YOLO được phân loại theo `type` / `modelId`:

```mermaid
flowchart TD
    F["frame đến"] --> G{"_captureStarted?"}
    G -->|"chưa bấm 'Bắt đầu chụp ảnh xe'"| SKIP["BỎ QUA"]
    G -->|rồi| T{"type / modelId?"}

    T -->|"classify (carCorner)"| C["Xác định góc xe (segment)"]
    C --> C0{"đang khóa góc<br/>và detect góc khác?"}
    C0 -->|"có, phase cho phép"| C4["_autoSwitchToDetectedSegment()<br/>4-góc ON: hoàn tất góc cũ<br/>4-góc OFF: chỉ đổi góc, không tô xanh nếu chưa có ảnh"]
    C0 -->|"không"| C1{"góc đổi & chưa khóa?"}
    C1 -->|"góc đã có ảnh / 4-góc OFF & đã có ảnh đầu"| C2["startDamageScanning() → GĐ2"]
    C1 -->|"ngược lại"| C3["updateMessage() → GĐ1"]

    T -->|"ocr"| O["readable? cập nhật _latestPlateReadable<br/>readable → updateMessage()"]
    T -->|"detect2 (carPart)"| P["lọc viewport, cập nhật bộ phận thấy được<br/>biển rời khung → readable=false → updateMessage()"]
    T -->|"detect (carDamage)"| D["lọc viewport → _maybeShowDetectionReady()"]
```

---

## GIAI ĐOẠN 1 — Chụp ảnh toàn cảnh

Chỉ chạy khi `inspectionPhase == null`.

- `hasPlate` = thấy class `"Biển số xe"`
- `allPresent` = thấy Biển + Cửa + Cản trước theo góc hiện tại

```mermaid
flowchart TD
    U["updateMessage()"] --> Q1{"thấy biển?"}
    Q1 -->|không| M1["msg: initialGuide (guide)<br/>'Vui lòng di chuyển về góc chéo ...'"]
    Q1 -->|có| Q2{"thấy cửa?"}
    Q2 -->|chưa| M2["msg: moveBackGuide (info)<br/>'Lùi camera ra xa để chụp ảnh toàn cảnh xe'"]
    Q2 -->|"có (allPresent)"| H["set _holdStillShownAt (lần đầu)<br/>giữ holdStill tối thiểu 3s"]

    H --> Q3{"OCR readable && đã giữ ≥3s<br/>&& prompt rõ biển đã hiện đủ 3s?"}
    Q3 -->|có| CAP["_triggerAutoCapture()"]
    Q3 -->|không| Q4{"_platePromptShown<br/>(đã chờ OCR 5s)?"}
    Q4 -->|có| M3["msg: movePlateClearGuide (warning)<br/>'Vui lòng di chuyển camera để biển số rõ nét...'<br/>giữ tối thiểu 3s"]
    Q4 -->|không| M4["msg: holdStillGuide (loading)<br/>'Hãy giữ yên điện thoại. Đang nhận diện biển số'<br/>+ _ensurePlateReadTimer(5s)"]
```

### `_triggerAutoCapture()` — ảnh toàn cảnh

```mermaid
flowchart TD
    T0["_triggerAutoCapture()"] --> T1["reset OCR/readable, holdStill, plate timer"]
    T1 --> T2["capturePhoto(immediate:true)<br/>blink trắng, lưu ảnh"]
    T2 --> T3["đánh dấu segment có panoramic<br/>_firstPanoramicCaptured=true<br/>_classificationLocked=true"]
    T3 --> T4["msg: plateValidCaptured (success)<br/>'Biển số hợp lệ, chụp ảnh thành công'<br/>giữ 3s"]
    T4 --> T5["setInspectionPhase(panoramicGuide)<br/>msg: inspectDamageGuide (info)<br/>+ noDetectionWarningTimer(10s)"]
```

---

## GIAI ĐOẠN 2 — Soi tổn thất

### State machine chính

```mermaid
stateDiagram-v2
    [*] --> panoramicGuide

    panoramicGuide: panoramicGuide\nmsg inspectDamageGuide\nchờ tổn thất hoặc chuyển góc
    scanning: scanning\nmsg null\nchờ tổn thất
    warning: warning\nmsg noDamageDetectedGuide\nhiện hand hint tới nút chụp\nkhông tự rời góc
    detectionReady: detectionReady\nmsg damageDetectedGuide\nnút [Xác nhận] [Thiếu tổn thất]\nmỗi 10s chụp ngầm
    capturingDamage: capturingDamage\ncapturePhoto khi Xác nhận
    detailGuide: detailGuide\nmsg detailPhotoGuide\ncó detection → xác nhận ngay\n10s chưa detect → auto-chụp 1 ảnh
    detailWait: detailWait\nsau auto-chụp detail\nchờ thêm 5s
    continueOrChange: continueOrChange\nmsg continueToNextDamage / moveCameraToMissing\nsau 10s quay lại scanning
    rgoc: _autoSwitchToDetectedSegment()\n4-góc ON: hoàn tất góc cũ\n4-góc OFF: chỉ đổi góc nếu chưa có ảnh

    panoramicGuide --> scanning: có detection
    panoramicGuide --> warning: 10s không thấy tổn thất
    panoramicGuide --> rgoc: classifier detect góc khác

    scanning --> detectionReady: có detection
    scanning --> warning: 10s không thấy tổn thất
    scanning --> rgoc: classifier detect góc khác

    warning --> detectionReady: có detection
    warning --> continueOrChange: user bấm chụp manual\ncapture thành công
    warning --> warning: không thao tác\nvẫn chờ detection

    detectionReady --> detectionReady: không bấm gì sau mỗi 10s\nchụp ngầm, giữ tooltip
    detectionReady --> capturingDamage: Xác nhận
    detectionReady --> continueOrChange: Thiếu tổn thất

    capturingDamage --> detailGuide: vừa chụp ảnh tổng quan
    capturingDamage --> continueOrChange: vừa chụp ảnh chi tiết

    detailGuide --> detectionReady: có detection
    detailGuide --> detailWait: 10s chưa detect\nchụp ngầm 1 ảnh
    detailWait --> detectionReady: trong 5s sau ảnh ngầm có detection
    detailWait --> continueOrChange: hết 5s vẫn chưa detect

    continueOrChange --> detectionReady: có detection mới
    continueOrChange --> scanning: sau 10s
    continueOrChange --> rgoc: classifier detect góc khác

    rgoc --> [*]
```

### Flow overview + ảnh chi tiết

```mermaid
flowchart TD
    A["Đã chụp toàn cảnh"] --> B["msg: inspectDamageGuide<br/>'Đưa camera lại gần vị trí tổn thất...'"]
    B --> C{"Nhận diện được tổn thất?"}
    C -->|có| D["msg: damageDetectedGuide<br/>Buttons: Xác nhận / Thiếu tổn thất"]
    C -->|"không, sau 10s"| W["msg: noDamageDetectedGuide (warning)<br/>'Tổn thất chưa được nhận diện...'<br/>hiện hand.png trỏ nút chụp"]

    W -->|"user bấm chụp manual"| WM["capturePhoto(immediate:true)<br/>lưu ảnh"]
    WM --> N["msg: continueToNextDamage<br/>'Tiếp tục di chuyển camera đến vùng có tổn thất khác'"]
    W -->|"không bấm"| W
    W -->|"có detection"| D

    D -->|"không bấm gì sau mỗi 10s"| DA["auto capture ngầm<br/>flashTick:false"]
    DA --> D
    D -->|"Thiếu tổn thất"| G["msg: moveCameraToMissing<br/>giữ 10s rồi scanning"]
    D -->|"Xác nhận"| E["capturePhoto(immediate:true)<br/>msg captureSuccess 3s"]

    E --> H["msg: detailPhotoGuide<br/>'Di chuyển camera đến gần vùng có tổn thất để chụp ảnh chi tiết'"]
    H -->|"có detection"| J["msg: damageDetectedGuide<br/>Buttons: Xác nhận / Thiếu tổn thất"]
    H -->|"sau 10s chưa detect"| I["auto capture detail ngầm 1 ảnh<br/>flashTick:false"]
    I -->|"trong 5s có detection"| J
    I -->|"sau 5s vẫn chưa detect"| N

    J -->|"không bấm gì sau mỗi 10s"| JA["auto capture ngầm<br/>flashTick:false"]
    JA --> J
    J -->|"Thiếu tổn thất"| G
    J -->|"Xác nhận"| K["capturePhoto(immediate:true)<br/>msg captureSuccess 3s"]
    K --> N

    N -->|"sau 10s"| S["scanning"]
    G -->|"sau 10s"| S
    S --> C
```

### Warning 10s không thấy tổn thất + hand hint

```mermaid
flowchart TD
    N0["_onNoDetectionWarningTimeout()<br/>(panoramicGuide / scanning)"] --> N1["msg: noDamageDetectedGuide (warning)<br/>'Tổn thất chưa được nhận diện.<br/>Vui lòng bấm chụp ảnh để AI tiếp tục đánh giá'"]
    N1 --> N2["CameraScreen hiển thị ManualCaptureHintHand<br/>dùng assets/images/hand.png<br/>trỏ tới nút chụp"]
    N2 --> Q{"User làm gì?"}
    Q -->|"không bấm"| WAIT["giữ warning, tiếp tục chờ detection<br/>không tự rời góc"]
    WAIT -->|"có detection"| DR["detectionReady"]
    Q -->|"bấm chụp manual"| CAP["manualCapture()<br/>capturePhoto(immediate:true)"]
    CAP --> NEXT["msg: continueToNextDamage<br/>hand tự ẩn vì message đổi"]
    NEXT -->|"sau 10s"| SCAN["scanning"]
```

### Detail guide theo feedback khách

```mermaid
sequenceDiagram
    participant UI as User/UI
    participant C as CameraController
    participant AI as carDamage stream

    C->>UI: msg detailPhotoGuide
    Note over C: Start _detailTimer = 10s
    AI-->>C: detection frame
    alt có detection trước timeout
        C->>UI: msg damageDetectedGuide
    else chưa có detection sau 10s
        C->>C: _onDetailTimeout()
        C->>C: capturePhoto(immediate:true, flashTick:false)
        Note over C: Start post-capture timer = 5s
        C->>C: sau 5s _onDetailPostCaptureTimeout()
        alt có detection
            C->>UI: msg damageDetectedGuide
        else vẫn chưa có detection
            C->>UI: msg continueToNextDamage
            C->>C: sau 10s startDamageScanning()
        end
    end
```

### Tự động chuyển góc — `_autoSwitchToDetectedSegment()`

```mermaid
flowchart TD
    R0["Classifier detect góc khác<br/>khi đang panoramicGuide / scanning / continueOrChange"] --> R1["huỷ timer, setInspectionPhase(null)<br/>chỉ đánh dấu góc cũ completed khi require4Angles=true"]
    R1 --> R2["set _activeSegmentIndex = góc mới"]
    R2 --> R3{"góc mới bỏ qua panorama?"}
    R3 -->|có| R4["lock góc mới<br/>startDamageScanning()"]
    R3 -->|không| R5["updateMessage()<br/>canh/chụp panorama góc mới"]
```

---

## Bảng message ↔ type ↔ ngữ cảnh

| Message (StringSheet) | type | Khi nào |
|---|---|---|
| `*Guide` (`frontLeftGuide`, `frontRightGuide`, ...) | guide | GĐ1: chưa thấy biển / điều hướng góc |
| `moveBackGuide` | info | GĐ1: thấy biển, chưa thấy cửa |
| `holdStillGuide` | loading | GĐ1: đủ bộ phận, đang đọc biển; giữ ≥3s mới chụp |
| `movePlateClearGuide` | warning | GĐ1: quá 5s chưa đọc được biển; giữ warning ≥3s |
| `plateValidCaptured` | success | Chụp toàn cảnh xong; giữ 3s |
| `inspectDamageGuide` | info | Vào `panoramicGuide` |
| `damageDetectedGuide` | info | `detectionReady`, có nút `Xác nhận` / `Thiếu tổn thất` |
| `moveCameraToMissing` | info | User bấm `Thiếu tổn thất`; giữ 10s rồi quét lại |
| `detailPhotoGuide` | info | Sau khi xác nhận ảnh tổng quan; có detection thì mở xác nhận ngay, không detect sau 10s thì auto-chụp ảnh chi tiết |
| `continueToNextDamage` | info | Sau khi xác nhận ảnh chi tiết, sau manual capture từ warning, hoặc detailGuide 10s + 5s vẫn không detect |
| `noDamageDetectedGuide` | warning | 10s không thấy tổn thất ở `panoramicGuide` / `scanning`; hiện hand hint |
| `null` | — | `scanning`, hoặc rời góc (4-góc OFF / đã đủ góc) |

---

## Các điểm chụp ảnh & blink

| Đường chụp | Lệnh | Blink? | Ghi chú |
|---|---|---|---|
| Toàn cảnh từ biển số | `capturePhoto(immediate:true)` | Có | Sau khi OCR readable và giữ khung đủ 3s |
| Thủ công (nút shutter) | `capturePhoto(immediate:true)` | Có | Nếu đang ở `noDamageDetectedGuide`, capture xong chuyển `continueToNextDamage` |
| Xác nhận tổn thất (bấm tay) | `capturePhoto(immediate:true, flashTick:true)` | Có | Sau ảnh tổng quan → `detailGuide`; sau ảnh chi tiết → `continueToNextDamage` |
| Auto-chụp ngầm khi đang xác nhận tổn thất | `capturePhoto(immediate:true, flashTick:false)` | Không | Mỗi 10s khi user không bấm gì, vẫn giữ `damageDetectedGuide` |
| Auto-chụp ảnh chi tiết | `capturePhoto(immediate:true, flashTick:false)` | Không | Một lần sau 10s ở `detailGuide` nếu chưa detect; sau đó chờ thêm 5s |

Blink được vẽ ngay trước lệnh native capture (`notifyListeners()` sau khi tăng
`_captureFlashTick`) để đồng bộ đúng khoảnh khắc chụp.

---

## Ghi chú gating OCR (canh khung biển số)

- Ảnh toàn cảnh được crop theo viewport preview dưới aspect-fill. Native tính lại
  crop rect normalized chính xác như `capturePhoto`, bao gồm offset do cover/crop.
- OCR chỉ coi là "đọc được biển" khi toàn bộ bbox biển số nằm trong crop rect đó
  sau khi inset margin an toàn ở cả 2 trục. Nhờ vậy biển số đọc được nhưng bị lẹm
  ở mép ảnh crop sẽ không được dùng để xác nhận ảnh toàn cảnh hợp lệ.
