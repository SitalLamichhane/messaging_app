import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  static const storage = FlutterSecureStorage();

  static const String baseUrl = 'http://192.168.1.112:8000/api';

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

  static Future<String?> refreshAccessToken() async {
    try {
      final refresh = await storage.read(key: 'refresh');

      if (refresh == null || refresh.trim().isEmpty) {
        return null;
      }

      final response = await _refreshDio.post(
        '/token/refresh/',
        data: {'refresh': refresh.trim()},
      );

      final newAccess = response.data['access'];

      if (newAccess == null || newAccess.toString().trim().isEmpty) {
        return null;
      }

      await storage.write(key: 'access', value: newAccess.toString());
      return newAccess.toString();
    } catch (e) {
      debugPrint('REFRESH TOKEN ERROR: $e');
      await storage.delete(key: 'access');
      await storage.delete(key: 'refresh');
      return null;
    }
  }

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
          final path = options.path;

          final isAuthRoute =
               path.contains('/accounts/otp/send/') ||
               path.contains('/accounts/otp/verify/') ||
               path.contains('/accounts/login/') ||
               path.contains('/token/refresh/');
          if (!isAuthRoute) {
  final alreadyHasAuthorization =
      options.headers['Authorization']?.toString().trim().isNotEmpty == true;

  if (!alreadyHasAuthorization) {
    final token = await storage.read(key: 'access');

    if (token != null && token.trim().isNotEmpty) {
      options.headers['Authorization'] = 'Bearer ${token.trim()}';
    }
  }
} else {
  options.headers.remove('Authorization');
} 

          debugPrint('╔════════ REQUEST ════════');
          debugPrint('URL: ${options.baseUrl}${options.path}');
          debugPrint('METHOD: ${options.method}');
          debugPrint('HEADERS: ${options.headers}');
          debugPrint('BODY: ${options.data}');
          debugPrint('╚════════════════════════');

          handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint('╔════════ RESPONSE ════════');
          debugPrint('URL: ${response.requestOptions.path}');
          debugPrint('STATUS: ${response.statusCode}');
          debugPrint('DATA: ${response.data}');
          debugPrint('╚═════════════════════════');

          handler.next(response);
        },
        onError: (DioException e, handler) async {
          debugPrint('╔════════ ERROR ════════');
          debugPrint('URL: ${e.requestOptions.path}');
          debugPrint('MESSAGE: ${e.message}');
          debugPrint('RESPONSE: ${e.response?.data}');
          debugPrint('╚═══════════════════════');

          final path = e.requestOptions.path;

          final isAuthRoute =
              path.contains('/accounts/otp/send/') ||
              path.contains('/accounts/otp/verify/') ||
              path.contains('/accounts/login/') ||
              path.contains('/token/refresh/');

          if (e.response?.statusCode == 401 && !isAuthRoute) {
            final newToken = await refreshAccessToken();

            if (newToken != null && newToken.trim().isNotEmpty) {
              final requestOptions = e.requestOptions;
              requestOptions.headers['Authorization'] =
                  'Bearer ${newToken.trim()}';

              try {
                final retryResponse = await dio.fetch(requestOptions);
                return handler.resolve(retryResponse);
              } catch (_) {
                return handler.next(e);
              }
            }
          }

          handler.next(e);
        },
      ),
    );
}