import 'package:dio/dio.dart';
import 'package:hiddenly/core/api_client.dart';

class AuthApi {
  // ============================================================
  // SEND OTP
  // ============================================================

  static Future<Response> sendOtp(String phone) async {
    try {
      return await ApiClient.dio.post(
        '/accounts/otp/send/',
        data: {
          'phone': phone.trim(),
        },
      );
    } on DioException catch (e) {
      print('========== SEND OTP ERROR ==========');
      print('Type: ${e.type}');
      print('Message: ${e.message}');
      print('Error: ${e.error}');
      print('Status: ${e.response?.statusCode}');
      print('Response: ${e.response?.data}');
      print('====================================');

      final data = e.response?.data;

      if (data is Map) {
        if (data['message'] != null) {
          throw Exception(
            _extractErrorValue(data['message']),
          );
        }

        if (data['detail'] != null) {
          throw Exception(
            _extractErrorValue(data['detail']),
          );
        }

        if (data['error'] != null) {
          throw Exception(
            _extractErrorValue(data['error']),
          );
        }

        if (data['phone'] != null) {
          throw Exception(
            _extractErrorValue(data['phone']),
          );
        }
      }

      if (e.response == null) {
        throw Exception(
          _getNetworkErrorMessage(e),
        );
      }

      throw Exception(
        'Failed to send OTP.',
      );
    }
  }

  // ============================================================
  // VERIFY OTP
  // ============================================================

  static Future<Response> verifyOtp({
    required String phone,
    required String code,
  }) async {
    try {
      return await ApiClient.dio.post(
        '/accounts/otp/verify/',
        data: {
          'phone': phone.trim(),
          'code': code.trim(),
        },
      );
    } on DioException catch (e) {
      print('========== VERIFY OTP ERROR ==========');
      print('Type: ${e.type}');
      print('Message: ${e.message}');
      print('Error: ${e.error}');
      print('Status: ${e.response?.statusCode}');
      print('Response: ${e.response?.data}');
      print('======================================');

      final data = e.response?.data;

      if (data is Map) {
        /*
         * Your backend currently returns:
         *
         * {
         *   "code": "Invalid OTP."
         * }
         *
         * So "code" must be checked before Dio's generic message.
         */
        if (data['code'] != null) {
          throw Exception(
            _extractErrorValue(data['code']),
          );
        }

        if (data['message'] != null) {
          throw Exception(
            _extractErrorValue(data['message']),
          );
        }

        if (data['detail'] != null) {
          throw Exception(
            _extractErrorValue(data['detail']),
          );
        }

        if (data['error'] != null) {
          throw Exception(
            _extractErrorValue(data['error']),
          );
        }

        if (data['non_field_errors'] != null) {
          throw Exception(
            _extractErrorValue(
              data['non_field_errors'],
            ),
          );
        }
      }

      if (e.response == null) {
        throw Exception(
          _getNetworkErrorMessage(e),
        );
      }

      if (e.response?.statusCode == 400) {
        throw Exception(
          'Invalid OTP.',
        );
      }

      if (e.response?.statusCode == 401) {
        throw Exception(
          'OTP verification failed.',
        );
      }

      if (e.response?.statusCode == 429) {
        throw Exception(
          'Too many attempts. Please try again later.',
        );
      }

      if (e.response != null &&
          e.response!.statusCode != null &&
          e.response!.statusCode! >= 500) {
        throw Exception(
          'Server error. Please try again.',
        );
      }

      throw Exception(
        'Unable to verify OTP.',
      );
    }
  }

  // ============================================================
  // COMPLETE SIGNUP
  // ============================================================

  static Future<Response> completeSignup({
    required String signupToken,
    required String fullName,
    required String bio,
  }) async {
    try {
      return await ApiClient.dio.post(
        '/accounts/signup/complete/',
        data: {
          'full_name': fullName.trim(),
          'bio': bio.trim(),
        },
        options: Options(
          headers: {
            'Authorization':
                'Bearer ${signupToken.trim()}',
          },
        ),
      );
    } on DioException catch (e) {
      print(
        '========== COMPLETE SIGNUP ERROR ==========',
      );
      print('Type: ${e.type}');
      print('Message: ${e.message}');
      print('Error: ${e.error}');
      print('Status: ${e.response?.statusCode}');
      print('Response: ${e.response?.data}');
      print(
        '===========================================',
      );

      final data = e.response?.data;

      if (data is Map) {
        if (data['message'] != null) {
          throw Exception(
            _extractErrorValue(data['message']),
          );
        }

        if (data['detail'] != null) {
          throw Exception(
            _extractErrorValue(data['detail']),
          );
        }

        if (data['error'] != null) {
          throw Exception(
            _extractErrorValue(data['error']),
          );
        }

        if (data['full_name'] != null) {
          throw Exception(
            _extractErrorValue(data['full_name']),
          );
        }

        if (data['bio'] != null) {
          throw Exception(
            _extractErrorValue(data['bio']),
          );
        }

        if (data['non_field_errors'] != null) {
          throw Exception(
            _extractErrorValue(
              data['non_field_errors'],
            ),
          );
        }
      }

      if (e.response == null) {
        throw Exception(
          _getNetworkErrorMessage(e),
        );
      }

      if (e.response?.statusCode == 401) {
        throw Exception(
          'Signup session expired. Please request OTP again.',
        );
      }

      if (e.response?.statusCode == 400) {
        throw Exception(
          'Unable to complete signup. Please check your information.',
        );
      }

      if (e.response != null &&
          e.response!.statusCode != null &&
          e.response!.statusCode! >= 500) {
        throw Exception(
          'Server error. Please try again.',
        );
      }

      throw Exception(
        'Signup failed.',
      );
    }
  }

  // ============================================================
  // ERROR VALUE EXTRACTOR
  // ============================================================

  static String _extractErrorValue(
    dynamic value,
  ) {
    if (value == null) {
      return 'Something went wrong.';
    }

    if (value is String) {
      return value.trim();
    }

    if (value is List) {
      if (value.isEmpty) {
        return 'Something went wrong.';
      }

      return _extractErrorValue(
        value.first,
      );
    }

    if (value is Map) {
      if (value.isEmpty) {
        return 'Something went wrong.';
      }

      return _extractErrorValue(
        value.values.first,
      );
    }

    return value.toString().trim();
  }

  // ============================================================
  // NETWORK ERROR MESSAGE
  // ============================================================

  static String _getNetworkErrorMessage(
    DioException e,
  ) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timeout. Please try again.';

      case DioExceptionType.sendTimeout:
        return 'Request timeout. Please try again.';

      case DioExceptionType.receiveTimeout:
        return 'Server response timeout. Please try again.';

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