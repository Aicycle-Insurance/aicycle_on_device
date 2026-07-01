import 'package:flutter/material.dart';

/// Parse chuỗi hex (`#RRGGBB` hoặc `RRGGBB`) sang [Color].
///
/// Trả về [Colors.transparent] nếu [hex] null/rỗng/không hợp lệ — an toàn để
/// dùng trực tiếp cho màu overlay mask mà không cần try/catch ở nơi gọi.
Color hexToColor(String? hex) {
  if (hex == null || hex.isEmpty) return Colors.transparent;

  final buffer = StringBuffer();
  if (hex.length == 6 || hex.length == 7) buffer.write('ff');
  buffer.write(hex.replaceFirst('#', ''));

  final value = int.tryParse(buffer.toString(), radix: 16);
  return value == null ? Colors.transparent : Color(value);
}
