import '../../domain/entity/inspection_result.dart';
import '../../domain/repository/result_repository.dart';
import '../datasource/result_remote_datasource.dart';

class ResultRepositoryImpl implements ResultRepository {
  ResultRepositoryImpl(this._dataSource);

  final ResultRemoteDataSource _dataSource;

  @override
  Future<List<VehiclePart>> fetchResult() async {
    final models = await _dataSource.fetchResult();
    return models.map((e) => e.toEntity()).toList();
  }
}
