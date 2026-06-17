// lib/auth_gate.dart

import 'package:flutter/material.dart';
import 'package:messaging_app/dashboard.dart';
import 'package:provider/provider.dart';

import 'package:messaging_app/features/auth/auth_provider.dart';
import 'package:messaging_app/login_page.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/core/call/global_call_handler.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  bool _checking = true;

  String _resolvedUserId = '';
  String _resolvedUserName = '';
  String _resolvedUserAvatar = '';

  bool _resolvedUserLoaded = false;
  bool _resolvingUser = false;

  int? _lastResolvedAuthUserId;

  bool _globalCallSocketStarting = false;
  bool _globalCallSocketStarted = false;
  String? _globalCallSocketUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSavedLogin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('AUTH GATE APP RESUMED: rechecking global call socket');
      _globalCallSocketStarted = false;
      _globalCallSocketUserId = null;
      if (mounted) setState(() {});
    }
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

  Future<void> _startGlobalCallSocketIfNeeded({
    required String currentUserId,
    required String currentUserName,
    required String currentUserAvatar,
  }) async {
    if (currentUserId.trim().isEmpty) {
      debugPrint('AUTH GATE GLOBAL CALL ERROR: currentUserId empty');
      return;
    }

    if (_globalCallSocketStarting) {
      debugPrint('AUTH GATE GLOBAL CALL: already starting');
      return;
    }

    if (_globalCallSocketStarted && _globalCallSocketUserId == currentUserId) {
      debugPrint('AUTH GATE GLOBAL CALL: already started for $currentUserId');
      return;
    }

    _globalCallSocketStarting = true;

    try {
      final accessToken = _firstNotEmpty([
        await ApiClient.storage.read(key: 'access'),
        await ApiClient.storage.read(key: 'access_token'),
        await ApiClient.storage.read(key: 'token'),
      ]);

      if (accessToken.isEmpty) {
        debugPrint('AUTH GATE GLOBAL CALL ERROR: access token empty');
        return;
      }

      debugPrint('');
      debugPrint('################################################');
      debugPrint('### AUTH GATE STARTING GLOBAL CALL SOCKET');
      debugPrint('################################################');
      debugPrint('currentUserId: $currentUserId');
      debugPrint('currentUserName: $currentUserName');
      debugPrint('token exists: ${accessToken.isNotEmpty}');
      debugPrint('################################################');

      await GlobalCallHandler.instance.connectGlobalIncomingCallSocket(
        accessToken: accessToken,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        currentUserAvatar: currentUserAvatar,
        allowConnect: true,
      );

      _globalCallSocketStarted = true;
      _globalCallSocketUserId = currentUserId;

      debugPrint('AUTH GATE GLOBAL CALL SOCKET READY EVERYWHERE');
    } catch (e, st) {
      debugPrint('AUTH GATE GLOBAL CALL SOCKET ERROR: $e');
      debugPrint(st.toString());
    } finally {
      _globalCallSocketStarting = false;
    }
  }

  void _clearResolvedUser() {
    _resolvedUserId = '';
    _resolvedUserName = '';
    _resolvedUserAvatar = '';

    _resolvedUserLoaded = false;
    _resolvingUser = false;
    _lastResolvedAuthUserId = null;

    _globalCallSocketStarting = false;
    _globalCallSocketStarted = false;
    _globalCallSocketUserId = null;

    GlobalCallHandler.instance.dispose();
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

          _globalCallSocketStarted = false;
          _globalCallSocketUserId = null;
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

    if (currentUserId.isNotEmpty &&
        !_globalCallSocketStarting &&
        (!_globalCallSocketStarted ||
            _globalCallSocketUserId != currentUserId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _startGlobalCallSocketIfNeeded(
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          currentUserAvatar: currentUserAvatar,
        );
      });
    }

    return ChatListScreen(
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      currentUserAvatar: currentUserAvatar,
    );
  }
}