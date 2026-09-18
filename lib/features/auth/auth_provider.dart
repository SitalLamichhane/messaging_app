// lib/features/auth/auth_provider.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/core/call/call_notification.dart';
import 'package:hiddenly/features/auth/auth_api.dart';

class AuthProvider extends ChangeNotifier {
  bool isLoading = false;
  bool isLoggedIn = false;

  String? accessToken;
  String? refreshToken;
  String? signupToken;

  Map<String, dynamic>? user;

  // ============================================================
  // HELPERS
  // ============================================================

  String _clean(dynamic value) {
    if (value == null) return '';

    final text = value.toString().trim();

    if (text.isEmpty || text.toLowerCase() == 'null') {
      return '';
    }

    return text;
  }

  String _firstNotEmpty(List<dynamic> values) {
    for (final value in values) {
      final cleaned = _clean(value);

      if (cleaned.isNotEmpty) {
        return cleaned;
      }
    }

    return '';
  }

  // ============================================================
  // RESTORE LOGIN ON APP START
  // ============================================================

  Future<void> checkLogin() async {
    try {
      debugPrint('');
      debugPrint('========================================');
      debugPrint('AUTH: CHECK LOGIN START');
      debugPrint('========================================');

      accessToken = await ApiClient.storage.read(key: 'access');
      refreshToken = await ApiClient.storage.read(key: 'refresh');

      final cleanAccess = _clean(accessToken);

      isLoggedIn = cleanAccess.isNotEmpty;

      // --------------------------------------------------------
      // No login stored
      // --------------------------------------------------------

      if (!isLoggedIn) {
        accessToken = null;
        refreshToken = null;
        user = null;

        debugPrint('AUTH: no saved login');

        notifyListeners();
        return;
      }

      // --------------------------------------------------------
      // Restore user identity from secure storage
      //
      // This is extremely important for:
      // - global call websocket
      // - killed-state CallKit answer
      // - background incoming calls
      // --------------------------------------------------------

      final userId = _firstNotEmpty([
        await ApiClient.storage.read(key: 'user_id'),
        await ApiClient.storage.read(key: 'id'),
      ]);

      final fullName = _firstNotEmpty([
        await ApiClient.storage.read(key: 'full_name'),
        await ApiClient.storage.read(key: 'name'),
        await ApiClient.storage.read(key: 'username'),
      ]);

      final avatar = _firstNotEmpty([
        await ApiClient.storage.read(key: 'avatar_url'),
        await ApiClient.storage.read(key: 'image_url'),
        await ApiClient.storage.read(key: 'profile_picture'),
      ]);

      if (userId.isNotEmpty) {
        user = <String, dynamic>{
          'id': userId,
          'user_id': userId,
          'full_name': fullName,
          'name': fullName,
          'avatar_url': avatar,
          'profile_picture': avatar,
          'image_url': avatar,
        };

        debugPrint('AUTH: restored user from storage');
        debugPrint('AUTH: userId=$userId');
        debugPrint('AUTH: fullName=$fullName');
      } else {
        /*
          The access token exists but older app versions may never have
          persisted user_id.

          Keep the login authenticated, but AuthGate will not be able to
          start the global call websocket until user identity is known.

          New logins using this updated AuthProvider will always persist
          user_id, so this mainly affects users upgrading from the old app.
        */
        user = null;

        debugPrint(
          'AUTH WARNING: access token exists but saved user_id is missing',
        );
      }

      notifyListeners();

      // --------------------------------------------------------
      // IMPORTANT
      //
      // App may have been killed/restarted.
      // Ensure this device's FCM token is registered for the
      // authenticated user.
      // --------------------------------------------------------

      await _syncFcmTokenAfterAuthentication();

      debugPrint('AUTH: CHECK LOGIN COMPLETE');
    } catch (e, st) {
      debugPrint('AUTH CHECK LOGIN ERROR: $e');
      debugPrint(st.toString());

      /*
        Do not automatically logout here because a temporary storage or
        FCM error should not destroy the user's session.
      */

      notifyListeners();
    }
  }

  // ============================================================
  // SEND OTP
  // ============================================================

