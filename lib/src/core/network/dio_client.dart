import 'dart:convert';
import 'package:dio/dio.dart';
import '../../config/aicycle_config.dart';
import '../../config/aicycle_config_internal.dart';
import '../../config/config_holder.dart';
import '../error/exceptions.dart';
import '../utils/logger.dart';

class DioClient {
  late final Dio _dio;
  final LoggerService _logger;

  DioClient(this._logger) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add logging and authentication interceptors
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // 1. Automatically get baseUrl and token from config
          final skipDefaultAuth = options.extra['skipDefaultAuth'] == true;
          try {
            final config = AICycleConfigHolder.config;
            final String? customBaseUrl = options.extra['customBaseUrl'];
            options.baseUrl = customBaseUrl ?? config.baseUrl;

            // Some endpoints (e.g. VBI's own server) use their own
            // auth scheme and must not get AICycle's Authorization header.
            if (!skipDefaultAuth) {
              options.headers['Authorization'] =
                  'Bearer ${config.generalConfig.apiToken}';
              String? xApp;

              switch (config.generalConfig.organization) {
                case AiCycleOrg.aicycle:
                  xApp = 'appDemo';
                  break;
                default:
                  xApp = 'api';
                  break;
              }

              options.headers['x-aicycle-application'] = xApp;
            }
          } catch (_) {
            // Config not yet initialized
          }
          _logger.d('====================REQUEST===================');
          _logger.d(
            '[${options.method}] => PATH: ${options.baseUrl}${options.path}',
          );
          if (options.queryParameters.isNotEmpty) {
            _logger.d('PARAM: ${options.queryParameters}');
          }
          if (options.data != null) {
            _logger.d('BODY: ${options.data}');
          }
          _logger.d('cURL:\n${_renderCurl(options)}');
          _logger.d('\n');

          return handler.next(options);
        },
        onResponse: (response, handler) {
          _logger.d('====================RESPONSE===================');
          _logger.d(
            '[${response.statusCode}] => PATH: ${response.requestOptions.baseUrl}${response.requestOptions.path}',
          );
          // _logger.d('RESPONSE DATA: ${response.data}');
          _logger.d('\n');
          return handler.next(response);
        },
        onError: (e, handler) {
          _logger.d('====================ERROR===================');
          _logger.e(
            '[${e.response?.statusCode}] => PATH: ${e.requestOptions.baseUrl}${e.requestOptions.path}',
            e.error,
          );
          _logger.d('ERROR: ${e.message}');
          _logger.d('ERROR RESPONSE: ${e.response?.data}');
          _logger.d('\n');
          return handler.next(e);
        },
      ),
    );
  }

  /// Wraps a Dio request with error handling and mapping to domain exceptions.
  ///
  /// [T] is the expected return type from the data mapper.
  Future<T> safeCall<T>(Future<Response> Function() call) async {
    try {
      final response = await call();
      return response.data as T;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  Exception _handleDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const NetworkException(
        'Connection timed out. Please check your internet.',
      );
    }

    if (e.response != null) {
      final statusCode = e.response?.statusCode;
      final data = e.response?.data;
      final message = (data is Map && data.containsKey('message'))
          ? data['message'].toString()
          : (data is Map && data.containsKey('errorMessage'))
              ? data['errorMessage'].toString()
              : e.message;
      final engineCode =
          (data is Map && data.containsKey('errorCodeFromEngine'))
              ? data['errorCodeFromEngine'] as int
              : null;

      if (engineCode != null && engineCode != 0) {
        return EngineException(message, engineCode);
      }

      if (statusCode == 401 || statusCode == 403) {
        return UnauthorizedException(message);
      }

      return ServerException(message, statusCode);
    }

    return ServerException(e.message);
  }

  // Shorthand methods using safeCall
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    String? customBaseUrl,
  }) async {
    return safeCall<T>(
      () => _dio.get(
        path,
        queryParameters: queryParameters,
        options: Options(extra: {'customBaseUrl': customBaseUrl}),
      ),
    );
  }

  Future<T> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    String? customBaseUrl,
    Map<String, dynamic>? headers,
    bool skipDefaultAuth = false,
  }) async {
    return safeCall<T>(
      () => _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          headers: headers,
          extra: {
            'customBaseUrl': customBaseUrl,
            'skipDefaultAuth': skipDefaultAuth,
          },
        ),
      ),
    );
  }

  Future<T> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    return safeCall<T>(
      () => _dio.put(path, data: data, queryParameters: queryParameters),
    );
  }

  Future<T> delete<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return safeCall<T>(
      () => _dio.delete(path, queryParameters: queryParameters),
    );
  }

  /// Downloads a file from an absolute [url] to [savePath].
  ///
  /// [onReceiveProgress] reports (received, total) bytes; total is -1 when
  /// the server does not send a content-length header.
  Future<void> download(
    String url,
    String savePath, {
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    try {
      await _dio.download(url, savePath, onReceiveProgress: onReceiveProgress);
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  /// Returns the size in bytes of the resource at [url] without
  /// downloading it, or null when it cannot be determined.
  Future<int?> getContentLength(String url) async {
    try {
      final response = await _dio.head(url);
      final length = response.headers.value(Headers.contentLengthHeader);
      final parsed = length != null ? int.tryParse(length) : null;
      if (parsed != null) return parsed;
    } catch (_) {
      // HEAD not supported — fall through to ranged GET
    }
    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {'Range': 'bytes=0-0'},
          responseType: ResponseType.bytes,
        ),
      );
      // content-range: "bytes 0-0/12345678"
      final contentRange = response.headers.value('content-range');
      final total = contentRange?.split('/').last;
      return total != null ? int.tryParse(total) : null;
    } catch (_) {
      return null;
    }
  }

  /// Creates a FormData object for multipart requests.
  Future<FormData> createFormData(Map<String, dynamic> data) async {
    return FormData.fromMap(data);
  }

  /// Creates a MultipartFile from a local path.
  Future<MultipartFile> createMultipartFile(String filePath) async {
    return MultipartFile.fromFile(filePath);
  }

  String _renderCurl(RequestOptions options) {
    List<String> components = ['curl -i'];
    if (options.method.toUpperCase() != 'GET') {
      components.add('-X ${options.method.toUpperCase()}');
    }

    options.headers.forEach((k, v) {
      if (k != 'Cookie') {
        components.add('-H "$k: $v"');
      }
    });

    if (options.data != null) {
      if (options.data is FormData) {
        final formData = options.data as FormData;
        for (final field in formData.fields) {
          components.add('-F "${field.key}=${field.value}"');
        }
        for (final file in formData.files) {
          components.add('-F "${file.key}=@${file.value.filename}"');
        }
      } else {
        try {
          final data = json.encode(options.data);
          components.add("-d '$data'");
        } catch (_) {
          components.add("-d '${options.data}'");
        }
      }
    }

    final query = options.queryParameters.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    final url =
        options.baseUrl + options.path + (query.isEmpty ? '' : '?$query');
    components.add('"$url"');

    return components.join(' \\\n  ');
  }
}
