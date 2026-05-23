import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'token_storage.dart';

/// Lỗi API có message tiếng Việt + map errors theo field (Laravel style).
class ApiException implements Exception {
  final String message;
  final Map<String, List<String>> errors;
  final int? code;

  ApiException(this.message, {this.errors = const {}, this.code});

  @override
  String toString() => message;
}

/// Singleton Dio client. Tự đính kèm Bearer token và bóc tách envelope
/// `{ code, message, data, errors }` của Woofoo API.
class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStorage.read();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          if (e.response?.statusCode == 401) {
            await TokenStorage.clear();
          }
          handler.next(e);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._();
  late final Dio _dio;

  /// Thực hiện request và trả về phần `data` của envelope.
  /// Ném [ApiException] khi `code` không phải 2xx hoặc khi lỗi mạng.
  Future<dynamic> request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.request(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method),
      );
      return _unwrap(res.data);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  dynamic _unwrap(dynamic body) {
    if (body is Map<String, dynamic>) {
      final code = body['code'];
      if (code is int && code >= 200 && code < 300) {
        return body['data'];
      }
      throw ApiException(
        body['message']?.toString() ?? 'Có lỗi xảy ra',
        errors: _parseErrors(body['errors']),
        code: code is int ? code : null,
      );
    }
    return body;
  }

  ApiException _toApiException(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return ApiException('Không thể kết nối đến máy chủ. Vui lòng thử lại.');
    }
    final body = e.response?.data;
    if (body is Map<String, dynamic>) {
      return ApiException(
        body['message']?.toString() ?? 'Có lỗi xảy ra',
        errors: _parseErrors(body['errors']),
        code: body['code'] is int ? body['code'] : e.response?.statusCode,
      );
    }
    return ApiException('Có lỗi xảy ra. Vui lòng thử lại.');
  }

  Map<String, List<String>> _parseErrors(dynamic raw) {
    if (raw is Map) {
      return raw.map(
        (k, v) => MapEntry(
          k.toString(),
          (v is List) ? v.map((e) => e.toString()).toList() : [v.toString()],
        ),
      );
    }
    return {};
  }
}
