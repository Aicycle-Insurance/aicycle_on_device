/// Base interface for all failures surfaced to the presentation layer.
abstract class Failure {
  final String message;
  const Failure(this.message);
}

/// 5xx or unexpected API errors.
class ServerFailure extends Failure {
  final int? statusCode;
  const ServerFailure([
    super.message = 'Server error occurred',
    this.statusCode,
  ]);
}

/// No internet or timeout.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection']);
}

/// 401 – token / API key invalid.
class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure([super.message = 'Unauthorized – invalid API key']);
}

/// Response body could not be parsed.
class ParseFailure extends Failure {
  const ParseFailure([super.message = 'Failed to parse server response']);
}

/// Local cache errors.
class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error occurred']);
}

/// Location / geocoding errors.
class LocationFailure extends Failure {
  const LocationFailure([super.message = 'Failed to get location']);
}
