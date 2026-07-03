import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/utils/image_fit_utils.dart';
import '../../domain/entity/inspection_result.dart';

const int _kAlphaThreshold = 20;

class MaskHitTester {
  final Map<String, _MaskData?> _cache = {};

  void preload(List<PartMask> masks) {
    for (final mask in masks) {
      final url = mask.maskUrl;
      if (url == null || url.isEmpty) continue;
      if (_cache.containsKey(url)) continue;

      _cache[url] = null;
      _loadMaskData(url);
    }
  }

  PartMask? hitTest({
    required Offset scenePos,
    required List<PartMask> masks,
    required double imWidth,
    required double imHeight,
  }) {
    for (final mask in masks.reversed) {
      final boxes = mask.boxes;
      if (boxes == null || boxes.length < 4) continue;

      final rect = maskDisplayRect(boxes, imWidth, imHeight);
      if (!rect.contains(scenePos)) continue;

      final url = mask.maskUrl;
      if (url == null || url.isEmpty) {
        return mask;
      }

      final data = _cache[url];
      if (data == null) {
        // Cache chưa sẵn sàng (null = chưa load hoặc đang load) → fallback bbox.
        return mask;
      }

      if (_hitsAlpha(scenePos, rect, data)) return mask;
    }
    return null;
  }

  void dispose() => _cache.clear();

  void _loadMaskData(String url) {
    final completer = Completer<_MaskData>();
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) async {
        stream.removeListener(listener);
        try {
          final byteData =
              await info.image.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (byteData != null) {
            completer.complete(
              _MaskData(
                byteData: byteData,
                width: info.image.width,
                height: info.image.height,
              ),
            );
          }
        } catch (_) {
          // Decode fail → giữ null trong cache (fallback bbox sẽ dùng).
          stream.removeListener(listener);
        }
      },
      onError: (_, __) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);

    completer.future.then((data) => _cache[url] = data).ignore();
  }

  /// Kiểm tra alpha của pixel tại [scenePos] trong mask tại [rect].
  bool _hitsAlpha(Offset scenePos, Rect rect, _MaskData data) {
    // Convert từ scene coords → tọa độ pixel trong mask image.
    final relX = (scenePos.dx - rect.left) / rect.width;
    final relY = (scenePos.dy - rect.top) / rect.height;

    final px = (relX * (data.width - 1)).round().clamp(0, data.width - 1);
    final py = (relY * (data.height - 1)).round().clamp(0, data.height - 1);

    // RGBA: mỗi pixel = 4 byte, alpha ở byte thứ 4 (offset +3).
    final idx = (py * data.width + px) * 4 + 3;
    if (idx < 0 || idx >= data.byteData.lengthInBytes) return false;

    return data.byteData.getUint8(idx) > _kAlphaThreshold;
  }
}

/// Pixel data đã decode của một mask PNG.
class _MaskData {
  const _MaskData({
    required this.byteData,
    required this.width,
    required this.height,
  });

  final ByteData byteData;
  final int width;
  final int height;
}
