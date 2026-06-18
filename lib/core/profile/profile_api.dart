// lib/core/profile/profile_api.dart

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hiddenly/core/api_client.dart';

class ProfileApi {
  static Future<Response> me() {
    return ApiClient.dio.get('/accounts/me/');
  }

  static Future<Response> editProfile({
    required String fullName,
    String bio = '',
    String businessName = '',
    File? image,
  }) async {
    final formData = FormData.fromMap({
      'full_name': fullName.trim(),
      'bio': bio.trim(),
      'business_name': businessName.trim(),

      // Backend can accept either image/profile_image/avatar.
      // Main field name is image.
      if (image != null)
        'profile_picture': await MultipartFile.fromFile(
          image.path,
          filename: image.path.split('/').last,
        ),
    });

    return ApiClient.dio.patch(
      '/accounts/profile/edit/',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
  }
}
