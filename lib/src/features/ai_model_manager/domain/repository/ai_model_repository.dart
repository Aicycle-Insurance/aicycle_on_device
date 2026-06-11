import '../../../../core/error/failures.dart';
import '../../../../core/utils/result.dart';
import '../../data/model/ai_model.dart';
import '../../data/model/downloaded_model_info.dart';
import '../../data/model/model_manifest.dart';
import '../entity/ai_model_type.dart';

/// Quản lý model AI: lấy danh sách từ server, tải về,
/// xoá và chọn model sử dụng.
abstract class AiModelRepository {
  /// Lấy danh sách model từ server theo [type].
  Future<Result<List<AiModel>, Failure>> getModels(AiModelType type);

  /// Đọc trạng thái local: model đã tải + model đang chọn.
  Future<Result<ModelManifest, Failure>> getLocalState();

  /// Lấy kích thước file (bytes) của [model] trên server.
  /// Best-effort: trả về null nếu không xác định được, không throw.
  Future<int?> getModelFileSize(AiModel model);

  /// Tải [model] về máy. File được tải vào thư mục tạm trước,
  /// tải xong mới chuyển vào bộ nhớ nội bộ của app.
  Future<Result<DownloadedModelInfo, Failure>> downloadModel(
    AiModel model, {
    void Function(double progress)? onProgress,
  });

  /// Xoá một model đã tải. Trả về manifest sau khi xoá
  /// (selection được tự động cập nhật nếu model đang chọn bị xoá).
  Future<Result<ModelManifest, Failure>> deleteModel(int modelId);

  /// Xoá toàn bộ model đã tải.
  Future<Result<void, Failure>> deleteAllModels();

  /// Chọn [model] làm model sử dụng cho loại tương ứng.
  Future<Result<void, Failure>> selectModel(AiModel model);
}
