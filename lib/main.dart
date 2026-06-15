// lib/main.dart

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'package:flutter_webrtc/flutter_webrtc.dart' hide MessageType;
import 'package:provider/provider.dart' as provider;

import 'package:messaging_app/auth_gate.dart';
import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/features/auth/auth_provider.dart';
import 'package:messaging_app/theme_controller.dart';
import 'package:messaging_app/core/chat/chat_provider.dart';
import 'package:messaging_app/core/profile/profile_provider.dart';
import 'package:messaging_app/core/block/block_provider.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/core/call/global_call_handler.dart';
import 'package:messaging_app/core/call/call_notification.dart';
import 'package:messaging_app/core/call/mini_call_overlay.dart';
import 'package:messaging_app/core/call/call_lifecycle_watcher.dart';
import 'package:messaging_app/core/call/call_provider.dart';
import 'package:messaging_app/core/call/call_overlay_controller.dart';
import 'package:messaging_app/core/call/call_state.dart';

bool _handlingColdStartCallKit = false;
StreamSubscription<CallEvent?>? _callKitSubscription;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('');
  debugPrint('################################################');
  debugPrint('### APP MAIN STARTED');
  debugPrint('################################################');

  await Firebase.initializeApp();

  debugPrint('[MAIN] Firebase initialized');

  /*
    Must be registered before runApp.
    This handles FCM data messages when app is background/killed.
  */
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  debugPrint('[MAIN] FirebaseMessaging background handler registered');

  /*
    Register CallKit listener early.
    Navigation will happen after MaterialApp/navigatorKey is ready.
  */
  _setupCallKitDebugListener();

  runApp(
    riverpod.ProviderScope(
      child: provider.MultiProvider(
        providers: [
          provider.ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider()..checkLogin(),
          ),
          provider.ChangeNotifierProvider<ChatProvider>(
            create: (_) => ChatProvider(),
          ),
          provider.ChangeNotifierProvider<ProfileProvider>(
            create: (_) => ProfileProvider(),
          ),
          provider.ChangeNotifierProvider<BlockProvider>(
            create: (_) => BlockProvider(),
          ),
        ],
        child: const MyApp(),
      ),
    ),
  );

  debugPrint('[MAIN] runApp called');

  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('');
    debugPrint('################################################');
    debugPrint('### APP FIRST FRAME READY');
    debugPrint('################################################');

    unawaited(_initAfterFirstFrame());
  });
}

