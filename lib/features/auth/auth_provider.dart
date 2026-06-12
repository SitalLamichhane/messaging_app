// lib/features/auth/auth_provider.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final storedAvatar =
        await ApiClient.storage.read(key: 'avatar_url') ??
        await ApiClient.storage.read(key: 'image_url') ??
        '';

    if (storedUserId != null && storedUserId.trim().isNotEmpty) {
      user = {
        'id': storedUserId,
        'full_name': storedFullName ?? '',
        'phone': storedPhone ?? '',
        'bio': storedBio ?? '',
        'profile_picture': storedAvatar,
      };

      await _saveUserToSharedPreferences(
        id: storedUserId,
        fullName: storedFullName ?? '',
        avatar: storedAvatar,
      );
    }

    isLoggedIn = accessToken != null && accessToken!.trim().isNotEmpty;

    debugPrint('AUTH CHECK LOGIN: $isLoggedIn');
    debugPrint('AUTH CHECK USER ID: ${user?['id'] ?? ''}');

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

      final data = Map<String, dynamic>.from(response.data);

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

      await _saveLoginData(Map<String, dynamic>.from(response.data));

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
    final tokens = data['tokens'];

    if (tokens is! Map) {
      throw Exception('Tokens missing from server response');
    }

    accessToken = tokens['access']?.toString();
    refreshToken = tokens['refresh']?.toString();

    if (accessToken == null || accessToken!.trim().isEmpty) {
      throw Exception('Access token missing from server response');
    }

    if (refreshToken == null || refreshToken!.trim().isEmpty) {
      throw Exception('Refresh token missing from server response');
    }

    final rawUser = data['user'];

    if (rawUser is Map) {
      user = Map<String, dynamic>.from(rawUser);
    } else {
      user = null;
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
      final id = _readUserValue(user!, [
        'id',
        'user_id',
      ]);

      final fullName = _readUserValue(user!, [
        'full_name',
        'name',
        'username',
        'display_name',
      ]);

      final phone = _readUserValue(user!, [
        'phone',
        'phone_number',
      ]);

      final bio = _readUserValue(user!, [
        'bio',
      ]);

      final avatar = _readUserValue(user!, [
        'profile_picture',
        'profile_image',
        'avatar',
        'avatar_url',
        'image_url',
      ]);

      if (id.trim().isEmpty) {
        throw Exception('User id missing from server response');
      }

      await ApiClient.storage.write(
        key: 'user_id',
        value: id,
      );

      await ApiClient.storage.write(
        key: 'full_name',
        value: fullName,
      );

      await ApiClient.storage.write(
        key: 'phone',
        value: phone,
      );

      await ApiClient.storage.write(
        key: 'bio',
        value: bio,
      );

      await ApiClient.storage.write(
        key: 'avatar_url',
        value: avatar,
      );

      await ApiClient.storage.write(
        key: 'image_url',
        value: avatar,
      );

      await _saveUserToSharedPreferences(
        id: id,
        fullName: fullName,
        avatar: avatar,
      );

      debugPrint('AUTH SAVED USER ID: $id');
      debugPrint('AUTH SAVED USER NAME: $fullName');
      debugPrint('AUTH SAVED USER AVATAR: $avatar');
    } else {
      debugPrint('AUTH WARNING: user object missing from login response');
    }

    isLoggedIn = true;
    notifyListeners();
  }

  String _readUserValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }

    return '';
  }

  Future<void> _saveUserToSharedPreferences({
    required String id,
    required String fullName,
    required String avatar,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('user_id', id);
    await prefs.setString('user_name', fullName);
    await prefs.setString('user_avatar', avatar);

    debugPrint('AUTH SAVED TO SHARED PREF USER ID: $id');
    debugPrint('AUTH SAVED TO SHARED PREF USER NAME: $fullName');
  }

  Future<void> logout() async {
    await ApiClient.storage.deleteAll();

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_avatar');

    accessToken = null;
    refreshToken = null;
    signupToken = null;
    user = null;
    isLoggedIn = false;

    notifyListeners();
  }
}