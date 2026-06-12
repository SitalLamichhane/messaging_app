// lib/auth_gate.dart

import 'package:flutter/material.dart';
import 'package:messaging_app/dashboard.dart';
import 'package:provider/provider.dart';

import 'package:messaging_app/features/auth/auth_provider.dart';
import 'package:messaging_app/login_page.dart';
import 'package:messaging_app/core/api_client.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;

  String _resolvedUserId = '';
  String _resolvedUserName = '';
  String _resolvedUserAvatar = '';

  bool _resolvedUserLoaded = false;
  bool _resolvingUser = false;

  int? _lastResolvedAuthUserId;

  @override
  void initState() {
    super.initState();
    _checkSavedLogin();
  }

  Future<void> _checkSavedLogin() async {
    final auth = context.read<AuthProvider>();

    await auth.checkLogin();

    if (!mounted) return;

    setState(() {
      _checking = false;
    });
  }

  String _firstNotEmpty(List<String?> values) {
    for (final value in values) {
      final clean = value?.trim() ?? '';

      if (clean.isNotEmpty && clean != 'null') {
        return clean;
      }
    }

    return '';
  }

  Future<Map<String, String>> _resolveCurrentUserData(
    Map<String, dynamic> user,
  ) async {
    String storageUserId = '';
    String storageFullName = '';
    String storageAvatar = '';

    try {
      storageUserId = _firstNotEmpty([
        await ApiClient.storage.read(key: 'user_id'),
        await ApiClient.storage.read(key: 'id'),
      ]);

      storageFullName = _firstNotEmpty([
        await ApiClient.storage.read(key: 'full_name'),
        await ApiClient.storage.read(key: 'name'),
        await ApiClient.storage.read(key: 'username'),
      ]);

      storageAvatar = _firstNotEmpty([
        await ApiClient.storage.read(key: 'avatar_url'),
        await ApiClient.storage.read(key: 'image_url'),
        await ApiClient.storage.read(key: 'profile_picture'),
      ]);
    } catch (e, st) {
      debugPrint('AUTH GATE READ USER STORAGE ERROR: $e');
      debugPrint(st.toString());
    }

    final currentUserId = _firstNotEmpty([
      user['id']?.toString(),
      user['user_id']?.toString(),
      storageUserId,
    ]);

    final currentUserName = _firstNotEmpty([
      user['full_name']?.toString(),
      user['name']?.toString(),
      user['username']?.toString(),
      user['display_name']?.toString(),
      storageFullName,
    ]);

    final currentUserAvatar = _firstNotEmpty([
      user['profile_picture']?.toString(),
      user['avatar_url']?.toString(),
      user['image_url']?.toString(),
      storageAvatar,
    ]);

    return {
      'id': currentUserId,
      'name': currentUserName,
      'avatar': currentUserAvatar,
    };
  }

  Future<void> _resolveUserOnly({
    required Map<String, dynamic> user,
  }) async {
    final rawUserId = _firstNotEmpty([
      user['id']?.toString(),
      user['user_id']?.toString(),
    ]);

    final authUserId = int.tryParse(rawUserId);

    // Main fix:
    // Do not resolve again and again for the same logged-in user.
    if (_resolvedUserLoaded && _lastResolvedAuthUserId == authUserId) return;
    if (_resolvingUser) return;

    _resolvingUser = true;

    try {
      final resolvedUser = await _resolveCurrentUserData(user);

      final currentUserId = resolvedUser['id'] ?? '';
      final currentUserName = resolvedUser['name'] ?? '';
      final currentUserAvatar = resolvedUser['avatar'] ?? '';

      debugPrint('');
      debugPrint('################################################');
      debugPrint('### AUTH GATE RESOLVE USER ONLY');
      debugPrint('################################################');
      debugPrint('auth.user: $user');
      debugPrint('currentUserId: $currentUserId');
      debugPrint('currentUserName: $currentUserName');
      debugPrint('currentUserAvatar: $currentUserAvatar');
      debugPrint('################################################');

      if (!mounted) return;

      setState(() {
        _resolvedUserId = currentUserId;
        _resolvedUserName = currentUserName;
        _resolvedUserAvatar = currentUserAvatar;
        _resolvedUserLoaded = true;
        _lastResolvedAuthUserId = authUserId;
      });
    } catch (e, st) {
      debugPrint('AUTH GATE RESOLVE USER ERROR: $e');
      debugPrint(st.toString());

      if (!mounted) return;

      setState(() {
        _resolvedUserLoaded = true;
        _lastResolvedAuthUserId = authUserId;
      });
    } finally {
      _resolvingUser = false;
    }
  }

  void _clearResolvedUser() {
    _resolvedUserId = '';
    _resolvedUserName = '';
    _resolvedUserAvatar = '';
    _resolvedUserLoaded = false;
    _resolvingUser = false;
    _lastResolvedAuthUserId = null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (_checking || auth.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!auth.isLoggedIn) {
      _clearResolvedUser();
      return const WelcomeScreen();
    }

    final user = Map<String, dynamic>.from(auth.user ?? {});

    final fallbackUserId = _firstNotEmpty([
      user['id']?.toString(),
      user['user_id']?.toString(),
    ]);

    final fallbackUserName = _firstNotEmpty([
      user['full_name']?.toString(),
      user['name']?.toString(),
      user['username']?.toString(),
      user['display_name']?.toString(),
    ]);

    final fallbackUserAvatar = _firstNotEmpty([
      user['profile_picture']?.toString(),
      user['avatar_url']?.toString(),
      user['image_url']?.toString(),
    ]);

    final authUserId = int.tryParse(fallbackUserId);

    // Main fix:
    // addPostFrameCallback should only run when user is not resolved yet
    // or when a different user logs in.
    if (!_resolvedUserLoaded && !_resolvingUser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _resolveUserOnly(user: user);
      });
    } else if (_lastResolvedAuthUserId != null &&
        authUserId != null &&
        _lastResolvedAuthUserId != authUserId &&
        !_resolvingUser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        setState(() {
          _resolvedUserId = '';
          _resolvedUserName = '';
          _resolvedUserAvatar = '';
          _resolvedUserLoaded = false;
          _lastResolvedAuthUserId = null;
        });

        _resolveUserOnly(user: user);
      });
    }

    final currentUserId = _firstNotEmpty([
      _resolvedUserId,
      fallbackUserId,
    ]);

    final currentUserName = _firstNotEmpty([
      _resolvedUserName,
      fallbackUserName,
    ]);

    final currentUserAvatar = _firstNotEmpty([
      _resolvedUserAvatar,
      fallbackUserAvatar,
    ]);

    if (!_resolvedUserLoaded && currentUserId.isEmpty) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return ChatListScreen(
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      currentUserAvatar: currentUserAvatar,
    );
  }
}