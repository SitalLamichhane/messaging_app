import 'package:dio/dio.dart';
import 'package:hiddenly/core/api_client.dart';

class AuthApi {
  static Future<Response> sendOtp(String phone) async {
    try {
      return await ApiClient.dio.post(
        '/accounts/otp/send/',
        data: {'phone': phone.trim()},
      );
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? 'Failed to send OTP';
      throw Exception(msg);
    }
  }

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
      final data = e.response?.data;

      final msg = (data is Map && data['message'] != null)
          ? data['message'].toString()
          : 'Invalid code';

      throw Exception(msg);
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
        data: {
          'full_name': fullName.trim(),
          'bio': bio.trim(),
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer ${signupToken.trim()}',
          },
        ),
      );
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? 'Signup failed';
      throw Exception(msg);
    }
  }
}//Gitpush