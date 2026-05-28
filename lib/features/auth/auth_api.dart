import 'package:dio/dio.dart';
import 'package:messaging_app/core/api_client.dart';

class AuthApi {
  static Future<Response> sendOtp(String phone) {
    return ApiClient.dio.post(
      '/accounts/otp/send/',
      data: {
        'phone': phone.trim(),
      },
    );
  }

  static Future<Response> verifyOtp({
    required String phone,
    required String code,
  }) {
    return ApiClient.dio.post(
      '/accounts/otp/verify/',
      data: {
        'phone': phone.trim(),
        'code': code.trim(),
      },
    );
  }

static Future<Response> completeSignup({
  required String signupToken,
  required String fullName,
  required String bio,
}) {
  return ApiClient.dio.post(
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
}
}