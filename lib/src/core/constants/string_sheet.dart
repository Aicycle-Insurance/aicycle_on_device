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

  // ----- Camera screen -----
  static const preparingModels = 'Đang chuẩn bị mô hình...';

  static String downloadingModel(String name) => 'Đang tải mô hình $name';

  // ----- Model list / card -----
  static const download = 'Tải về';
  static const deleteModelTooltip = 'Xoá mô hình';
  static const notSelected = 'Chưa chọn';
  static const retry = 'Thử lại';
  static const emptyModels = 'Không có mô hình nào';

  static const unknown = 'Không xác định';

  static String modelVersion(String version) => 'Phiên bản $version';
  static String sizeInMb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  static String releasedAt(String date) => 'Phát hành: $date';
  static String sizeLabel(String size) => 'Kích thước: $size';
  static String versionCount(int count) => '$count phiên bản';
  static String selectedVersion(String version) => 'Đã chọn v$version';
}
