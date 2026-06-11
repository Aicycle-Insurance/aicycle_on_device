/// Base exceptions thrown by Data Sources.
/// All exceptions carry an optional [message] and [statusCode].
///
/// 5xx or unexpected server-side errors.
class ServerException implements Exception {
  final String? message;
  final int? statusCode;
  const ServerException([this.message, this.statusCode]);

  @override
  String toString() => 'ServerException($statusCode): $message';
}

/// No internet, connection timeout, or receive timeout.
class NetworkException implements Exception {
  final String? message;
  const NetworkException([this.message]);

  @override
  String toString() => 'NetworkException: $message';
}

/// HTTP 401 – invalid or missing API key / token.
class UnauthorizedException implements Exception {
  final String? message;
  const UnauthorizedException([this.message]);

  @override
  String toString() => 'UnauthorizedException: $message';
}

/// Failed to deserialize response body.
class ParseException implements Exception {
  final String? message;
  const ParseException([this.message]);

  @override
  String toString() => 'ParseException: $message';
}

/// Local cache errors.
class CacheException implements Exception {
  final String? message;
  const CacheException([this.message]);

  @override
  String toString() => 'CacheException: $message';
}

class EngineException implements Exception {
  final String? message;
  final int? engineCode;
  const EngineException([this.message, this.engineCode]);

  @override
  String toString() => 'EngineException($engineCode): $message';
}

/// Location / geocoding errors (permission denied, service disabled, etc.).
class LocationException implements Exception {
  final String? message;
  const LocationException([this.message]);

  @override
  String toString() => 'LocationException: $message';
}
