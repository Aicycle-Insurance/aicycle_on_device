import 'aicycle_config.dart';

/// Holder nội bộ giữ config đang hoạt động của SDK, dùng chung trong package.
///
/// Các feature (model manager, camera, ...) đọc config qua class này
/// để hoạt động độc lập, không phụ thuộc vào widget `AICycleOnDevice`.
/// File này không được export ra public API.
class AICycleConfigHolder {
  AICycleConfigHolder._();

  static AICycleConfig? _config;

  static bool get isInitialized => _config != null;

  /// Config hiện tại. Throws nếu SDK chưa được khởi tạo.
  static AICycleConfig get config {
    final config = _config;
    if (config == null) {
      throw StateError(
        'AICycle SDK has not been initialized. '
        'Ensure AICycleOnDevice widget is in the tree, '
        'or call AICycleConfigHolder.init() first.',
      );
    }
    return config;
  }

  static void init(AICycleConfig config) {
    _config = config;
  }

  static void reset() {
    _config = null;
  }
}
