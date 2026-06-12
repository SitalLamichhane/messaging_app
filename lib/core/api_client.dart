import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:messaging_app/core/config/app_config.dart';

class ApiClient {
  static const FlutterSecureStorage storage = FlutterSecureStorage();

  static String get baseUrl => AppConfig.apiBaseUrl;

  static final Dio _refreshDio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  static final Dio dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (_isAuthRoute(options.path)) {
            options.headers.remove('Authorization');
          } else {
            final hasAuth =
                options.headers['Authorization']?.toString().trim().isNotEmpty ==
                    true;

            if (!hasAuth) {
              final access = await storage.read(key: 'access');

              if (access != null && access.trim().isNotEmpty) {
                options.headers['Authorization'] = 'Bearer ${access.trim()}';
              }
            }
          }

          _logRequest(options);
          handler.next(options);
        },
        onResponse: (response, handler) {
          _logResponse(response);
          handler.next(response);
        },
        onError: (DioException e, handler) async {
          _logError(e);

          final isAuthRoute = _isAuthRoute(e.requestOptions.path);

          if (e.response?.statusCode == 401 && !isAuthRoute) {
            final newAccess = await refreshAccessToken();

            if (newAccess != null && newAccess.trim().isNotEmpty) {
              try {
                final retryOptions = e.requestOptions;
                retryOptions.headers['Authorization'] =
                    'Bearer ${newAccess.trim()}';

                final retryResponse = await dio.fetch(retryOptions);
                return handler.resolve(retryResponse);
              } catch (retryError) {
                debugPrint('RETRY ERROR: $retryError');
              }
            }
          }

          handler.next(e);
        },
      ),
    );

  static bool _isAuthRoute(String path) {
    return path.contains('/accounts/otp/send/') ||
        path.contains('/accounts/otp/verify/') ||
        path.contains('/accounts/login/') ||
        path.contains('/token/refresh/');
  }

  static Future<String?> refreshAccessToken() async {
    try {
      final refresh = await storage.read(key: 'refresh');

      if (refresh == null || refresh.trim().isEmpty) {
        return null;
      }

      final response = await _refreshDio.post(
        '/token/refresh/',
        data: {
          'refresh': refresh.trim(),
        },
      );

      final newAccess = response.data['access'];

      if (newAccess == null || newAccess.toString().trim().isEmpty) {
        return null;
      }

      await storage.write(
        key: 'access',
        value: newAccess.toString(),
      );

      return newAccess.toString();
    } on DioException catch (e) {
      debugPrint('REFRESH TOKEN ERROR: ${e.message}');

      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        await clearTokens();
      }

      return null;
    } catch (e) {
      debugPrint('REFRESH TOKEN ERROR: $e');
      return null;
    }
  }

  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await storage.write(key: 'access', value: access.trim());
    await storage.write(key: 'refresh', value: refresh.trim());
  }

  static Future<String?> getAccessToken() async {
    return storage.read(key: 'access');
  }

  static Future<String?> getRefreshToken() async {
    return storage.read(key: 'refresh');
  }

  static Future<void> clearTokens() async {
    await storage.delete(key: 'access');
    await storage.delete(key: 'refresh');
  }

  static void _logRequest(RequestOptions options) {
    debugPrint('╔════════ REQUEST ════════');
    debugPrint('URL: ${options.uri}');
    debugPrint('METHOD: ${options.method}');
    debugPrint('HEADERS: ${options.headers}');
    debugPrint('BODY: ${options.data}');
    debugPrint('╚════════════════════════');
  }

  static void _logResponse(Response response) {
    debugPrint('╔════════ RESPONSE ════════');
    debugPrint('URL: ${response.requestOptions.uri}');
    debugPrint('STATUS: ${response.statusCode}');
    debugPrint('DATA: ${response.data}');
    debugPrint('╚═════════════════════════');
  }

  static void _logError(DioException e) {
    debugPrint('╔════════ ERROR ════════');
    debugPrint('URL: ${e.requestOptions.uri}');
    debugPrint('STATUS: ${e.response?.statusCode}');
    debugPrint('MESSAGE: ${e.message}');
    debugPrint('RESPONSE: ${e.response?.data}');
    debugPrint('╚═══════════════════════');
  }
}