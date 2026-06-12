import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../ai_model_manager/data/model/ai_model.dart';
import '../../../ai_model_manager/domain/entity/ai_model_type.dart';
import '../../../ai_model_manager/domain/repository/ai_model_repository.dart';

/// Đảm bảo đủ model trước khi mở camera.
///
/// Với loại nào chưa có sẵn đường dẫn model, controller luôn lấy
/// version mới nhất từ server: nếu bản mới nhất đã được tải về máy
/// thì dùng luôn, chưa có thì tải về rồi mới báo sẵn sàng.
class CameraModelController extends ChangeNotifier {
  CameraModelController(this._repository);

  final AiModelRepository _repository;

  Map<AiModelType, String?> _initialPaths = {};
  final Map<AiModelType, String> _modelPaths = {};
  bool _isPreparing = true;
  String? _error;
  AiModelType? _downloadingType;
  double _downloadProgress = 0;

  /// Báo lỗi chuẩn bị model cho bên ngoài (vd: callback onError của SDK).
  void Function(String message)? onPrepareError;

  bool get isPreparing => _isPreparing;

  String? get error => _error;

  /// Chỉ sẵn sàng mở camera khi có đủ model cho cả 3 loại.
  bool get isReady =>
      !_isPreparing &&
      _error == null &&
      AiModelType.values.every(_modelPaths.containsKey);

  /// Loại model đang được tải, null nếu không trong quá trình tải.
  AiModelType? get downloadingType => _downloadingType;

  /// Tiến trình tải model hiện tại (0.0 → 1.0).
  double get downloadProgress => _downloadProgress;

  /// Đường dẫn file model đã sẵn sàng cho [type].
  String? modelPathOf(AiModelType type) => _modelPaths[type];

  /// Chuẩn bị model: giữ nguyên các path đã có, loại nào null
  /// thì đảm bảo version mới nhất có trên máy.
  Future<void> prepare(Map<AiModelType, String?> paths) async {
    _initialPaths = paths;
    _isPreparing = true;
    _error = null;
    notifyListeners();

    try {
      for (final type in AiModelType.values) {
        final provided = paths[type];
        // Path truyền vào chỉ dùng được khi file còn tồn tại trên máy,
        // ngược lại tự tải version mới nhất
        if (provided != null && File(provided).existsSync()) {
          _modelPaths[type] = provided;
          continue;
        }
        _modelPaths[type] = await _ensureLatestModel(type);
      }
    } on _PrepareException catch (e) {
      _error = e.message;
      onPrepareError?.call(e.message);
    } finally {
      _isPreparing = false;
      _downloadingType = null;
      notifyListeners();
    }
  }

  /// Thử lại với đúng các path ban đầu.
  Future<void> retry() => prepare(_initialPaths);

  Future<String> _ensureLatestModel(AiModelType type) async {
    final models = (await _repository.getModels(type)).fold(
      (failure) => throw _PrepareException(failure.message),
      (models) => models,
    );
    if (models.isEmpty) {
      throw _PrepareException('No model available for ${type.apiValue}');
    }
    final latest = models.reduce(_newer);

    // Bản mới nhất đã có trên máy → dùng luôn, không tải lại
    final manifest = (await _repository.getLocalState()).fold(
      (failure) => throw _PrepareException(failure.message),
      (manifest) => manifest,
    );
    final existing =
        manifest.downloaded.where((e) => e.id == latest.id).firstOrNull;
    if (existing != null) {
      await _repository.selectModel(latest);
      return existing.filePath;
    }

    _downloadingType = type;
    _downloadProgress = 0;
    notifyListeners();

    final info = (await _repository.downloadModel(
      latest,
      onProgress: (progress) {
        // Chỉ rebuild khi tiến trình thay đổi đáng kể để tránh giật UI
        if (progress - _downloadProgress >= 0.01) {
          _downloadProgress = progress;
          notifyListeners();
        }
      },
    ))
        .fold(
      (failure) => throw _PrepareException(failure.message),
      (info) => info,
    );

    _downloadingType = null;

    // Tải bản mới thành công → xoá các version cũ cùng loại (best-effort)
    final oldVersions =
        manifest.downloaded.where((e) => e.type == type && e.id != latest.id);
    for (final old in oldVersions) {
      await _repository.deleteModel(old.id);
    }

    await _repository.selectModel(latest);
    return info.filePath;
  }

  /// Model mới hơn: so sánh version theo từng phần số,
  /// bằng nhau thì lấy bản có ngày tạo mới hơn.
  AiModel _newer(AiModel a, AiModel b) {
    final cmp = _compareVersions(a.version, b.version);
    if (cmp != 0) return cmp > 0 ? a : b;
    return a.createdDate.isAfter(b.createdDate) ? a : b;
  }

  int _compareVersions(String a, String b) {
    final partsA = a.split('.');
    final partsB = b.split('.');
    final length =
        partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < length; i++) {
      final numA = i < partsA.length ? int.tryParse(partsA[i]) ?? 0 : 0;
      final numB = i < partsB.length ? int.tryParse(partsB[i]) ?? 0 : 0;
      if (numA != numB) return numA.compareTo(numB);
    }
    return 0;
  }
}

class _PrepareException implements Exception {
  const _PrepareException(this.message);
  final String message;
}
