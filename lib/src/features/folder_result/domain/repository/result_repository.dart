import '../entity/inspection_result.dart';

/// Photos are uploaded by the native background queue
/// (`core/upload/photo_upload_queue.dart`), not through this repository.
abstract class ResultRepository {
  /// Fetches the inspection result after all photos are uploaded.
  Future<List<VehiclePart>> fetchResult();
}