Future<void> _initAfterFirstFrame() async {
  try {
    debugPrint('[MAIN] _initAfterFirstFrame started');

    /*
      Initialize notification service after navigator exists.
      This sets up FCM/local notification/CallKit logic.
    */
    debugPrint('[MAIN] Calling NotificationService.init()...');
    await NotificationService.init();
    debugPrint('[MAIN] NotificationService.init() completed');

    /*
      Keep this enabled.
      In killed state, sometimes CallKit accept event is not received by
      onEvent listener, so we check active calls after Flutter opens.
    */
    await _checkKilledStateCallKit();

    debugPrint('[MAIN] _initAfterFirstFrame completed');
  } catch (e, st) {
    debugPrint('!!!!!!!!!! MAIN INIT AFTER FIRST FRAME ERROR !!!!!!!!!!');
    debugPrint('error: $e');
    debugPrint('stack: $st');
    debugPrint('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
  }
}

void _setupCallKitDebugListener() {
  debugPrint('[MAIN] Setting up CallKit listener...');

  _callKitSubscription?.cancel();

  _callKitSubscription = FlutterCallkitIncoming.onEvent.listen(
    (CallEvent? event) async {
      debugPrint('');
      debugPrint('################################################');
      debugPrint('### CALLKIT EVENT RECEIVED IN MAIN');
      debugPrint('################################################');
      debugPrint('event object: $event');
      debugPrint('event name: ${event?.event}');
      debugPrint('event body: ${event?.body}');
      debugPrint('################################################');

      if (event == null) {
        debugPrint('[MAIN CALLKIT] event is null');
        return;
      }

      final body = _safeMap(event.body);

      if (event.event == Event.actionCallAccept) {
        debugPrint('[MAIN CALLKIT] ANSWER clicked');
        await _handleCallKitAcceptFromMain(
          body,
          source: 'onEvent_accept',
        );
        return;
      }

      if (event.event == Event.actionCallDecline) {
        debugPrint('[MAIN CALLKIT] DECLINE clicked');
        await _handleCallKitDeclineFromMain(body);
        return;
      }

      if (event.event == Event.actionCallEnded) {
        debugPrint('[MAIN CALLKIT] ENDED clicked');
        await _handleCallKitEndFromMain(body);
        return;
      }

      debugPrint('[MAIN CALLKIT] Event ignored: ${event.event}');
    },
    onError: (Object error, StackTrace stackTrace) {
      debugPrint('!!!!!!!!!! CALLKIT LISTENER ERROR !!!!!!!!!!');
      debugPrint('error: $error');
      debugPrint('stack: $stackTrace');
      debugPrint('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
    },
  );

  debugPrint('[MAIN] CallKit listener registered');
}

Future<void> _checkKilledStateCallKit() async {
  try {
    debugPrint('');
    debugPrint('################################################');
    debugPrint('### CLEARING STALE CALLKIT ACTIVE CALLS');
    debugPrint('################################################');

    final activeCalls = await FlutterCallkitIncoming.activeCalls();

    debugPrint(
      '[MAIN CALLKIT] activeCalls runtimeType: ${activeCalls.runtimeType}',
    );
    debugPrint('[MAIN CALLKIT] activeCalls: $activeCalls');

    if (activeCalls is List && activeCalls.isNotEmpty) {
      debugPrint(
        '[MAIN CALLKIT] OLD STALE CALL FOUND. CLEARING ALL SO APP DOES NOT AUTO OPEN CALLSCREEN.',
      );

      try {
        await FlutterCallkitIncoming.endAllCalls();
        debugPrint('[MAIN CALLKIT] endAllCalls success');
      } catch (e) {
        debugPrint('[MAIN CALLKIT] endAllCalls error: $e');
      }
    } else {
      debugPrint('[MAIN CALLKIT] No stale active calls found');
    }

    debugPrint('################################################');
  } catch (e, st) {
    debugPrint('!!!!!!!!!! CLEAR STALE CALLKIT ERROR !!!!!!!!!!');
    debugPrint('error: $e');
    debugPrint('stack: $st');
    debugPrint('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
  }
}

Future<void> _handleCallKitAcceptFromMain(
  Map<String, dynamic> rawData, {
  required String source,
}) async {
  if (_handlingColdStartCallKit) {
    debugPrint('[MAIN CALLKIT] accept ignored: already handling. source=$source');
    return;
  }

  _handlingColdStartCallKit = true;

  try {
    debugPrint('');
    debugPrint('################################################');
    debugPrint('### HANDLE CALLKIT ANSWER FROM MAIN');
    debugPrint('################################################');
    debugPrint('source: $source');
    debugPrint('rawData: $rawData');

    final data = _extractCallData(rawData);

    debugPrint('[MAIN CALLKIT] extracted data: $data');

    final callId = _readString(
      data,
      ['call_id', 'callId', 'id', 'uuid'],
    ).ifEmpty(
      _readString(rawData, ['id', 'uuid']),
    );

    final conversationId = _readString(
      data,
      ['conversation_id', 'conversationId'],
    );

    final callerId = _readString(
      data,
      ['caller_id', 'callerId', 'from_user', 'from'],
    );

    final callerName = _readString(
      data,
      ['caller_name', 'callerName', 'nameCaller', 'name'],
    ).ifEmpty(
      _readString(rawData, ['nameCaller', 'name']).ifEmpty('Unknown'),
    );

    final callerAvatar = _readString(
      data,
      ['caller_avatar', 'callerAvatar', 'avatar'],
    );

    final isVideoCall =
        _readBool(data, ['is_video_call', 'isVideoCall', 'video']) ||
            _readBool(rawData, ['is_video_call', 'isVideoCall', 'video']) ||
            rawData['type'] == 1 ||
            rawData['type']?.toString() == '1' ||
            data['type'] == 1 ||
            data['type']?.toString() == '1';

    debugPrint('rawData type: ${rawData['type']}');
    debugPrint('data type: ${data['type']}');
    debugPrint('data is_video_call: ${data['is_video_call']}');
    debugPrint('data isVideoCall: ${data['isVideoCall']}');
    debugPrint('resolved isVideoCall: $isVideoCall');

    debugPrint('========== MAIN CALLKIT ANSWER RESOLVED ==========');
    debugPrint('callId: $callId');
    debugPrint('conversationId: $conversationId');
    debugPrint('callerId: $callerId');
    debugPrint('callerName: $callerName');
    debugPrint('callerAvatar: $callerAvatar');
    debugPrint('isVideoCall: $isVideoCall');
    debugPrint('=================================================');

    if (conversationId.isEmpty) {
      debugPrint(
        '[MAIN CALLKIT] ERROR: conversationId empty. Socket cannot connect.',
      );
      return;
    }

    if (callerId.isEmpty) {
      debugPrint('[MAIN CALLKIT] ERROR: callerId empty. Cannot target caller.');
      return;
    }

    debugPrint('[MAIN CALLKIT] Reading current user from storage...');

    final currentUserId =
        (await ApiClient.storage.read(key: 'user_id'))?.trim() ?? '';

    final currentUserName =
        (await ApiClient.storage.read(key: 'full_name'))?.trim() ?? '';

    final currentUserAvatar =
        (await ApiClient.storage.read(key: 'avatar_url'))?.trim() ??
            (await ApiClient.storage.read(key: 'image_url'))?.trim() ??
            '';

    debugPrint('========== MAIN CALLKIT CURRENT USER ==========');
    debugPrint('currentUserId: $currentUserId');
    debugPrint('currentUserName: $currentUserName');
    debugPrint('currentUserAvatar: $currentUserAvatar');
    debugPrint('==============================================');

    if (currentUserId.isEmpty) {
      debugPrint(
        '[MAIN CALLKIT] ERROR: currentUserId empty. User may not be loaded/logged in.',
      );
      return;
    }

    await _waitForNavigatorReady();

    final nav = GlobalCallHandler.navigatorKey.currentState;

    debugPrint('[MAIN CALLKIT] navigator ready: ${nav != null}');

    if (nav == null) {
      debugPrint(
        '[MAIN CALLKIT] ERROR: navigator is null. Cannot open direct call screen.',
      );
      return;
    }

    /*
      IMPORTANT:
      Do NOT call FlutterCallkitIncoming.endCall(callId) here.
      ANSWER means user accepted the call. endCall() can trigger ended/cancel flow
      and prevent Flutter call screen from opening/connecting.
    */
    debugPrint('');
    debugPrint('################################################');
    debugPrint('### CALLKIT ANSWER CLICKED: OPEN DIRECT CALL SCREEN');
    debugPrint('################################################');

    await GlobalCallHandler.instance.openIncomingCallFromCallKit(
      callId: callId,
      conversationId: conversationId,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      isVideoCall: isVideoCall,
    );

    debugPrint('[MAIN CALLKIT] Direct call screen opened after ANSWER');
  } catch (e, st) {
    debugPrint('!!!!!!!!!! HANDLE CALLKIT ANSWER FROM MAIN ERROR !!!!!!!!!!');
    debugPrint('error: $e');
    debugPrint('stack: $st');
    debugPrint('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
  } finally {
    Future.delayed(const Duration(seconds: 2), () {
      _handlingColdStartCallKit = false;
      debugPrint('[MAIN CALLKIT] accept handling lock released');
    });
  }
}

Future<void> _handleCallKitDeclineFromMain(Map<String, dynamic> rawData) async {
  try {
    debugPrint('');
    debugPrint('################################################');
    debugPrint('### HANDLE CALLKIT DECLINE FROM MAIN');
    debugPrint('################################################');
    debugPrint('rawData: $rawData');

    final data = _extractCallData(rawData);
    final callId = _readString(data, ['call_id', 'callId', 'id', 'uuid'])
        .ifEmpty(_readString(rawData, ['id', 'uuid']));

    debugPrint('[MAIN CALLKIT] decline callId: $callId');

    if (callId.isNotEmpty) {
      await FlutterCallkitIncoming.endCall(callId);

      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (_) {}

      debugPrint('[MAIN CALLKIT] decline endCall/endAllCalls success');
    }
  } catch (e, st) {
    debugPrint('!!!!!!!!!! HANDLE CALLKIT DECLINE ERROR !!!!!!!!!!');
    debugPrint('error: $e');
    debugPrint('stack: $st');
    debugPrint('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
  }
}

Future<void> _handleCallKitEndFromMain(Map<String, dynamic> rawData) async {
  try {
    debugPrint('');
    debugPrint('################################################');
    debugPrint('### HANDLE CALLKIT END FROM MAIN');
    debugPrint('################################################');
    debugPrint('rawData: $rawData');

    final data = _extractCallData(rawData);
    final callId = _readString(data, ['call_id', 'callId', 'id', 'uuid'])
        .ifEmpty(_readString(rawData, ['id', 'uuid']));

    debugPrint('[MAIN CALLKIT] end callId: $callId');

    if (callId.isNotEmpty) {
      await FlutterCallkitIncoming.endCall(callId);

      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (_) {}

      debugPrint('[MAIN CALLKIT] endCall/endAllCalls success');
    }
  } catch (e, st) {
    debugPrint('!!!!!!!!!! HANDLE CALLKIT END ERROR !!!!!!!!!!');
    debugPrint('error: $e');
    debugPrint('stack: $st');
    debugPrint('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
  }
}

Future<void> _waitForNavigatorReady() async {
  int attempt = 0;

  while (GlobalCallHandler.navigatorKey.currentState == null && attempt < 30) {
    debugPrint('[MAIN CALLKIT] Waiting for navigator... attempt=$attempt');
    await Future.delayed(const Duration(milliseconds: 200));
    attempt++;
  }
}

Map<String, dynamic> _extractCallData(Map<String, dynamic> rawData) {
  final bodyRaw = rawData['body'];

  if (bodyRaw is Map) {
    final body = Map<String, dynamic>.from(bodyRaw);
    final extraRaw = body['extra'];

    if (extraRaw is Map) {
      final extra = Map<String, dynamic>.from(extraRaw);

      // Preserve CallKit type because type: 1 means video.
      if (extra['type'] == null && body['type'] != null) {
        extra['type'] = body['type'];
      }

      if (extra['type'] == null && rawData['type'] != null) {
        extra['type'] = rawData['type'];
      }

      return extra;
    }

    if (body['type'] == null && rawData['type'] != null) {
      body['type'] = rawData['type'];
    }

    return body;
  }

  final extraRaw = rawData['extra'];

  if (extraRaw is Map) {
    final extra = Map<String, dynamic>.from(extraRaw);

    if (extra['type'] == null && rawData['type'] != null) {
      extra['type'] = rawData['type'];
    }

    return extra;
  }

  return rawData;
}

Map<String, dynamic> _safeMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }

  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return <String, dynamic>{};
}

String _readString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];

    if (value == null) continue;

    final text = value.toString().trim();

    if (text.isNotEmpty && text != 'null') {
      return text;
    }
  }

  return '';
}

bool _readBool(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];

    if (value == true) return true;
    if (value == false) return false;

    final text = value?.toString().trim().toLowerCase() ?? '';

    if (text == 'true' || text == '1' || text == 'yes') {
      return true;
    }

    if (text == 'false' || text == '0' || text == 'no') {
      return false;
    }
  }

  return false;
}

