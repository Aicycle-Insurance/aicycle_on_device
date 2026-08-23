/// Bậc nhiệt của thiết bị do native báo lên (`type == "thermal"`).
///
/// Native tự hạ nhịp chạy các model theo bậc này (xem `ThermalGovernor` bên
/// Kotlin/Swift) — Dart chỉ nhận để biết trạng thái, không điều khiển ngược.
/// Thứ tự phải khớp với `ThermalTier` ở cả hai nền tảng.
enum ThermalLevel {
  /// Máy mát — model chạy full nhịp.
  normal,

  /// Bắt đầu ấm — nhịp hạ nhẹ, user chưa cảm nhận được khác biệt.
  warm,

  /// Nóng rõ — nhịp hạ mạnh, hệ điều hành có thể đã throttle SoC.
  hot,

  /// Rất nóng — model chạy ở nhịp tối thiểu vừa đủ giữ luồng nghiệp vụ.
  critical;

  /// Native đang chủ động giảm tốc để hạ nhiệt.
  bool get isThrottled => this != ThermalLevel.normal;

  static ThermalLevel fromLevel(int? level) {
    if (level == null || level < 0 || level >= ThermalLevel.values.length) {
      return ThermalLevel.normal;
    }
    return ThermalLevel.values[level];
  }
}

/// Sự kiện `type == "thermal"` từ native.
class ThermalStatus {
  const ThermalStatus({required this.level, required this.throttled});

  final ThermalLevel level;

  /// Cờ do native gửi kèm. Luôn bằng `level.isThrottled`; giữ lại để không phụ
  /// thuộc vào việc hai bên có cùng số bậc hay không.
  final bool throttled;

  static const normal =
      ThermalStatus(level: ThermalLevel.normal, throttled: false);

  factory ThermalStatus.fromJson(Map<String, dynamic> json) {
    final level = ThermalLevel.fromLevel((json['level'] as num?)?.toInt());
    return ThermalStatus(
      level: level,
      throttled: (json['throttled'] as bool?) ?? level.isThrottled,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': 'thermal',
        'level': level.index,
        'state': level.name,
        'throttled': throttled,
      };

  @override
  String toString() => 'ThermalStatus(${level.name}, throttled: $throttled)';
}
