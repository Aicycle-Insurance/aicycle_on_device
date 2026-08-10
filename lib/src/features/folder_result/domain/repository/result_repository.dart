import 'dart:typed_data';

import '../entity/inspection_result.dart';

abstract class ResultRepository {
  /// Uploads a single photo for [angleId].
  /// [photoIndex] is the 0-based position within that angle's photo list.
  /// Returns the JSON body the server responds with for that photo (null when
  /// the response is not a JSON object).
  Future<Map<String, dynamic>?> uploadAnglePhoto({
    required int angleId,
    required Uint8List photoBytes,
    required int photoIndex,
    int? imageOrder,
  });

  /// Fetches the inspection result after all photos are uploaded.
  Future<List<VehiclePart>> fetchResult();
}
