import 'package:flutter/material.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/features/auth/auth_api.dart';

class AuthProvider extends ChangeNotifier {
  bool isLoading = false;
  bool isLoggedIn = false;

  String? accessToken;
  String? refreshToken;
  String? signupToken;

  Map<String, dynamic>? user;

Future<void> checkLogin() async {
  accessToken = await ApiClient.storage.read(key: 'access');
  refreshToken = await ApiClient.storage.read(key: 'refresh');

  final storedUserId = await ApiClient.storage.read(key: 'user_id');
  final storedFullName = await ApiClient.storage.read(key: 'full_name');
  final storedPhone = await ApiClient.storage.read(key: 'phone');
  final storedBio = await ApiClient.storage.read(key: 'bio');

  if (storedUserId != null && storedUserId.trim().isNotEmpty) {
    user = {
      'id': storedUserId,
      'full_name': storedFullName ?? '',
      'phone': storedPhone ?? '',
      'bio': storedBio ?? '',
    };
  }

  isLoggedIn = accessToken != null && accessToken!.trim().isNotEmpty;
  notifyListeners();
}

  Future<bool> sendOtp(String phone) async {
    isLoading = true;
    notifyListeners();

    try {
      await AuthApi.sendOtp(phone.trim());
      return true;
    } catch (e) {
      debugPrint('SEND OTP ERROR: $e');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> verifyOtp({
    required String phone,
    required String code,
  }) async {
    isLoading = true;
    notifyListeners();

    try {
      final response = await AuthApi.verifyOtp(
        phone: phone.trim(),
        code: code.trim(),
      );

      final data = response.data;

      if (data['type'] == 'login') {
        await _saveLoginData(data);
        return 'login';
      }

      if (data['type'] == 'signup') {
        final token = data['signup_token']?.toString().trim();

        if (token == null || token.isEmpty) {
          throw Exception('Signup token missing from server response');
        }

        signupToken = token;

        await ApiClient.storage.write(
          key: 'signup_token',
          value: token,
        );

        return 'signup';
      }

      return null;
    } catch (e) {
      debugPrint('VERIFY OTP ERROR: $e');
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> completeSignup({
    required String fullName,
    required String bio,
  }) async {
    String? token = signupToken;

    token ??= await ApiClient.storage.read(key: 'signup_token');

    if (token == null || token.trim().isEmpty) {
      debugPrint('COMPLETE SIGNUP ERROR: signup token missing');
      return false;
    }

    isLoading = true;
    notifyListeners();

    try {
      final response = await AuthApi.completeSignup(
        signupToken: token.trim(),
        fullName: fullName.trim(),
        bio: bio.trim(),
      );

      await _saveLoginData(response.data);

      await ApiClient.storage.delete(key: 'signup_token');
      signupToken = null;

      return true;
    } catch (e) {
      debugPrint('COMPLETE SIGNUP ERROR: $e');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveLoginData(Map<String, dynamic> data) async {
    accessToken = data['tokens']['access']?.toString();
    refreshToken = data['tokens']['refresh']?.toString();
    user = data['user'];

    if (accessToken == null || refreshToken == null) {
      throw Exception('Login token missing from server response');
    }

    await ApiClient.storage.write(
      key: 'access',
      value: accessToken!.trim(),
    );

    await ApiClient.storage.write(
      key: 'refresh',
      value: refreshToken!.trim(),
    );

    if (user != null) {
      await ApiClient.storage.write(
        key: 'user_id',
        value: user!['id'].toString(),
      );

      await ApiClient.storage.write(
        key: 'full_name',
        value: user!['full_name']?.toString() ?? '',
      );

      await ApiClient.storage.write(
        key: 'phone',
        value: user!['phone']?.toString() ?? '',
      );

      await ApiClient.storage.write(
        key: 'bio',
        value: user!['bio']?.toString() ?? '',
      );
    }

    isLoggedIn = true;
    notifyListeners();
  }

  Future<void> logout() async {
    await ApiClient.storage.deleteAll();

    accessToken = null;
    refreshToken = null;
    signupToken = null;
    user = null;
    isLoggedIn = false;

    notifyListeners();
  }
}