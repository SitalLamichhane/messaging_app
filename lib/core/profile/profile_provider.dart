// lib/core/profile/profile_provider.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/core/profile/profile_api.dart';

class UserProfile {
  final String id;
  final String fullName;
  final String phone;
  final String bio;
  final String businessName;
  final String imageUrl;

  const UserProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.bio,
    required this.businessName,
    required this.imageUrl,
  });

  factory UserProfile.empty() {
    return const UserProfile(
      id: '',
      fullName: '',
      phone: '',
      bio: '',
      businessName: '',
      imageUrl: '',
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final user = json['user'];

    final Map<String, dynamic> data = user is Map
        ? Map<String, dynamic>.from(user)
        : Map<String, dynamic>.from(json);

    return UserProfile(
      id: (data['id'] ?? data['user_id'] ?? '').toString(),
      fullName:
          (data['full_name'] ??
                  data['name'] ??
                  data['username'] ??
                  data['display_name'] ??
                  '')
              .toString(),
      phone: (data['phone'] ?? data['phone_number'] ?? '').toString(),
      bio: (data['bio'] ?? '').toString(),
      businessName: (data['business_name'] ?? data['business'] ?? '')
          .toString(),
      imageUrl:
          (data['profile_picture'] ??
                  data['profile_image'] ??
                  data['avatar'] ??
                  data['avatar_url'] ??
                  '')
              .toString(),
    );
  }

  UserProfile copyWith({
    String? id,
    String? fullName,
    String? phone,
    String? bio,
    String? businessName,
    String? imageUrl,
  }) {
    return UserProfile(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      bio: bio ?? this.bio,
      businessName: businessName ?? this.businessName,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

class ProfileProvider extends ChangeNotifier {
  bool isLoading = false;
  bool isSaving = false;
  String? error;

  UserProfile profile = UserProfile.empty();

  Future<void> loadProfile() async {
    if (isLoading) return;

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final response = await ProfileApi.me();
      final raw = _asMap(response.data);

      profile = UserProfile.fromJson(raw);

      await _saveProfileToStorage(profile);

      debugPrint('PROFILE LOADED USER ID: ${profile.id}');
      debugPrint('PROFILE LOADED NAME: ${profile.fullName}');
      debugPrint('PROFILE LOADED IMAGE: ${profile.imageUrl}');
    } catch (e) {
      error = _cleanError(e);
      await _loadProfileFromStorage();

      debugPrint('PROFILE LOAD ERROR: $error');
      debugPrint('PROFILE LOADED FROM LOCAL USER ID: ${profile.id}');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateProfile({
    required String fullName,
    String bio = '',
    String businessName = '',
    File? image,
  }) async {
    if (isSaving) return false;

    isSaving = true;
    error = null;
    notifyListeners();

    try {
      final response = await ProfileApi.editProfile(
        fullName: fullName,
        bio: bio,
        businessName: businessName,
        image: image,
      );

      final raw = _asMap(response.data);
      profile = UserProfile.fromJson(raw);

      await _saveProfileToStorage(profile);

      debugPrint('PROFILE UPDATED USER ID: ${profile.id}');
      debugPrint('PROFILE UPDATED NAME: ${profile.fullName}');
      debugPrint('PROFILE UPDATED IMAGE: ${profile.imageUrl}');

      isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = _cleanError(e);
      isSaving = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProfileImage(File image) async {
    return updateProfile(
      fullName: profile.fullName.trim().isEmpty ? 'User' : profile.fullName,
      bio: profile.bio,
      businessName: profile.businessName,
      image: image,
    );
  }

  Future<void> logoutLocal() async {
    await ApiClient.storage.delete(key: 'access');
    await ApiClient.storage.delete(key: 'refresh');
    await ApiClient.storage.delete(key: 'user_id');
    await ApiClient.storage.delete(key: 'full_name');
    await ApiClient.storage.delete(key: 'phone');
    await ApiClient.storage.delete(key: 'bio');
    await ApiClient.storage.delete(key: 'business_name');
    await ApiClient.storage.delete(key: 'image_url');
    await ApiClient.storage.delete(key: 'avatar_url');

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_avatar');

    profile = UserProfile.empty();
    error = null;
    notifyListeners();
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    throw Exception('Invalid profile response');
  }

  Future<void> _saveProfileToStorage(UserProfile value) async {
    await ApiClient.storage.write(key: 'user_id', value: value.id);
    await ApiClient.storage.write(key: 'full_name', value: value.fullName);
    await ApiClient.storage.write(key: 'phone', value: value.phone);
    await ApiClient.storage.write(key: 'bio', value: value.bio);
    await ApiClient.storage.write(
      key: 'business_name',
      value: value.businessName,
    );
    await ApiClient.storage.write(key: 'image_url', value: value.imageUrl);
    await ApiClient.storage.write(key: 'avatar_url', value: value.imageUrl);

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('user_id', value.id);
    await prefs.setString('user_name', value.fullName);
    await prefs.setString('user_avatar', value.imageUrl);

    debugPrint('PROFILE SAVED TO SECURE STORAGE USER ID: ${value.id}');
    debugPrint('PROFILE SAVED TO SHARED PREF USER ID: ${value.id}');
  }

  Future<void> _loadProfileFromStorage() async {
    String id = await ApiClient.storage.read(key: 'user_id') ?? '';
    String fullName = await ApiClient.storage.read(key: 'full_name') ?? '';
    String phone = await ApiClient.storage.read(key: 'phone') ?? '';
    String bio = await ApiClient.storage.read(key: 'bio') ?? '';
    String businessName =
        await ApiClient.storage.read(key: 'business_name') ?? '';
    String imageUrl =
        await ApiClient.storage.read(key: 'image_url') ??
        await ApiClient.storage.read(key: 'avatar_url') ??
        '';

    final prefs = await SharedPreferences.getInstance();

    if (id.trim().isEmpty) {
      id = prefs.getString('user_id') ?? '';
    }

    if (fullName.trim().isEmpty) {
      fullName = prefs.getString('user_name') ?? '';
    }

    if (imageUrl.trim().isEmpty) {
      imageUrl = prefs.getString('user_avatar') ?? '';
    }

    profile = UserProfile(
      id: id,
      fullName: fullName,
      phone: phone,
      bio: bio,
      businessName: businessName,
      imageUrl: imageUrl,
    );

    if (profile.id.trim().isNotEmpty) {
      await _saveProfileToStorage(profile);
    }
  }

  String _cleanError(dynamic error) {
    final message = error.toString();

    if (message.contains('401')) {
      return 'Session expired. Please login again.';
    }

    if (message.contains('404')) {
      return 'Profile endpoint not found. Check your backend URL path.';
    }

    if (message.contains('SocketException') ||
        message.contains('connection errored') ||
        message.contains('XMLHttpRequest')) {
      return 'Network error. Please check your backend connection.';
    }

    return message;
  }
}