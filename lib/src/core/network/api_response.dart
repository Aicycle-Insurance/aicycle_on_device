/// A generic wrapper for API responses.
class ApiResponse<T> {
  final int? statusCode;
  final T data;
  final String? message;

  const ApiResponse({this.statusCode, required this.data, this.message});
}