extension _StringFallback on String {
  String ifEmpty(String fallback) {
    if (trim().isEmpty) return fallback;
    return this;
  }
}

/*
  This class is not used in MaterialApp builder because AuthGate starts
  the global incoming-call socket.

  Keep it only for old references.
  Do not wrap the app with it, otherwise duplicate incoming screens may appear.
*/
class GlobalCallBootstrapper extends StatefulWidget {
  final Widget child;

  const GlobalCallBootstrapper({
    super.key,
    required this.child,
  });

  @override
  State<GlobalCallBootstrapper> createState() =>
      _GlobalCallBootstrapperState();
}

class _GlobalCallBootstrapperState extends State<GlobalCallBootstrapper>
    with WidgetsBindingObserver {
  bool _starting = false;
  bool _started = false;
  String? _startedUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStartGlobalSocket();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStartGlobalSocket();
    });
  }

  @override
  void didUpdateWidget(covariant GlobalCallBootstrapper oldWidget) {
    super.didUpdateWidget(oldWidget);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStartGlobalSocket();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[GLOBAL BOOTSTRAP] App resumed. Checking global call socket.');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryStartGlobalSocket(force: true);
      });
    }
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

  Future<void> _tryStartGlobalSocket({bool force = false}) async {
    if (!mounted) return;

    if (_starting) {
      debugPrint('[GLOBAL BOOTSTRAP] Already starting.');
      return;
    }

    final auth = provider.Provider.of<AuthProvider>(
      context,
      listen: false,
    );

    if (!auth.isLoggedIn) {
      debugPrint('[GLOBAL BOOTSTRAP] User not logged in.');
      _started = false;
      _startedUserId = null;
      return;
    }

    _starting = true;

    try {
      final user = Map<String, dynamic>.from(auth.user ?? {});

      final accessToken = _firstNotEmpty([
        await ApiClient.storage.read(key: 'access'),
        await ApiClient.storage.read(key: 'access_token'),
        await ApiClient.storage.read(key: 'token'),
      ]);

      final currentUserId = _firstNotEmpty([
        user['id']?.toString(),
        user['user_id']?.toString(),
        await ApiClient.storage.read(key: 'user_id'),
        await ApiClient.storage.read(key: 'id'),
      ]);

      final currentUserName = _firstNotEmpty([
        user['full_name']?.toString(),
        user['name']?.toString(),
        user['username']?.toString(),
        user['display_name']?.toString(),
        await ApiClient.storage.read(key: 'full_name'),
        await ApiClient.storage.read(key: 'name'),
        await ApiClient.storage.read(key: 'username'),
      ]);

      final currentUserAvatar = _firstNotEmpty([
        user['profile_picture']?.toString(),
        user['avatar_url']?.toString(),
        user['image_url']?.toString(),
        await ApiClient.storage.read(key: 'avatar_url'),
        await ApiClient.storage.read(key: 'image_url'),
        await ApiClient.storage.read(key: 'profile_picture'),
      ]);

      debugPrint('');
      debugPrint('################################################');
      debugPrint('### GLOBAL BOOTSTRAP START CALL SOCKET');
      debugPrint('################################################');
      debugPrint('currentUserId: $currentUserId');
      debugPrint('currentUserName: $currentUserName');
      debugPrint('token exists: ${accessToken.isNotEmpty}');
      debugPrint('started: $_started');
      debugPrint('startedUserId: $_startedUserId');
      debugPrint('force: $force');
      debugPrint('################################################');

      if (currentUserId.isEmpty) {
        debugPrint('[GLOBAL BOOTSTRAP] ERROR: currentUserId empty.');
        return;
      }

      if (accessToken.isEmpty) {
        debugPrint('[GLOBAL BOOTSTRAP] ERROR: access token empty.');
        return;
      }

      if (!force && _started && _startedUserId == currentUserId) {
        debugPrint('[GLOBAL BOOTSTRAP] Already connected for $currentUserId.');
        return;
      }

      await GlobalCallHandler.instance.connectGlobalIncomingCallSocket(
        accessToken: accessToken,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        currentUserAvatar: currentUserAvatar,
      );

      _started = true;
      _startedUserId = currentUserId;

      debugPrint('[GLOBAL BOOTSTRAP] Global call socket ready everywhere.');
    } catch (e, st) {
      debugPrint('[GLOBAL BOOTSTRAP] ERROR: $e');
      debugPrint(st.toString());
    } finally {
      _starting = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class AppText {
  static const TextTheme lightTextTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: Color(0xFF0E1730),
      height: 1.15,
    ),
    displayMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0E1730),
    ),
    headlineLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0E1730),
    ),
    headlineMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0E1730),
    ),
    titleLarge: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0E1730),
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: Color(0xFF0E1730),
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: Color(0xFF0E1730),
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: Color(0xFF64748B),
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: Color(0xFF64748B),
    ),
    labelLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    labelMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Color(0xFF4F7CF3),
    ),
  );

  static const TextTheme darkTextTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      height: 1.15,
    ),
    displayMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    headlineLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    headlineMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    titleLarge: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: Colors.white,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: Color(0xFFCBD5E1),
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: Color(0xFF94A3B8),
    ),
    labelLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    labelMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Color(0xFF93C5FD),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  bool _isPipLikeSize(BoxConstraints constraints) {
    return constraints.maxWidth < 320 || constraints.maxHeight < 520;
  }

  bool _isFinalCallStatus(CallStatus status) {
    return status == CallStatus.ended ||
        status == CallStatus.failed ||
        status == CallStatus.rejected ||
        status == CallStatus.busy ||
        status == CallStatus.timeout ||
        status == CallStatus.missed;
  }

  bool _hasActiveCall(CallState state) {
    final hasUsers = state.currentUserId?.trim().isNotEmpty == true &&
        state.receiverId?.trim().isNotEmpty == true;

    return hasUsers && !_isFinalCallStatus(state.status);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, themeMode, child) {
        return MaterialApp(
          navigatorKey: GlobalCallHandler.navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'SocialConnect',
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Arial',
            scaffoldBackgroundColor: const Color(0xFFF6F8FC),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4F7CF3),
              brightness: Brightness.light,
            ),
            textTheme: AppText.lightTextTheme,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            dividerColor: const Color(0xFFE5EAF2),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              elevation: 0,
              centerTitle: false,
              surfaceTintColor: Colors.transparent,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Arial',
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4F7CF3),
              brightness: Brightness.dark,
            ),
            textTheme: AppText.darkTextTheme,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            dividerColor: const Color(0xFF243041),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0F172A),
              elevation: 0,
              centerTitle: false,
              surfaceTintColor: Colors.transparent,
            ),
          ),
          home: const AuthGate(),

          /*
            Final Messenger-like behavior:

            App open:
            - normal screens show normally
            - MiniCallOverlay appears only when CallScreen is minimized

            Back button inside CallScreen:
            - handled by CallScreen
            - shows MiniCallOverlay inside app

            Home button from ANY screen while video call is active:
            - Android shrinks Activity into PiP
            - this builder detects tiny PiP size
            - hides Dashboard / ChatList / Profile / ChatDetail
            - shows only call video surface

            Tap PiP:
            - CallLifecycleWatcher reopens full CallScreen if it was minimized

            Force close / detached:
            - handled by CallLifecycleWatcher
            - do NOT emit call_end from Flutter
          */
          builder: (context, child) {
            return CallLifecycleWatcher(
              child: riverpod.Consumer(
                builder: (context, ref, _) {
                  final callState = ref.watch(callProvider);
                  final forceCallPipSurface =
                      ref.watch(forceCallPipSurfaceProvider);
                  final openCallScreenFromPip =
                      ref.watch(openCallScreenFromPipProvider);

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final isPipLike = _isPipLikeSize(constraints);
                      final hasActiveCall = _hasActiveCall(callState);

                      /*
                        ABSOLUTE RULE:

                        If the Android window is PiP-sized OR we are preparing
                        to enter PiP, NEVER render the normal app.

                        That means:
                        - no ChatList in PiP
                        - no Dashboard in PiP
                        - no Profile in PiP
                        - no ChatDetail in PiP
                        - no MiniCallOverlay stacked over app in PiP

                        If active call exists -> show only audio/video call UI.
                        If Android wrongly enters PiP after call ended -> show
                        only black safe surface, never normal app.
                      */
                      /*
                        EXACT MESSENGER RULE:

                        1) No active call:
                           - normal app behaves normally
                           - Home/back from ChatList/Profile/Dashboard never creates overlay

                        2) Active call:
                           - Home from any screen captures only call UI into Android PiP
                           - PiP zoom/tap opens real CallScreen
                           - never ChatScreen/ChatList/Profile/Dashboard

                        3) If Android is already PiP but call just ended:
                           - show black safe surface briefly, never leak normal app into PiP
                      */
                      if (forceCallPipSurface || isPipLike) {
                        /*
                          IMPORTANT FIX:

                          Do NOT remove `child` here.

                          `child` is the MaterialApp Navigator.
                          If we return only _GlobalPipCallSurface, the Navigator
                          is removed from the widget tree and
                          GlobalCallHandler.navigatorKey.currentState becomes null.

                          That was the exact reason PiP zoom could not open
                          the real CallScreen.

                          So we keep the Navigator alive but hidden behind the
                          call-only surface.
                        */
                        if (hasActiveCall) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Offstage(
                                offstage: true,
                                child: child ?? const SizedBox.shrink(),
                              ),
                              Positioned.fill(
                                child: _GlobalPipCallSurface(
                                  callState: callState,
                                  forceOpenRealCallScreen: false,
                                ),
                              ),
                            ],
                          );
                        }

                        if (isPipLike) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Offstage(
                                offstage: true,
                                child: child ?? const SizedBox.shrink(),
                              ),
                              const Positioned.fill(
                                child: _PipSafeBlackSurface(),
                              ),
                            ],
                          );
                        }
                      }

                      return Stack(
                        children: [
                          child ?? const SizedBox.shrink(),
                          const MiniCallOverlay(),
                        ],
                      );
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}


