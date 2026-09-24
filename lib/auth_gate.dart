// lib/auth_gate.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddenly/dashboard.dart';
import 'package:provider/provider.dart';

import 'package:hiddenly/features/auth/auth_provider.dart';
import 'package:hiddenly/login_page.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/core/call/global_call_handler.dart';
import 'package:hiddenly/core/call/global_call_socket_service.dart';
import 'package:hiddenly/core/call/call_notification.dart';

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
  Timer? _globalSocketHealthTimer;
  bool _loggedOutCleanupDone = false;

  String? _lastFcmSyncedUserId;
  DateTime? _lastFcmSyncAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _globalSocketHealthTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _recoverGlobalSocketIfNeeded(),
    );

    _checkSavedLogin();
  }

  @override
  void dispose() {
    _globalSocketHealthTimer?.cancel();
    _globalSocketHealthTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('AUTH GATE APP RESUMED: checking global call socket');
      unawaited(_recoverGlobalSocketIfNeeded(force: true));
    }
  }

  Future<void> _recoverGlobalSocketIfNeeded({bool force = false}) async {
    if (!mounted) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;

    final socket = GlobalCallSocketService.instance;

    if (!force &&
        ((socket.isConnected && socket.isHealthy) || socket.isConnecting)) {
      return;
    }

    if (_globalCallSocketStarting) {
      return;
    }

    _loggedOutCleanupDone = false;

    final user = Map<String, dynamic>.from(auth.user ?? {});

    final currentUserId = _firstNotEmpty([
      _resolvedUserId,
      user['id']?.toString(),
      user['user_id']?.toString(),
      await ApiClient.storage.read(key: 'user_id'),
      await ApiClient.storage.read(key: 'id'),
    ]);

    final currentUserName = _firstNotEmpty([
      _resolvedUserName,
      user['full_name']?.toString(),
      user['name']?.toString(),
      user['username']?.toString(),
      user['display_name']?.toString(),
      await ApiClient.storage.read(key: 'full_name'),
      await ApiClient.storage.read(key: 'name'),
    ]);

    final currentUserAvatar = _firstNotEmpty([
      _resolvedUserAvatar,
      user['profile_picture']?.toString(),
      user['avatar_url']?.toString(),
      user['image_url']?.toString(),
      await ApiClient.storage.read(key: 'avatar_url'),
      await ApiClient.storage.read(key: 'image_url'),
    ]);

    if (currentUserId.isEmpty) {
      debugPrint('AUTH GATE GLOBAL HEALTH: user id unavailable');
      return;
    }

    debugPrint(
      'AUTH GATE GLOBAL HEALTH: connected=${socket.isConnected} '
      'connecting=${socket.isConnecting} force=$force',
    );

    await _startGlobalCallSocketIfNeeded(
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      currentUserAvatar: currentUserAvatar,
      force: true,
    );
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

  Future<void> _syncFcmTokenAfterLogin(String currentUserId) async {
    final cleanUserId = currentUserId.trim();
    if (cleanUserId.isEmpty) return;

    final now = DateTime.now();
    final recentlySynced = _lastFcmSyncedUserId == cleanUserId &&
        _lastFcmSyncAt != null &&
        now.difference(_lastFcmSyncAt!).inMinutes < 2;

    if (recentlySynced) return;

    try {
      debugPrint('AUTH GATE: syncing FCM token after login user=$cleanUserId');
      await NotificationService.saveCurrentToken();
      _lastFcmSyncedUserId = cleanUserId;
      _lastFcmSyncAt = DateTime.now();
    } catch (e, st) {
      debugPrint('AUTH GATE FCM TOKEN SYNC ERROR: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> _startGlobalCallSocketIfNeeded({
    required String currentUserId,
    required String currentUserName,
    required String currentUserAvatar,
    bool force = false,
  }) async {
    if (currentUserId.trim().isEmpty) {
      debugPrint('AUTH GATE GLOBAL CALL ERROR: currentUserId empty');
      return;
    }

    await _syncFcmTokenAfterLogin(currentUserId);

    if (_globalCallSocketStarting) {
      debugPrint('AUTH GATE GLOBAL CALL: already starting');
      return;
    }

    final socket = GlobalCallSocketService.instance;

    if (!force &&
    _globalCallSocketStarted &&
    _globalCallSocketUserId == currentUserId &&
    socket.isConnected &&
    socket.isHealthy) {
   debugPrint(
    'AUTH GATE GLOBAL CALL: already connected and healthy for $currentUserId',
  );
  return;
}

    if (socket.isConnected &&
        socket.isHealthy &&
        _globalCallSocketUserId == currentUserId) {
     _globalCallSocketStarted = true;

  debugPrint(
    'AUTH GATE GLOBAL CALL: socket already connected and healthy',
  );

   return;
 }

    _globalCallSocketStarting = true;

    try {
      final accessToken = _firstNotEmpty([
        await ApiClient.storage.read(key: 'access'),
        await ApiClient.storage.read(key: 'access_token'),
        await ApiClient.storage.read(key: 'token'),
      ]);

      var usableToken = accessToken;

      if (usableToken.isEmpty) {
        usableToken = (await ApiClient.refreshAccessToken())?.trim() ?? '';
      }

      if (usableToken.isEmpty) {
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
        accessToken: usableToken,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        currentUserAvatar: currentUserAvatar,
        allowConnect: true,
      );

      final connected = GlobalCallSocketService.instance.isConnected;

      _globalCallSocketStarted = connected;
      _globalCallSocketUserId = connected ? currentUserId : null;

      debugPrint(
        'AUTH GATE GLOBAL CALL SOCKET READY: connected=$connected',
      );
    } catch (e, st) {
      debugPrint('AUTH GATE GLOBAL CALL SOCKET ERROR: $e');
      debugPrint(st.toString());
    } finally {
      _globalCallSocketStarting = false;
    }
  }

  void _clearResolvedUser() {
    if (_loggedOutCleanupDone &&
        _resolvedUserId.isEmpty &&
        !_globalCallSocketStarted &&
        _globalCallSocketUserId == null) {
      return;
    }

    _loggedOutCleanupDone = true;

    _resolvedUserId = '';
    _resolvedUserName = '';
    _resolvedUserAvatar = '';

    _resolvedUserLoaded = false;
    _resolvingUser = false;
    _lastResolvedAuthUserId = null;

    _globalCallSocketStarting = false;
    _globalCallSocketStarted = false;
    _globalCallSocketUserId = null;
    _lastFcmSyncedUserId = null;
    _lastFcmSyncAt = null;

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
      return const WelcomeScreen();
    } 

    _loggedOutCleanupDone = false;

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

    final globalSocketHealthy =
       GlobalCallSocketService.instance.isConnected &&
       GlobalCallSocketService.instance.isHealthy;

    if (currentUserId.isNotEmpty &&
        !_globalCallSocketStarting &&
        (!globalSocketHealthy ||
            !_globalCallSocketStarted ||
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