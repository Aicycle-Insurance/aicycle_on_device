// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import Foundation

/// One JPEG frame in the burst timeline with monotonic [stepIndex].
public struct BurstFrame {
  public let data: Data
  public let stepIndex: Int
  public let isCallEngine: Bool

  public init(data: Data, stepIndex: Int, isCallEngine: Bool) {
    self.data = data
    self.stepIndex = stepIndex
    self.isCallEngine = isCallEngine
  }
}

/// Fixed-capacity ring buffer holding the most recent [capacity] burst frames.
/// Access only from the owning serial queue (cameraQueue).
final class FrameRingBuffer {
  private let capacity: Int
  private var slots: [BurstFrame?]
  private var writeHead = 0
  private var filled = 0

  init(capacity: Int = 5) {
    self.capacity = max(1, capacity)
    self.slots = Array(repeating: nil, count: capacity)
  }

  func write(_ frame: BurstFrame) {
    slots[writeHead] = frame
    writeHead = (writeHead + 1) % capacity
    filled = min(filled + 1, capacity)
  }

  /// Returns a copy of stored frames in chronological order (oldest first).
  func snapshot() -> [BurstFrame] {
    if filled == 0 { return [] }
    let count = min(filled, capacity)
    let start = filled < capacity ? 0 : writeHead
    var result: [BurstFrame] = []
    for i in 0..<count {
      let idx = (start + i) % capacity
      if let frame = slots[idx] {
        result.append(frame)
      }
    }
    return result
  }

  var totalBytes: Int {
    slots.compactMap { $0?.data.count }.reduce(0, +)
  }
}
