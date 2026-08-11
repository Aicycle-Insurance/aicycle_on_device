import 'package:flutter/foundation.dart';

import '../../data/model/ai_model.dart';
import '../../data/model/downloaded_model_info.dart';
import '../../data/model/model_manifest.dart';
import '../../domain/entity/ai_model_type.dart';
import '../../domain/repository/ai_model_repository.dart';

/// Trạng thái danh sách model của một loại.
class ModelTypeState {
  final bool isLoading;
  final String? error;
  final List<AiModel> models;

  const ModelTypeState({
    this.isLoading = false,
    this.error,
    this.models = const [],
  });
}

/// Quản lý state màn hình quản lý model bằng ChangeNotifier.
class ModelManagerController extends ChangeNotifier {
  ModelManagerController(this._repository);

  final AiModelRepository _repository;

  final Map<AiModelType, ModelTypeState> _typeStates = {
    for (final type in AiModelType.values)
      type: const ModelTypeState(isLoading: true),
  };

  /// Tiến trình tải theo model id (0.0 → 1.0).
  final Map<int, double> _downloadProgress = {};

  /// Model đã tải về, theo model id.
  final Map<int, DownloadedModelInfo> _downloadedById = {};

  /// Kích thước file (bytes) theo model id, lấy từ Content-Length.
  final Map<int, int> _modelSizes = {};

  /// Model id đang chờ kết quả lấy kích thước (tránh gọi trùng).
  final Set<int> _sizeFetching = {};

  /// Model id đang được chọn cho từng loại.
  final Map<AiModelType, int?> _selectedIds = {
    for (final type in AiModelType.values) type: null,
  };

  bool _isDeletingAll = false;

  /// Báo lỗi thao tác (tải/xoá) cho UI hiển thị snackbar.
  void Function(String message)? onActionError;

  // ---------------- Getters ----------------

  ModelTypeState stateOf(AiModelType type) => _typeStates[type]!;

  bool get isDeletingAll => _isDeletingAll;

  bool isDownloaded(AiModel model) => _downloadedById.containsKey(model.id);

  bool isSelected(AiModel model) => _selectedIds[model.type] == model.id;

  /// null nếu model không trong quá trình tải.
  double? downloadProgressOf(AiModel model) => _downloadProgress[model.id];

  /// Kích thước file (bytes): ưu tiên size file thật khi đã tải,
  /// fallback về Content-Length từ server; null nếu chưa xác định được.
  int? sizeOf(AiModel model) =>
      _downloadedById[model.id]?.sizeInBytes ?? _modelSizes[model.id];

  bool get hasDownloadedModels => _downloadedById.isNotEmpty;

  /// Loại [type] đã sẵn sàng khi có model được chọn và đã tải xong.
  bool isTypeReady(AiModelType type) =>
      _selectedIds[type] != null &&
      _downloadedById.containsKey(_selectedIds[type]);

  /// Chỉ được chuyển sang màn camera khi các loại quản lý qua network đều sẵn sàng.
  bool get canContinue => AiModelType.values.every(isTypeReady);

  /// Model đã chọn cho từng loại — dùng truyền sang màn camera.
  Map<AiModelType, DownloadedModelInfo> get selectedModels => {
        for (final type in AiModelType.values)
          if (isTypeReady(type)) type: _downloadedById[_selectedIds[type]]!,
      };

  /// Version của model đang chọn cho [type], null nếu chưa chọn.
  String? selectedVersionOf(AiModelType type) {
    final id = _selectedIds[type];
    return id == null ? null : _downloadedById[id]?.version;
  }

  // ---------------- Actions ----------------

  /// Đọc trạng thái local rồi tải danh sách model của cả 3 loại.
  Future<void> init() async {
    final localState = await _repository.getLocalState();
    localState.fold(
      (failure) => onActionError?.call(failure.message),
      _applyManifest,
    );
    await Future.wait(AiModelType.values.map(fetchModels));
  }

  Future<void> fetchModels(AiModelType type) async {
    _typeStates[type] = const ModelTypeState(isLoading: true);
    notifyListeners();

    final result = await _repository.getModels(type);
    _typeStates[type] = result.fold(
      (failure) => ModelTypeState(error: failure.message),
      (models) => ModelTypeState(models: models),
    );
    notifyListeners();

    result.fold((_) {}, _fetchModelSizes);
  }

  /// Lấy kích thước các model chưa biết size, chạy nền không chặn UI.
  void _fetchModelSizes(List<AiModel> models) {
    for (final model in models) {
      if (sizeOf(model) != null || _sizeFetching.contains(model.id)) continue;
      _sizeFetching.add(model.id);
      _repository.getModelFileSize(model).then((size) {
        _sizeFetching.remove(model.id);
        if (size != null) {
          _modelSizes[model.id] = size;
          notifyListeners();
        }
      });
    }
  }

  Future<void> downloadModel(AiModel model) async {
    if (isDownloaded(model) || _downloadProgress.containsKey(model.id)) return;

    _downloadProgress[model.id] = 0;
    notifyListeners();

    final result = await _repository.downloadModel(
      model,
      onProgress: (progress) {
        // Chỉ rebuild khi tiến trình thay đổi đáng kể để tránh giật UI
        final current = _downloadProgress[model.id] ?? 0;
        if (progress - current >= 0.01) {
          _downloadProgress[model.id] = progress;
          notifyListeners();
        }
      },
    );

    _downloadProgress.remove(model.id);
    result.fold(
      (failure) => onActionError?.call(failure.message),
      (info) {
        _downloadedById[info.id] = info;
        // Tự chọn nếu loại này chưa có model nào được chọn,
        // hoặc model đang chọn chưa được tải về (id cũ không còn tồn tại)
        final currentSelected = _selectedIds[model.type];
        if (currentSelected == null ||
            !_downloadedById.containsKey(currentSelected)) {
          _selectedIds[model.type] = model.id;
          _repository.selectModel(model);
        }
      },
    );
    notifyListeners();
  }

  Future<void> selectModel(AiModel model) async {
    if (!isDownloaded(model) || isSelected(model)) return;

    _selectedIds[model.type] = model.id;
    notifyListeners();

    final result = await _repository.selectModel(model);
    result.fold(
      (failure) => onActionError?.call(failure.message),
      (_) {},
    );
  }

  Future<void> deleteModel(AiModel model) async {
    final result = await _repository.deleteModel(model.id);
    result.fold(
      (failure) => onActionError?.call(failure.message),
      _applyManifest,
    );
    notifyListeners();
  }

  Future<void> deleteAllModels() async {
    _isDeletingAll = true;
    notifyListeners();

    final result = await _repository.deleteAllModels();
    result.fold(
      (failure) => onActionError?.call(failure.message),
      (_) => _applyManifest(ModelManifest.empty()),
    );

    _isDeletingAll = false;
    notifyListeners();
  }

  void _applyManifest(ModelManifest manifest) {
    _downloadedById
      ..clear()
      ..addEntries(manifest.downloaded.map((e) => MapEntry(e.id, e)));
    for (final type in AiModelType.values) {
      _selectedIds[type] = manifest.selected[type];
    }
  }
}
