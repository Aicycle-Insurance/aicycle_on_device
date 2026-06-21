# aicycle_on_device

Flutter SDK chạy model AI trên thiết bị (on-device) để phát hiện thiệt hại xe theo thời gian thực qua camera.

---

## Mục lục

- [Cài đặt](#cài-đặt)
- [Cấu hình nền tảng (Permissions)](#cấu-hình-nền-tảng-permissions)
- [Bắt đầu nhanh](#bắt-đầu-nhanh)
- [Hai cách sử dụng: `AICycleOnDevice` vs `AICycleOnDeviceCamera`](#hai-cách-sử-dụng-aicycleondevice-vs-aicycleondevicecamera)
  - [1. `AICycleOnDevice`](#1-aicycleondevice-widget)
  - [2. `AICycleOnDeviceCamera`](#2-aicycleondevicecamera-widget)
- [Chi tiết các tham số cấu hình](#chi-tiết-các-tham-số-cấu-hình)
  - [`AICycleConfig`](#aicycleconfig)
  - [`GeneralConfig`](#generalconfig-bắt-buộc)
  - [`CarInformation`](#carinformation-bắt-buộc)
  - [`ModelConfig`](#modelconfig-bắt-buộc)
  - [`DisplayConfig`](#displayconfig-tùy-chọn)
  - [`ValidateConfig`](#validateconfig-tùy-chọn)
  - [`VBIConfig`](#vbiconfig-bắt-buộc-khi-organization--vbi)
- [Callback `onComplete` và `onError`](#callback-oncomplete-và-onerror)
- [Dọn cache ảnh sau khi upload](#dọn-cache-ảnh-sau-khi-upload)

---

## Cài đặt

Thêm vào `pubspec.yaml` của app:

```yaml
dependencies:
  aicycle_on_device: ^0.0.2
```

Sau đó import:

```dart
import 'package:aicycle_on_device/aicycle_on_device.dart';
```

---

## Cấu hình nền tảng (Permissions)

SDK sử dụng camera, vị trí (geolocation) và lưu ảnh vào gallery. Cần khai báo quyền cho từng nền tảng.

### iOS — `ios/Runner/Info.plist`

```xml
<key>NSCameraUsageDescription</key>
<string>Ứng dụng cần camera để chụp ảnh kiểm định xe</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Ứng dụng cần vị trí để gắn toạ độ ảnh chụp</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Ứng dụng cần lưu ảnh đã chụp vào thư viện</string>
```

### Android — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

> SDK tự yêu cầu quyền (camera, vị trí) khi cần.

---

## Bắt đầu nhanh

```dart
import 'package:aicycle_on_device/aicycle_on_device.dart';
import 'package:flutter/material.dart';

void openInspection(BuildContext context) {
  final config = AICycleConfig(
    generalConfig: GeneralConfig(
      apiToken: '<API_TOKEN>',       // bắt buộc — liên hệ AICycle để được cấp
      documentId: '<DOCUMENT_ID>',   // bắt buộc — ID hồ sơ (so_id_hs)
      organization: AiCycleOrg.aicycle,
      environment: AiCycleEnvironment.stage,
    ),
    carInformation: CarInformation(
      companyName: 'toyota',
      modelName: 'vios',
      licensePlate: '30A12345',
    ),
    modelConfig: ModelConfig(), // dùng ngưỡng mặc định
  );

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => AICycleOnDeviceCamera(
        aiCycleConfig: config,
        onComplete: () => Navigator.pop(context),
        onError: (error) => debugPrint('SDK Error: $error'),
      ),
    ),
  );
}
```

---

## Hai cách sử dụng: `AICycleOnDevice` vs `AICycleOnDeviceCamera`

SDK cung cấp **2 widget điểm vào (entry point)**. Cả hai đều nhận `aiCycleConfig`, `onComplete`, `onError`. Khác nhau ở luồng chuẩn bị model:

| Tiêu chí | `AICycleOnDevice` | `AICycleOnDeviceCamera` |
|---|---|---|
| Màn hình quản lý / chọn model trước khi mở camera | ✅ Có (`ModelManagerScreen`) | ❌ Không |
| Tự tải & chuẩn bị model | Người dùng chọn model rồi mới tải | Tự tải toàn bộ model cần thiết |
| Phù hợp khi | Muốn người dùng xem/chọn model đã tải | Muốn vào thẳng camera, đơn giản nhất |
| Cách dùng | Push widget vào Navigator | Push widget vào Navigator |

> Bên trong, `AICycleOnDevice` sau khi người dùng chọn model sẽ tự push sang `AICycleOnDeviceCamera`. Nếu không cần màn chọn model, dùng thẳng `AICycleOnDeviceCamera`.

### 1. `AICycleOnDevice` (widget)

Hiển thị màn **Model Manager** để người dùng xem/chọn model trước, sau đó vào camera.

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => AICycleOnDevice(
      aiCycleConfig: config,
      onComplete: () => Navigator.pop(context),
      onError: (error) => showError(error),
    ),
  ),
);
```

**Tham số:**

| Tên | Kiểu | Bắt buộc | Mô tả |
|---|---|---|---|
| `aiCycleConfig` | `AICycleConfig` | ✅ | Toàn bộ cấu hình SDK (xem bên dưới). |
| `onComplete` | `void Function()?` | ❌ | Gọi khi hoàn tất luồng (sau khi upload xong). |
| `onError` | `void Function(String error)?` | ❌ | Gọi khi có lỗi (khởi tạo hồ sơ, tải model, …). |

Nút back trên màn Model Manager được điều khiển bằng [`DisplayConfig.showBackButton`](#displayconfig-tùy-chọn).

### 2. `AICycleOnDeviceCamera` (widget)

Điểm vào trực tiếp: tự tạo/lấy hồ sơ (folder), tự tải & chuẩn bị model rồi vào thẳng camera. Đây là cách dùng phổ biến nhất.

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => AICycleOnDeviceCamera(
      aiCycleConfig: config,
      onComplete: () => Navigator.pop(context),
      onError: (error) => showError(error),
    ),
  ),
);
```

**Tham số:**

| Tên | Kiểu | Bắt buộc | Mô tả |
|---|---|---|---|
| `aiCycleConfig` | `AICycleConfig` | ✅ | Toàn bộ cấu hình SDK. |
| `onComplete` | `void Function()?` | ❌ | Gọi khi hoàn tất luồng (sau khi upload ảnh). |
| `onError` | `void Function(String error)?` | ❌ | Gọi khi có lỗi. |
| `carCornerModelPath` | `String?` | ❌ | Đường dẫn model "góc xe" có sẵn (bỏ trống → SDK tự tải). |
| `carDamageModelPath` | `String?` | ❌ | Đường dẫn model "thiệt hại" có sẵn (bỏ trống → SDK tự tải). |
| `carPartModelPath` | `String?` | ❌ | Đường dẫn model "bộ phận xe" có sẵn (bỏ trống → SDK tự tải). |

> 3 tham số `*ModelPath` chủ yếu dùng nội bộ (khi đã có model từ màn chọn model). Bình thường không cần truyền — SDK tự tải.

---

## Chi tiết các tham số cấu hình

### `AICycleConfig`

Đối tượng gốc gom toàn bộ cấu hình.

| Trường | Kiểu | Bắt buộc | Mặc định | Mô tả |
|---|---|---|---|---|
| `generalConfig` | `GeneralConfig` | ✅ | — | Cấu hình chung (token, hồ sơ, môi trường…). |
| `modelConfig` | `ModelConfig` | ✅ | — | Ngưỡng confidence / IOU cho từng model. |
| `carInformation` | `CarInformation` | ✅ | — | Thông tin xe được kiểm định. |
| `displayConfig` | `DisplayConfig` | ❌ | `DisplayConfig()` | Tuỳ chỉnh hiển thị. |
| `validateConfig` | `ValidateConfig` | ❌ | `ValidateConfig()` | Tuỳ chỉnh ràng buộc chụp ảnh. |
| `vbiConfig` | `VBIConfig?` | ⚠️ | `null` | **Bắt buộc** khi `organization == AiCycleOrg.vbi`. |

```dart
final config = AICycleConfig(
  generalConfig: GeneralConfig(...),
  modelConfig: ModelConfig(),
  carInformation: CarInformation(...),
  displayConfig: const DisplayConfig(showBackButton: true),
  validateConfig: const ValidateConfig(),
  vbiConfig: null, // hoặc VBIConfig(...) nếu organization là vbi
);
```

### `GeneralConfig` (bắt buộc)

| Trường | Kiểu | Bắt buộc | Mặc định | Mô tả |
|---|---|---|---|---|
| `apiToken` | `String` | ✅ | — | Token API của AICycle (liên hệ AICycle để được cấp). |
| `documentId` | `String` | ✅ | — | ID hồ sơ (`so_id_hs`). |
| `organization` | `AiCycleOrg` | ✅ | — | Tổ chức dùng SDK: `aicycle`, `vbi`, `others`. |
| `environment` | `AiCycleEnvironment` | ❌ | `develop` | Môi trường: `develop`, `stage`, `production`. |
| `documentName` | `String?` | ❌ | `null` | Tên hồ sơ. |
| `loggingEnabled` | `bool` | ❌ | `false` | Bật/tắt log của SDK. |
| `savePhotoAfterShot` | `bool` | ❌ | `true` | Có lưu ảnh đã chụp vào gallery của máy không. |

```dart
GeneralConfig(
  apiToken: '<API_TOKEN>',
  documentId: '<DOCUMENT_ID>',
  organization: AiCycleOrg.aicycle,
  environment: AiCycleEnvironment.production,
  documentName: 'Hồ sơ kiểm định xe',
  loggingEnabled: false,
  savePhotoAfterShot: true,
);
```

### `CarInformation` (bắt buộc)

Tất cả các trường đều **tùy chọn** (có giá trị mặc định là chuỗi rỗng / `null`), nhưng nên điền đầy đủ để hồ sơ chính xác.

| Trường | Kiểu | Mặc định | Mô tả |
|---|---|---|---|
| `companyName` | `String` | `''` | Hãng xe, ví dụ `"toyota"`. |
| `modelName` | `String` | `''` | Dòng/hiệu xe, ví dụ `"vios"`. |
| `manufacturingYear` | `int?` | `null` | Năm sản xuất, ví dụ `2022`. |
| `vehicleVersionName` | `String` | `''` | Phiên bản xe, ví dụ `"1.5C"`. |
| `licensePlate` | `String` | `''` | Biển số xe, ví dụ `"30A12345"`. |
| `vehicleType` | `String?` | `null` | Loại xe, ví dụ `"sedan"`, `"pickup"`. |
| `color` | `String?` | `null` | Màu xe dạng hex `#RRGGBB`, ví dụ `"#A2A8A1"`. |
| `garageId` | `String` | `''` | ID garage. |
| `vehicleBrandId` | `String` | `''` | ID brand. |

```dart
CarInformation(
  companyName: 'toyota',
  modelName: 'vios',
  manufacturingYear: 2022,
  vehicleVersionName: '1.5C',
  licensePlate: '30A12345',
  vehicleType: 'sedan',
  color: '#A2A8A1',
  garageId: '',
  vehicleBrandId: '',
);
```

### `ModelConfig` (bắt buộc)

Ngưỡng cho từng model AI. Tất cả giá trị phải nằm trong khoảng `0.0`–`1.0` (vi phạm sẽ ném `assert`).

| Trường | Kiểu | Mặc định | Mô tả |
|---|---|---|---|
| `carPartConfThreshold` | `double` | `0.25` | Confidence threshold model nhận diện bộ phận xe. |
| `carPartIouThreshold` | `double` | `0.45` | IOU threshold model nhận diện bộ phận xe. |
| `carCornerConfThreshold` | `double` | `0.25` | Confidence threshold model phân loại góc xe. |
| `carDamageConfThreshold` | `double` | `0.25` | Confidence threshold model phát hiện thiệt hại. |
| `carDamageIouThreshold` | `double` | `0.45` | IOU threshold model phát hiện thiệt hại. |

```dart
// Dùng mặc định
ModelConfig();

// Hoặc tinh chỉnh
ModelConfig(
  carPartConfThreshold: 0.1,
  carPartIouThreshold: 0.45,
  carCornerConfThreshold: 0.1,
  carDamageConfThreshold: 0.1,
  carDamageIouThreshold: 0.45,
);
```

> **Conf threshold** càng thấp → bắt được nhiều đối tượng hơn nhưng dễ nhiễu. **IOU threshold** điều chỉnh việc gộp các bounding box trùng nhau.

### `DisplayConfig` (tùy chọn)

| Trường | Kiểu | Mặc định | Mô tả |
|---|---|---|---|
| `loadingWidget` | `Widget?` | `null` | Widget loading tùy chỉnh. |
| `showBackButton` | `bool` | `false` | Hiển thị nút back trên màn quản lý model. |

```dart
const DisplayConfig(
  showBackButton: true,
);
```

### `ValidateConfig` (tùy chọn)

| Trường | Kiểu | Mặc định | Mô tả |
|---|---|---|---|
| `require4AnglePanoramicPhotos` | `bool` | `false` | Bắt buộc chụp ảnh toàn cảnh đủ cả 4 góc xe. |

```dart
const ValidateConfig(
  require4AnglePanoramicPhotos: true,
);
```

### `VBIConfig` (bắt buộc khi organization = vbi)

Chỉ dùng khi `generalConfig.organization == AiCycleOrg.vbi`. Tất cả các trường đều **bắt buộc**.

| Trường | Kiểu | Mô tả |
|---|---|---|
| `authorityId` | `String` | ID đơn vị/authority. |
| `signatureKey` | `String` | Khóa chữ ký. |
| `externalSessionId` | `String` | ID phiên bên ngoài. |
| `jobId` | `String` | ID công việc. |
| `maHangMuc` | `String` | Mã hạng mục. |
| `tenHangMuc` | `String` | Tên hạng mục. |
| `departmentId` | `String` | ID phòng ban. |
| `userId` | `String` | ID người dùng. |
| `maTVV` | `String` | Mã TVV. |
| `source` | `String` | Nguồn. |

```dart
final config = AICycleConfig(
  generalConfig: GeneralConfig(
    apiToken: '<API_TOKEN>',
    documentId: '<DOCUMENT_ID>',
    organization: AiCycleOrg.vbi, // ⚠️ bắt buộc vbiConfig
  ),
  modelConfig: ModelConfig(),
  carInformation: CarInformation(licensePlate: '30A12345'),
  vbiConfig: VBIConfig(
    authorityId: '...',
    signatureKey: '...',
    externalSessionId: '...',
    jobId: '...',
    maHangMuc: '...',
    tenHangMuc: 'Ảnh toàn cảnh',
    departmentId: '000',
    userId: '...',
    maTVV: '...',
    source: '...',
  ),
);
```

> ⚠️ Nếu `organization == AiCycleOrg.vbi` mà `vbiConfig == null`, constructor `AICycleConfig` sẽ ném `assert`.

---

## Callback `onComplete` và `onError`

Cả `AICycleOnDevice` và `AICycleOnDeviceCamera` đều hỗ trợ:

- **`onComplete`** — gọi khi luồng hoàn tất (sau khi người dùng bấm "Xem kết quả" và upload ảnh xong). Thường dùng để `Navigator.pop` đóng SDK và thông báo thành công.
- **`onError`** — gọi khi xảy ra lỗi (tạo hồ sơ thất bại, tải model lỗi, xác thực token lỗi…). Tham số là chuỗi mô tả lỗi.

```dart
AICycleOnDeviceCamera(
  aiCycleConfig: config,
  onComplete: () {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hoàn tất')),
    );
  },
  onError: (error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Lỗi SDK: $error')),
    );
  },
);
```

---

## Dọn cache ảnh sau khi upload

SDK lưu ảnh đã chụp xuống đĩa theo `documentId` (để chịu được app bị kill giữa chừng). Sau khi upload thành công, có thể dọn cache phiên đó:

```dart
import 'package:aicycle_on_device/aicycle_on_device.dart';

await PhotoSessionCache.instance.clearSession(documentId);
```

`PhotoSessionCache` là singleton (`PhotoSessionCache.instance`); `clearSession(sessionId)` xóa toàn bộ ảnh cache của hồ sơ tương ứng với `sessionId` (chính là `documentId`).
