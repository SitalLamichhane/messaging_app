import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/features/auth/auth_api.dart';

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

    isLoggedIn = accessToken != null && accessToken!.trim().isNotEmpty;
    notifyListeners();
  }

  Future<bool> sendOtp(String phone) async {
    isLoading = true;
    notifyListeners();

    try {
      await AuthApi.sendOtp(phone);
      return true;
    } catch (e) {
      debugPrint('SEND OTP ERROR: $e');
      throw Exception(e.toString().replaceAll("Exception: ", ""));
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
        phone: phone,
        code: code,
      );

      final data = Map<String, dynamic>.from(response.data);

      if (data['type'] == 'login') {
        await _saveLoginData(data);
        return 'login';
      }

      if (data['type'] == 'signup') {
        signupToken = data['signup_token']?.toString().trim();

        if (signupToken == null || signupToken!.isEmpty) {
          throw Exception('Signup token missing');
        }

        await ApiClient.storage.write(
          key: 'signup_token',
          value: signupToken!,
        );

        return 'signup';
      }

      return null;
    } catch (e) {
      debugPrint('VERIFY OTP ERROR: $e');
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> completeSignup({
    required String fullName,
    required String bio,
  }) async {
    String? token = signupToken ??
        await ApiClient.storage.read(key: 'signup_token');

    if (token == null || token.isEmpty) {
      throw Exception('Signup token missing');
    }

    isLoading = true;
    notifyListeners();

    try {
      final response = await AuthApi.completeSignup(
        signupToken: token,
        fullName: fullName,
        bio: bio,
      );

      await _saveLoginData(Map<String, dynamic>.from(response.data));

      await ApiClient.storage.delete(key: 'signup_token');
      signupToken = null;

      return true;
    } catch (e) {
      debugPrint('COMPLETE SIGNUP ERROR: $e');
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveLoginData(Map<String, dynamic> data) async {
    final tokens = data['tokens'];

    accessToken = tokens['access']?.toString();
    refreshToken = tokens['refresh']?.toString();

    await ApiClient.storage.write(key: 'access', value: accessToken);
    await ApiClient.storage.write(key: 'refresh', value: refreshToken);

    final rawUser = data['user'];
    if (rawUser is Map) {
      user = Map<String, dynamic>.from(rawUser);
    }

    isLoggedIn = true;
    notifyListeners();
  }

  Future<void> logout() async {
    await ApiClient.storage.deleteAll();

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    accessToken = null;
    refreshToken = null;
    signupToken = null;
    user = null;
    isLoggedIn = false;

    notifyListeners();
  }
}//Gitpush