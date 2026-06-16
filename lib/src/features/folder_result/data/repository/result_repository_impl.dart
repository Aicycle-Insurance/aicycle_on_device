import 'dart:typed_data';

import '../../domain/repository/result_repository.dart';
import '../datasource/result_remote_datasource.dart';

class ResultRepositoryImpl implements ResultRepository {
  ResultRepositoryImpl(this._dataSource);

  final ResultRemoteDataSource _dataSource;

  @override
  Future<void> uploadAnglePhoto({
    required int angleId,
    required Uint8List photoBytes,
    required int photoIndex,
  }) =>
      _dataSource.uploadAnglePhoto(
        angleId: angleId,
        photoBytes: photoBytes,
        photoIndex: photoIndex,
      );

  @override
  Future<dynamic> fetchResult() => _dataSource.fetchResult();
}
