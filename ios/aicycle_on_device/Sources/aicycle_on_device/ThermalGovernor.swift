//  ThermalGovernor — theo dõi nhiệt độ máy để các view inference tự hạ nhịp chạy model.

import Foundation

/// Bậc nhiệt đã chuẩn hoá giữa iOS và Android. `rawValue` được dùng làm index
/// vào các bảng nhịp chạy model, nên thứ tự phải khớp với `ThermalTier` bên
/// Kotlin và với thứ tự cột của các bảng đó.
enum ThermalTier: Int {
  /// Máy mát — chạy full nhịp.
  case normal = 0
  /// Bắt đầu ấm — hạ nhịp nhẹ, user chưa cảm nhận được khác biệt.
  case warm = 1
  /// Nóng rõ — hạ nhịp mạnh, hệ điều hành có thể đã bắt đầu throttle SoC.
  case hot = 2
  /// Rất nóng — chạy ở nhịp tối thiểu vừa đủ để luồng nghiệp vụ không đứng.
  case critical = 3

  var label: String {
    switch self {
    case .normal: return "normal"
    case .warm: return "warm"
    case .hot: return "hot"
    case .critical: return "critical"
    }
  }

  /// iOS chỉ có 4 mức thermal state, ánh xạ 1–1 sang 4 bậc ở đây.
  init(thermalState: ProcessInfo.ThermalState) {
    switch thermalState {
    case .nominal: self = .normal
    case .fair: self = .warm
    case .serious: self = .hot
    case .critical: self = .critical
    @unknown default: self = .warm
    }
  }
}

/// Theo dõi `ProcessInfo.thermalState` và báo về khi bậc nhiệt đổi.
///
/// Khác với Android (nơi phải tự poll trên máy cũ), iOS luôn có sẵn thermal
/// state, nên đây chỉ là lớp mỏng quanh notification của hệ thống.
///
/// [onChange] được gọi trên main queue, chỉ khi bậc nhiệt thực sự đổi.
final class ThermalGovernor: @unchecked Sendable {

  /// Bậc nhiệt hiện tại. Chỉ đọc/ghi trên main queue.
  private(set) var tier: ThermalTier = .normal

  private let onChange: (ThermalTier) -> Void
  private var observer: NSObjectProtocol?

  init(onChange: @escaping (ThermalTier) -> Void) {
    self.onChange = onChange
  }

  deinit {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  /// Bắt đầu theo dõi. An toàn khi gọi nhiều lần. Phải gọi trên main queue.
  func start() {
    guard observer == nil else { return }
    apply(ThermalTier(thermalState: ProcessInfo.processInfo.thermalState))
    observer = NotificationCenter.default.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.apply(ThermalTier(thermalState: ProcessInfo.processInfo.thermalState))
    }
  }

  /// Ngừng theo dõi và gỡ observer. An toàn khi gọi nhiều lần.
  func stop() {
    guard let observer else { return }
    NotificationCenter.default.removeObserver(observer)
    self.observer = nil
  }

  private func apply(_ next: ThermalTier) {
    guard next != tier else { return }
    let previous = tier
    tier = next
    NSLog("ThermalGovernor: thermal tier %@ → %@", previous.label, next.label)
    onChange(next)
  }
}