  Future<bool> sendOtp(String phone) async {
    isLoading = true;
    notifyListeners();

    try {
      await AuthApi.sendOtp(phone);

      return true;
    } catch (e) {
      debugPrint('SEND OTP ERROR: $e');

      throw Exception(
        e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ============================================================
  // VERIFY OTP
  // ============================================================

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

      final rawData = response.data;

      if (rawData is! Map) {
        throw Exception('Invalid login response');
      }

      final data = Map<String, dynamic>.from(rawData);

      final type = _clean(data['type']).toLowerCase();

      // --------------------------------------------------------
      // Existing user login
      // --------------------------------------------------------

      if (type == 'login') {
        await _saveLoginData(data);

        return 'login';
      }

      // --------------------------------------------------------
      // New user signup
      // --------------------------------------------------------

      if (type == 'signup') {
        signupToken = _clean(data['signup_token']);

        if (signupToken == null || signupToken!.isEmpty) {
          throw Exception('Signup token missing');
        }

        await ApiClient.storage.write(
          key: 'signup_token',
          value: signupToken!,
        );

        return 'signup';
      }

      debugPrint('VERIFY OTP UNKNOWN RESPONSE TYPE: $type');

      return null;
    } catch (e) {
      debugPrint('VERIFY OTP ERROR: $e');

      throw Exception(
        e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ============================================================
  // COMPLETE SIGNUP
  // ============================================================

  Future<bool> completeSignup({
    required String fullName,
    required String bio,
  }) async {
    String? token = signupToken;

    token ??= await ApiClient.storage.read(
      key: 'signup_token',
    );

    final cleanToken = _clean(token);

    if (cleanToken.isEmpty) {
      throw Exception('Signup token missing');
    }

    isLoading = true;
    notifyListeners();

    try {
      final response = await AuthApi.completeSignup(
        signupToken: cleanToken,
        fullName: fullName,
        bio: bio,
      );

      final rawData = response.data;

      if (rawData is! Map) {
        throw Exception('Invalid signup response');
      }

      final data = Map<String, dynamic>.from(rawData);

      await _saveLoginData(data);

      await ApiClient.storage.delete(
        key: 'signup_token',
      );

      signupToken = null;

      return true;
    } catch (e) {
      debugPrint('COMPLETE SIGNUP ERROR: $e');

      throw Exception(
        e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ============================================================
  // SAVE LOGIN
  //
  // THIS IS THE IMPORTANT FIX.
  //
  // Previously:
  //
  // Login
  //   -> access token saved
  //   -> FCM token was NOT re-registered
  //   -> user identity was NOT persisted
  //
  // Now:
  //
  // Login
  //   -> tokens saved
  //   -> user identity saved
  //   -> logged in
  //   -> FCM token registered immediately
  // ============================================================

  Future<void> _saveLoginData(
    Map<String, dynamic> data,
  ) async {
    debugPrint('');
    debugPrint('========================================');
    debugPrint('AUTH: SAVE LOGIN DATA');
    debugPrint('========================================');

    // --------------------------------------------------------
    // Tokens
    // --------------------------------------------------------

    final rawTokens = data['tokens'];

    if (rawTokens is! Map) {
      throw Exception('Login tokens missing');
    }

    final tokens = Map<String, dynamic>.from(rawTokens);

    final newAccessToken = _clean(tokens['access']);
    final newRefreshToken = _clean(tokens['refresh']);

    if (newAccessToken.isEmpty) {
      throw Exception('Access token missing');
    }

    accessToken = newAccessToken;

    refreshToken = newRefreshToken.isEmpty
        ? null
        : newRefreshToken;

    await ApiClient.storage.write(
      key: 'access',
      value: newAccessToken,
    );

    if (newRefreshToken.isNotEmpty) {
      await ApiClient.storage.write(
        key: 'refresh',
        value: newRefreshToken,
      );
    } else {
      await ApiClient.storage.delete(
        key: 'refresh',
      );
    }

    debugPrint('AUTH: access token saved');
    debugPrint(
      'AUTH: refresh token exists=${newRefreshToken.isNotEmpty}',
    );

    // --------------------------------------------------------
    // User
    // --------------------------------------------------------

    final rawUser = data['user'];

    if (rawUser is Map) {
      user = Map<String, dynamic>.from(rawUser);

      await _persistUserIdentity(user!);
    } else {
      /*
        This should normally never happen because login/signup should
        return user information.

        Do not create a fake user ID because call routing requires the
        real authenticated user ID.
      */

      user = null;

      debugPrint(
        'AUTH WARNING: login response does not contain user object',
      );
    }

    // --------------------------------------------------------
    // Mark logged in only AFTER tokens are safely stored.
    // --------------------------------------------------------

    isLoggedIn = true;

    notifyListeners();

    // --------------------------------------------------------
    // CRITICAL FIX
    //
    // NotificationService.init() may have run BEFORE login.
    //
    // At that point:
    //
    // _sendTokenToBackend()
    //    -> access token missing
    //    -> return
    //
    // Therefore explicitly sync FCM again AFTER authentication.
    // --------------------------------------------------------

    await _syncFcmTokenAfterAuthentication();

    debugPrint('AUTH: LOGIN DATA SAVED SUCCESSFULLY');
    debugPrint('========================================');
  }

  // ============================================================
  // SAVE USER IDENTITY
  // ============================================================

  Future<void> _persistUserIdentity(
    Map<String, dynamic> rawUser,
  ) async {
    final userId = _firstNotEmpty([
      rawUser['id'],
      rawUser['user_id'],
    ]);

    final fullName = _firstNotEmpty([
      rawUser['full_name'],
      rawUser['name'],
      rawUser['username'],
      rawUser['display_name'],
    ]);

    final avatar = _firstNotEmpty([
      rawUser['profile_picture'],
      rawUser['avatar_url'],
      rawUser['image_url'],
      rawUser['avatar'],
    ]);

    // --------------------------------------------------------
    // User ID
    // --------------------------------------------------------

    if (userId.isNotEmpty) {
      /*
        Save both keys because different existing parts of your project
        currently check both user_id and id.
      */

      await ApiClient.storage.write(
        key: 'user_id',
        value: userId,
      );

      await ApiClient.storage.write(
        key: 'id',
        value: userId,
      );

      // Normalize in-memory user too.
      user?['id'] = userId;
      user?['user_id'] = userId;

      debugPrint('AUTH: user_id saved=$userId');
    } else {
      debugPrint(
        'AUTH WARNING: login response user has no id/user_id',
      );
    }

    // --------------------------------------------------------
    // Name
    // --------------------------------------------------------

    if (fullName.isNotEmpty) {
      await ApiClient.storage.write(
        key: 'full_name',
        value: fullName,
      );

      await ApiClient.storage.write(
        key: 'name',
        value: fullName,
      );

      user?['full_name'] = fullName;

      debugPrint('AUTH: full_name saved=$fullName');
    }

    // --------------------------------------------------------
    // Avatar
    // --------------------------------------------------------

    if (avatar.isNotEmpty) {
      await ApiClient.storage.write(
        key: 'avatar_url',
        value: avatar,
      );

      await ApiClient.storage.write(
        key: 'image_url',
        value: avatar,
      );

      user?['avatar_url'] = avatar;

      debugPrint('AUTH: avatar saved');
    }
  }

  // ============================================================
  // FCM SYNC
  // ============================================================

  Future<void> _syncFcmTokenAfterAuthentication() async {
    try {
      final access = _clean(
        await ApiClient.storage.read(key: 'access'),
      );

      if (access.isEmpty) {
        debugPrint(
          'AUTH FCM SYNC SKIPPED: access token missing',
        );

        return;
      }

      debugPrint(
        'AUTH: syncing FCM token after authentication...',
      );

      await NotificationService.saveCurrentToken();

      debugPrint(
        'AUTH: FCM token sync completed',
      );
    } catch (e, st) {
      /*
        Important:
        FCM failure must NOT make login fail.

        User should still be able to enter the app.
        FCM can retry on the next app start/token refresh.
      */

      debugPrint(
        'AUTH FCM SYNC ERROR: $e',
      );

      debugPrint(st.toString());
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    debugPrint('');
    debugPrint('========================================');
    debugPrint('AUTH: LOGOUT');
    debugPrint('========================================');

    try {
      // Close any native incoming-call UI before clearing identity.
      await NotificationService.endAllNativeCalls();
    } catch (e) {
      debugPrint(
        'AUTH LOGOUT END CALLKIT ERROR: $e',
      );
    }

    // --------------------------------------------------------
    // Secure storage
    // --------------------------------------------------------

    await ApiClient.storage.deleteAll();

    // --------------------------------------------------------
    // SharedPreferences
    //
    // GlobalCallHandler stores user_id/user_name/user_avatar here too.
    // --------------------------------------------------------

    final prefs = await SharedPreferences.getInstance();

    await prefs.clear();

    // --------------------------------------------------------
    // Memory
    // --------------------------------------------------------

    accessToken = null;
    refreshToken = null;
    signupToken = null;
    user = null;

    isLoggedIn = false;
    isLoading = false;

    notifyListeners();

    debugPrint('AUTH: logout complete');
  }
}