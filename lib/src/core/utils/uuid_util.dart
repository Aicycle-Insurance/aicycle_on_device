import 'dart:math';

/// Utility to generate RFC4122 version 4 UUIDs without external dependencies.
class UuidUtil {
  UuidUtil._();

  static final Random _random = Random.secure();

  /// Generates a random v4 UUID string (e.g. "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d").
  static String v4() {
    final values = List<int>.generate(16, (_) => _random.nextInt(256));

    // Set version to 4 (0100 in bits 4-7 of octet 6)
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant to RFC4122 (10xx in bits 6-7 of octet 8)
    values[8] = (values[8] & 0x3f) | 0x80;

    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
    return '${hex[0]}${hex[1]}${hex[2]}${hex[3]}-'
        '${hex[4]}${hex[5]}-'
        '${hex[6]}${hex[7]}-'
        '${hex[8]}${hex[9]}-'
        '${hex[10]}${hex[11]}${hex[12]}${hex[13]}${hex[14]}${hex[15]}';
  }
}
