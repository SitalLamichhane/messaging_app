import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hiddenly/core/config/app_config.dart';

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
            final access = await storage.read(key: 'access');

            if (access != null && access.isNotEmpty) {
              options.headers['Authorization'] =
                  'Bearer ${access.trim()}';
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

          final isAuth = _isAuthRoute(e.requestOptions.path);

          if (e.response?.statusCode == 401 && !isAuth) {
            final newAccess = await _refreshToken();

            if (newAccess != null && newAccess.isNotEmpty) {
              try {
                final request = e.requestOptions;

                request.headers['Authorization'] =
                    'Bearer $newAccess';

                final retryResponse = await dio.fetch(request);
                return handler.resolve(retryResponse);
              } catch (retryError) {
                debugPrint('RETRY FAILED: $retryError');
              }
            }
          }

          handler.next(e);
        },
      ),
    );

  // ---------------------------
  // AUTH ROUTES
  // ---------------------------
  static bool _isAuthRoute(String path) {
    return path.contains('/accounts/otp/send/') ||
        path.contains('/accounts/otp/verify/') ||
        path.contains('/accounts/login/') ||
        path.contains('/token/refresh/');
  }

  // ---------------------------
  // REFRESH TOKEN
  // ---------------------------
  static Future<String?> _refreshToken() async {
    try {
      final refresh = await storage.read(key: 'refresh');

      if (refresh == null || refresh.isEmpty) return null;

      final response = await _refreshDio.post(
        '/token/refresh/',
        data: {'refresh': refresh.trim()},
      );

      final newAccess = response.data['access'];

      if (newAccess == null || newAccess.toString().isEmpty) {
        return null;
      }

      await storage.write(
        key: 'access',
        value: newAccess.toString(),
      );

      return newAccess.toString();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 ||
          e.response?.statusCode == 403) {
        await clearTokens();
      }

      debugPrint('REFRESH ERROR: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('REFRESH ERROR: $e');
      return null;
    }
  }

  // ---------------------------
  // TOKEN HELPERS
  // ---------------------------
  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await storage.write(key: 'access', value: access.trim());
    await storage.write(key: 'refresh', value: refresh.trim());
  }

  static Future<String?> getAccessToken() =>
      storage.read(key: 'access');

  static Future<String?> getRefreshToken() =>
      storage.read(key: 'refresh');

  static Future<void> clearTokens() async {
    await storage.delete(key: 'access');
    await storage.delete(key: 'refresh');
  }

  // ---------------------------
  // SAFE LOGGING
  // ---------------------------
  static void _logRequest(RequestOptions options) {
    if (!kDebugMode) return;

    final headers = Map<String, dynamic>.from(options.headers);

    if (headers.containsKey('Authorization')) {
      headers['Authorization'] = 'Bearer ***';
    }

    debugPrint('╔══ REQUEST');
    debugPrint('URL: ${options.uri}');
    debugPrint('METHOD: ${options.method}');
    debugPrint('HEADERS: $headers');
    debugPrint('BODY: ${options.data}');
    debugPrint('╚══════════');
  }

  static void _logResponse(Response response) {
    if (!kDebugMode) return;

    debugPrint('╔══ RESPONSE');
    debugPrint('URL: ${response.requestOptions.uri}');
    debugPrint('STATUS: ${response.statusCode}');
    debugPrint('DATA: ${response.data}');
    debugPrint('╚══════════');
  }

  static void _logError(DioException e) {
    if (!kDebugMode) return;

    debugPrint('╔══ ERROR');
    debugPrint('URL: ${e.requestOptions.uri}');
    debugPrint('STATUS: ${e.response?.statusCode}');
    debugPrint('MESSAGE: ${e.message}');
    debugPrint('DATA: ${e.response?.data}');
    debugPrint('╚══════════');
  }
}