class _PipSafeBlackSurface extends StatelessWidget {
  const _PipSafeBlackSurface();

  @override
  Widget build(BuildContext context) {
    /*
      Failsafe.

      If Android enters PiP when call is already ended/cancelled,
      do NOT show Dashboard/ChatList/Profile in the PiP window.

      A black surface is better than leaking normal screens into PiP.
    */
    return const ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(),
    );
  }
}

class _GlobalPipCallSurface extends StatefulWidget {
  final CallState callState;
  final bool forceOpenRealCallScreen;

  const _GlobalPipCallSurface({
    required this.callState,
    required this.forceOpenRealCallScreen,
  });

  @override
  State<_GlobalPipCallSurface> createState() => _GlobalPipCallSurfaceState();
}

class _GlobalPipCallSurfaceState extends State<_GlobalPipCallSurface> {
  static bool _openingRealCallScreen = false;
  DateTime? _lastOpenAttemptAt;

  bool _isFinalStatus(CallStatus status) {
    return status == CallStatus.ended ||
        status == CallStatus.failed ||
        status == CallStatus.rejected ||
        status == CallStatus.busy ||
        status == CallStatus.timeout ||
        status == CallStatus.missed;
  }

  bool _hasActiveCall(CallState state) {
    final hasUsers = state.currentUserId?.trim().isNotEmpty == true &&
        state.receiverId?.trim().isNotEmpty == true;

    return hasUsers && !_isFinalStatus(state.status);
  }

