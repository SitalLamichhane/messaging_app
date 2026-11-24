import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddenly/core/api_client.dart';

class AuthApi {
  static Future<Response> sendOtp(String phone) async {
    try {
      return await ApiClient.dio.post(
        '/accounts/otp/send/',
        data: {'phone': phone.trim()},
      );
    } on DioException catch (e) {
      _logFailure('Send OTP', e);
      throw Exception(
        _errorMessage(
          e,
          keys: const [
            'message',
            'detail',
            'error',
            'phone',
            'non_field_errors',
          ],
          statusMessages: const {
            429: 'Too many OTP requests. Please try again later.',
          },
          fallback: 'Failed to send OTP.',
        ),
      );
    }
  }

  static Future<Response> verifyOtp({
    required String phone,
    required String code,
  }) async {
    try {
      return await ApiClient.dio.post(
        '/accounts/otp/verify/',
        data: {'phone': phone.trim(), 'code': code.trim()},
      );
    } on DioException catch (e) {
      _logFailure('Verify OTP', e);
      throw Exception(
        _errorMessage(
          e,
          keys: const [
            'code',
            'message',
            'detail',
            'error',
            'non_field_errors',
          ],
          statusMessages: const {
            400: 'Invalid OTP.',
            401: 'OTP verification failed.',
            429: 'Too many attempts. Please try again later.',
          },
          fallback: 'Unable to verify OTP.',
        ),
      );
    }
  }

  static Future<Response> completeSignup({
    required String signupToken,
    required String fullName,
    required String bio,
  }) async {
    try {
      return await ApiClient.dio.post(
        '/accounts/signup/complete/',
        data: {'full_name': fullName.trim(), 'bio': bio.trim()},
        options: Options(
          headers: {'Authorization': 'Bearer ${signupToken.trim()}'},
        ),
      );
    } on DioException catch (e) {
      _logFailure('Complete signup', e);
      throw Exception(
        _errorMessage(
          e,
          keys: const [
            'message',
            'detail',
            'error',
            'full_name',
            'bio',
            'non_field_errors',
          ],
          statusMessages: const {
            401: 'Signup session expired. Please request OTP again.',
            400: 'Unable to complete signup. Please check your information.',
            429: 'Too many requests. Please try again later.',
          },
          fallback: 'Signup failed.',
        ),
      );
    }
  }

  static void _logFailure(String operation, DioException e) {
    if (kDebugMode) {
      debugPrint(
        '$operation failed: ${e.type.name}, HTTP ${e.response?.statusCode ?? "none"}',
      );
    }
  }

  static String _errorMessage(
    DioException e, {
    required List<String> keys,
    required Map<int, String> statusMessages,
    required String fallback,
  }) {
    final data = e.response?.data;
    if (data is Map) {
      for (final key in keys) {
        if (data[key] != null) return _extractErrorValue(data[key]);
      }
    }
    if (e.response == null) return _getNetworkErrorMessage(e);
    final status = e.response?.statusCode;
    if (status != null && statusMessages.containsKey(status)) {
      return statusMessages[status]!;
    }
    if (status != null && status >= 500) {
      return 'Server error. Please try again.';
    }
    return fallback;
  }

  static String _extractErrorValue(dynamic value) {
    if (value == null) return 'Something went wrong.';
    if (value is List) {
      return value.isEmpty
          ? 'Something went wrong.'
          : _extractErrorValue(value.first);
    }
    if (value is Map) {
      return value.isEmpty
          ? 'Something went wrong.'
          : _extractErrorValue(value.values.first);
    }
    final text = value.toString().trim();
    return text.isEmpty ? 'Something went wrong.' : text;
  }

  static String _getNetworkErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timeout. Please try again.';
      case DioExceptionType.sendTimeout:
        return 'Request timeout. Please try again.';
      case DioExceptionType.receiveTimeout:
        return 'Server response timeout. Please try again.';
      case DioExceptionType.transformTimeout:
        return 'Request processing timeout. Please try again.';
      case DioExceptionType.connectionError:
        return 'Unable to connect to the server. Check your internet connection.';
      case DioExceptionType.badCertificate:
        return 'Secure connection failed. Please check the server SSL certificate.';
      case DioExceptionType.cancel:
        return 'Request cancelled.';
      case DioExceptionType.badResponse:
        return 'Server returned an invalid response.';
      case DioExceptionType.unknown:
        return 'Network error. Please try again.';
    }
  }
}
