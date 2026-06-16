import 'dart:typed_data';

abstract class ResultRepository {
  /// Uploads a single photo for [angleId].
  /// [photoIndex] is the 0-based position within that angle's photo list.
  Future<void> uploadAnglePhoto({
    required int angleId,
    required Uint8List photoBytes,
    required int photoIndex,
  });

  /// Fetches the inspection result after all photos are uploaded.
  Future<dynamic> fetchResult();
}