  String _displayName() {
    final name = widget.callState.name?.trim() ?? '';
    return name.isEmpty ? 'Call' : name;
  }

  String _avatarUrl() {
    return widget.callState.avatarUrl?.trim() ?? '';
  }

  @override
  void initState() {
    super.initState();
    _maybeOpenRealCallScreen();
  }

  @override
  void didUpdateWidget(covariant _GlobalPipCallSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeOpenRealCallScreen();
  }

  void _maybeOpenRealCallScreen() {
    if (!widget.forceOpenRealCallScreen) return;
    if (!_hasActiveCall(widget.callState)) return;

    final now = DateTime.now();

    if (_lastOpenAttemptAt != null &&
        now.difference(_lastOpenAttemptAt!).inMilliseconds < 500) {
      return;
    }

    _lastOpenAttemptAt = now;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openRealCallScreen();
    });
  }

  Future<void> _openRealCallScreen() async {
    if (_openingRealCallScreen) return;
    if (!_hasActiveCall(widget.callState)) return;

    _openingRealCallScreen = true;

    try {
      debugPrint('GLOBAL PIP SURFACE TAP: OPEN ONE REAL CALLSCREEN');

      final container = riverpod.ProviderScope.containerOf(
        context,
        listen: false,
      );

      if (container.read(openingCallScreenProvider)) {
        debugPrint('GLOBAL PIP SURFACE OPEN IGNORED: already opening');
        return;
      }

      container.read(openingCallScreenProvider.notifier).state = true;

      NavigatorState? navigator;

      for (int attempt = 0; attempt < 20; attempt++) {
        navigator = GlobalCallHandler.navigatorKey.currentState;

        if (navigator != null && navigator.mounted) {
          break;
        }

        debugPrint(
          'GLOBAL PIP SURFACE WAITING NAVIGATOR: attempt ${attempt + 1}',
        );

        await Future.delayed(const Duration(milliseconds: 80));
      }

      if (navigator == null || !navigator.mounted) {
        debugPrint('GLOBAL PIP SURFACE OPEN ERROR: navigator still null');
        container.read(openingCallScreenProvider.notifier).state = false;
        return;
      }

      // Do NOT use pushAndRemoveUntil. Keep the navigator stable and open
      // exactly one resumeExistingCall route.
      await navigator.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CallScreen(
            name: widget.callState.name?.trim().isNotEmpty == true
                ? widget.callState.name!.trim()
                : 'Unknown',
            avatarUrl: widget.callState.avatarUrl?.trim() ?? '',
            isVideoCall: widget.callState.isVideoCall,
            currentUserId: widget.callState.currentUserId?.trim() ?? '',
            currentUserName: '',
            currentUserAvatar: '',
            receiverId: widget.callState.receiverId?.trim() ?? '',
            isCaller: widget.callState.isCaller,
            incomingOffer: null,
            conversationId: null,
            callId: null,
            resumeExistingCall: true,
          ),
        ),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        container.read(callScreenVisibleProvider.notifier).state = true;
        container.read(callScreenMinimizedProvider.notifier).state = false;
        container.read(forceCallPipSurfaceProvider.notifier).state = false;
        container.read(openCallScreenFromPipProvider.notifier).state = false;
        container.read(appWasInPhonePipProvider.notifier).state = false;
      });
    } catch (e, st) {
      debugPrint('GLOBAL PIP SURFACE OPEN CALLSCREEN ERROR: $e');
      debugPrint(st.toString());
    } finally {
      final container = riverpod.ProviderScope.containerOf(
        context,
        listen: false,
      );
      container.read(openingCallScreenProvider.notifier).state = false;
      _openingRealCallScreen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final remoteRenderer = widget.callState.remoteRenderer;
    final localRenderer = widget.callState.localRenderer;

    final isActive = !_isFinalStatus(widget.callState.status);

    final hasRemoteVideo = isActive &&
        widget.callState.isVideoCall &&
        !widget.callState.isRemoteCameraOff &&
        remoteRenderer != null &&
        remoteRenderer.srcObject != null;

    final hasLocalVideo = isActive &&
        widget.callState.isVideoCall &&
        !widget.callState.isCameraOff &&
        localRenderer != null &&
        localRenderer.srcObject != null;

    /*
      Temporary call-only surface.

      This is used only:
      - while Android is entering PiP
      - while Android PiP is tiny
      - for a few milliseconds after PiP expands, until real CallScreen opens

      Tap on this surface also opens real CallScreen.
      So user never gets stuck on a fullscreen temporary surface without
      call-end button.
    */
    if (widget.callState.isVideoCall) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openRealCallScreen,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasRemoteVideo)
                RTCVideoView(
                  remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else if (hasLocalVideo)
                RTCVideoView(
                  localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                ),

              if (hasRemoteVideo && hasLocalVideo)
                Positioned(
                  top: 8,
                  right: 8,
                  width: 58,
                  height: 82,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.25),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: RTCVideoView(
                        localRenderer,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),

              if (widget.forceOpenRealCallScreen)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 22,
                  child: Center(
                    child: Text(
                      'Opening call...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final avatar = _avatarUrl();
    final hasAvatar = avatar.isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openRealCallScreen,
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF1877F2),
                    backgroundImage: hasAvatar ? NetworkImage(avatar) : null,
                    child: !hasAvatar
                        ? const Icon(
                            Icons.call_rounded,
                            color: Colors.white,
                            size: 30,
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      _displayName(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Audio call',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (widget.forceOpenRealCallScreen) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Opening call...',
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
