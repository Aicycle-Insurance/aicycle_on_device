import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../domain/entity/inspection_result.dart';
import '../../domain/repository/result_repository.dart';
import '../datasource/result_remote_datasource.dart';

class ResultRepositoryImpl implements ResultRepository {
  ResultRepositoryImpl(this._dataSource);

  final ResultRemoteDataSource _dataSource;

  final Map<int, ResultImage> _imageCache = {};

  @override
  Future<Map<String, dynamic>?> uploadAnglePhoto({
    required int angleId,
    required Uint8List photoBytes,
    required int photoIndex,
  }) async {
    final data = await _dataSource.uploadAnglePhoto(
      angleId: angleId,
      photoBytes: photoBytes,
      photoIndex: photoIndex,
    );
    if (data != null) _cacheFromUpload(data);
    return data;
  }


  @override
  Future<List<VehiclePart>> fetchResult() async {
    if (_imageCache.isEmpty) {
      debugPrint('fetchResult: upload cache empty, returning empty result');
      return const [];
    }
    debugPrint('fetchResult: building from ${_imageCache.length} cached uploads');
    final sorted = _imageCache.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted
        .map((e) => VehiclePart(images: [e.value]))
        .toList();
  }

  // /// Fallback gọi endpoint khi cache rỗng (chưa dùng).
  // Future<List<VehiclePart>> _fetchResultFromEndpoint() async {
  //   final models = await _dataSource.fetchResult();
  //   return models.map((p) => p.toEntity(const {})).toList();
  // }

  /// Trích toàn bộ data cần thiết từ một upload response và lưu vào [_imageCache].
  void _cacheFromUpload(Map<String, dynamic> data) {
    final imageId = data['imageId'] as int?;
    if (imageId == null) return;

    final result = data['result'];
    if (result is! Map<String, dynamic>) return;

    final extraInfor = result['extraInfor'];
    final imgSize = result['imgSize'];

    _imageCache[imageId] = ResultImage(
      imageId: imageId,
      imageUrl: result['imgUrl'] as String?,
      // "45-phai-truoc-UoYzs6" → contains 'phai-truoc' → angle 0
      directionEngineSlug: extraInfor is Map
          ? extraInfor['imageDirection'] as String?
          : null,
      resolution: imgSize is List
          ? imgSize.whereType<num>().map((e) => e.toInt()).toList()
          : null,
      damageImageInfo: _buildDamageMasks(result),
      partsMasks: _buildPartMasks(result),
    );
  }

  /// Masks bộ phận (`isPart = true`) + damage (`isPart = false`).
  List<PartMask> _buildPartMasks(Map<String, dynamic> result) {
    final masks = <PartMask>[];

    final carParts = result['carParts'];
    if (carParts is List) {
      for (final p in carParts.whereType<Map<String, dynamic>>()) {
        masks.add(PartMask(
          maskUrl: p['maskUrl'] as String?,
          masksPath: p['maskPath'] as String?,
          boxes: _parseBoxes(p['box']),
          vehiclePartName: p['name'] as String?,
          vehicleColor: p['maskColor'] as String?,
          scores: p['score'] as num?,
          isPart: true,
        ));
      }
    }

    final damages = result['damages'];
    if (damages is List) {
      for (final d in damages.whereType<Map<String, dynamic>>()) {
        masks.add(PartMask(
          maskUrl: d['maskUrl'] as String?,
          masksPath: d['maskPath'] as String?,
          boxes: _parseBoxes(d['box']),
          vehiclePartName: d['name'] as String?,
          vehicleColor: d['damageColor'] as String?,
          scores: d['score'] as num?,
          isPart: false,
          damageTypeSlug: d['damageKey'] as String?,
        ));
      }
    }

    return masks;
  }

  /// Damage overlay info từ `result.damages[]` — dùng cho [ResultImage.damageImageInfo].
  List<DamageMask> _buildDamageMasks(Map<String, dynamic> result) {
    final damages = result['damages'];
    if (damages is! List) return const [];
    return damages
        .whereType<Map<String, dynamic>>()
        .map((d) => DamageMask(
              maskUrl: d['maskUrl'] as String?,
              damageTypeSlug: d['damageKey'] as String?,
              damageTypeName: d['name'] as String?,
              damageTypeColor: d['damageColor'] as String?,
              damagePercentage: (d['score'] as num?)?.toDouble(),
            ))
        .toList();
  }

  List<double>? _parseBoxes(dynamic raw) {
    if (raw is! List) return null;
    return raw.whereType<num>().map((e) => e.toDouble()).toList();
  }
}
