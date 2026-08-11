class AICycleFolderModel {
  final int? claimId;
  final bool? resultsAvailable;

  AICycleFolderModel({this.claimId, this.resultsAvailable});

  factory AICycleFolderModel.fromJson(Map<String, dynamic> json) {
    return AICycleFolderModel(
      claimId: int.tryParse(json['claimId']?.toString() ?? ''),
      resultsAvailable: json['resultsAvailable']?.toString().contains('true'),
    );
  }

  /// Parses a response that might be a List or a Map, or wrapped in a 'data' field.
  factory AICycleFolderModel.fromDynamic(dynamic data) {
    if (data is Map<String, dynamic> && data.containsKey('data')) {
      final innerData = data['data'];
      if (innerData is List && innerData.isNotEmpty) {
        return AICycleFolderModel.fromJson(
            innerData[0] as Map<String, dynamic>);
      }
      return AICycleFolderModel.fromJson(innerData as Map<String, dynamic>);
    }

    if (data is List && data.isNotEmpty) {
      return AICycleFolderModel.fromJson(data[0] as Map<String, dynamic>);
    } else if (data is Map<String, dynamic>) {
      return AICycleFolderModel.fromJson(data);
    }
    return AICycleFolderModel();
  }
}
