/// Mapping từ 14 class của model classify → 4 góc của CarProgressRing.
///
/// Ring index convention (chiều kim đồng hồ từ góc phải-trước):
///   0 = phải - trước  (right front)
///   1 = phải - sau    (right rear)
///   2 = trái - sau    (left rear)
///   3 = trái - trước  (left front)
enum CarAngle {
  // ── Góc 0: phải trước ───────────────────────────────────
  phaiTruocToanCanh(label: 'phai_truoc_toan_canh', segmentIndex: 0),
  angle45PhaiTruoc(label: '45_phai_truoc', segmentIndex: 0),

  // ── Góc 1: phải sau ─────────────────────────────────────
  phaiSauToanCanh(label: 'phai_sau_toan_canh', segmentIndex: 1),
  angle45PhaiSau(label: '45_phai_sau', segmentIndex: 1),

  // ── Góc 2: trái sau ─────────────────────────────────────
  traiSauToanCanh(label: 'trai_sau_toan_canh', segmentIndex: 2),
  angle45TraiSau(label: '45_trai_sau', segmentIndex: 2),

  // ── Góc 3: trái trước ───────────────────────────────────
  traiTruocToanCanh(label: 'trai_truoc_toan_canh', segmentIndex: 3),
  angle45TraiTruoc(label: '45_trai_truoc', segmentIndex: 3);

  const CarAngle({required this.label, required this.segmentIndex});

  /// Tên class từ model.
  final String label;

  /// Index cung trên CarProgressRing (0–3).
  final int segmentIndex;

  static final _byLabel = {
    for (final v in values) v.label: v,
  };

  /// Trả về [CarAngle] từ tên class, null nếu không nhận ra.
  static CarAngle? fromLabel(String label) => _byLabel[label];

  /// Trả về segment index (0–3) từ tên class top1.
  /// Trả về null nếu class không thuộc bộ phân loại góc xe.
  static int? segmentOf(String label) => fromLabel(label)?.segmentIndex;

  /// Nhãn hiển thị cho từng segment index (0–3).
  static const segmentLabels = [
    'Phải trước',
    'Phải sau',
    'Trái sau',
    'Trái trước',
  ];

  /// về segment index (0–3). Trả về null nếu không nhận ra.
  static int? angleFromEngineSlug(String? slug) {
    if (slug == null) return null;
    if (slug.contains('phai-truoc')) return 0;
    if (slug.contains('phai-sau')) return 1;
    if (slug.contains('trai-sau')) return 2;
    if (slug.contains('trai-truoc')) return 3;
    return null;
  }
}
