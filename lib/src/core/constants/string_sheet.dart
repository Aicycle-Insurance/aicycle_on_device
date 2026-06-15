/// Quản lý tập trung toàn bộ string hiển thị trên UI của SDK.
class StringSheet {
  StringSheet._();

  // ----- Model types -----
  static const carCornerName = 'Nhận diện góc xe';
  static const carDamageName = 'Nhận diện thiệt hại';
  static const carPartName = 'Nhận diện bộ phận xe';
  static const carCornerShortName = 'Góc xe';
  static const carDamageShortName = 'Thiệt hại';
  static const carPartShortName = 'Bộ phận xe';

  // ----- Model manager screen -----
  static const modelManagerTitle = 'Quản lý mô hình AI';
  static const deleteAllTooltip = 'Xoá tất cả mô hình';
  static const deleteAllDialogTitle = 'Xoá tất cả mô hình?';
  static const deleteAllDialogContent =
      'Toàn bộ mô hình đã tải sẽ bị xoá khỏi thiết bị. '
      'Bạn sẽ cần tải lại để tiếp tục sử dụng.';
  static const cancel = 'Huỷ';
  static const deleteAll = 'Xoá tất cả';
  static const continueButton = 'Tiếp tục';
  static const requirementHint =
      'Tải và chọn ít nhất 1 mô hình cho mỗi loại để tiếp tục';

  static String missingTypes(String types) => 'Còn thiếu: $types';

  // ----- Folder / session init -----
  static const creatingFolder = 'Đang khởi tạo hồ sơ...';
  static const folderError = 'Không thể khởi tạo hồ sơ';

  // ----- Camera screen -----
  static const preparingModels = 'Đang chuẩn bị mô hình...';
  static const startCapture = 'Bắt đầu chụp ảnh xe';
  static const captureGuide =
      'Vui lòng chụp 01 ảnh toàn cảnh xe đảm bảo đủ ánh sáng và thấy rõ biển số như mẫu dưới đây';
  static const frontLeftGuide =
      'Vui lòng di chuyển về góc chéo đầu xe bên ghế lái';
  static const frontRightGuide =
      'Vui lòng di chuyển về góc chéo đầu xe bên ghế phụ';
  static const backLeftGuide =
      'Vui lòng di chuyển về góc chéo cuối xe bên ghế lái';
  static const backRightGuide =
      'Vui lòng di chuyển về góc chéo cuối xe bên ghế phụ';

  static String downloadingModel(String name) => 'Đang tải mô hình $name';
  static const moveBackGuide =
      'Lùi camera ra xa để xe nằm trọn vẹn trong khung hình';
  static const holdStillGuide =
      'Hãy giữ yên điện thoại. Ảnh sẽ được chụp tự động';
  static const captureSuccess = 'Chụp thành công';
  static const inspectDamageGuide =
      'Đưa camera lại gần vị trí tổn thất.\nNếu không có tổn thất, hãy chuyển sang vị trí khác';
  static const changeAngle = 'Chuyển góc';
  static const damageDetectedGuide =
      'Các tổn thất đã được ghi nhận. Vui lòng kiểm tra và xác nhận';
  static const missingDamage = 'Thiếu tổn thất';
  static const confirm = 'Xác nhận';
  static const continueOrChangeGuide =
      'Tiếp tục di chuyển camera đến vùng có tổn thất khác hoặc chuyển góc';

  // ----- Car progress ring dialog -----
  static const cornerNeedsPhoto = 'Góc cần bổ sung ảnh';
  static const cornerCaptured = 'Đã chụp thành công';

  // ----- Camera exit dialog -----
  static const exitCameraTitle = 'Thoát chụp ảnh?';
  static const exitCameraContent =
      'Các ảnh xe đã chụp sẽ không được lưu nếu bạn thoát ngay bây giờ.';
  static const exitConfirm = 'Thoát';
  static const carPhoto = 'Ảnh xe';

  // ----- Model list / card -----
  static const download = 'Tải về';
  static const deleteModelTooltip = 'Xoá mô hình';
  static const notSelected = 'Chưa chọn';
  static const retry = 'Thử lại';
  static const emptyModels = 'Không có mô hình nào';

  // ----- Result / upload screen -----
  static String uploadingPhotos(int uploaded, int total) =>
      'Đang tải lên ảnh $uploaded/$total';
  static const fetchingResult = 'Đang lấy kết quả...';
  static const unknownError = 'Đã xảy ra lỗi. Vui lòng thử lại';

  static const unknown = 'Không xác định';

  static String modelVersion(String version) => 'Phiên bản $version';
  static String sizeInMb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  static String releasedAt(String date) => 'Phát hành: $date';
  static String sizeLabel(String size) => 'Kích thước: $size';
  static String versionCount(int count) => '$count phiên bản';
  static String selectedVersion(String version) => 'Đã chọn v$version';
}
