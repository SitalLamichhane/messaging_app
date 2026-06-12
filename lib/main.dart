// lib/main.dart

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide ChangeNotifierProvider;
import 'package:provider/provider.dart';

import 'package:messaging_app/auth_gate.dart';
import 'package:messaging_app/features/auth/auth_provider.dart';
import 'package:messaging_app/theme_controller.dart';
import 'package:messaging_app/core/chat/chat_provider.dart';
import 'package:messaging_app/core/profile/profile_provider.dart';
import 'package:messaging_app/core/block/block_provider.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/core/call/global_call_handler.dart';
import 'package:messaging_app/core/call/call_notification.dart';
import 'package:messaging_app/core/call/mini_call_overlay.dart';

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
    Important:
    We register CallKit event listener early.
    But real navigation can only happen after runApp + first frame,
    because navigatorKey needs MaterialApp.
  */
  _setupCallKitDebugListener();

  runApp(
    ProviderScope(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider()..checkLogin(),
          ),
          ChangeNotifierProvider<ChatProvider>(
            create: (_) => ChatProvider(),
          ),
          ChangeNotifierProvider<ProfileProvider>(
            create: (_) => ProfileProvider(),
          ),
          ChangeNotifierProvider<BlockProvider>(
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
      This sets up FCM, local notification, CallKit show/receive logic.
    */
    debugPrint('[MAIN] Calling NotificationService.init()...');
    await NotificationService.init();
    debugPrint('[MAIN] NotificationService.init() completed');

    /*
      Killed-app fix.
      In killed state, CallKit accept event may not be caught by listener.
      So after app opens, check active CallKit calls manually.
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
        debugPrint('[MAIN CALLKIT] ACCEPT clicked');
        await _handleCallKitAcceptFromMain(body, source: 'onEvent_accept');
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
  if (_handlingColdStartCallKit) {
    debugPrint('[MAIN CALLKIT] killed-state check ignored: already handling');
    return;
  }

  try {
    debugPrint('');
    debugPrint('################################################');
    debugPrint('### CHECKING KILLED-STATE CALLKIT ACTIVE CALLS');
    debugPrint('################################################');

    final activeCalls = await FlutterCallkitIncoming.activeCalls();

    debugPrint(
      '[MAIN CALLKIT] activeCalls runtimeType: ${activeCalls.runtimeType}',
    );
    debugPrint('[MAIN CALLKIT] activeCalls: $activeCalls');

    if (activeCalls is! List || activeCalls.isEmpty) {
      debugPrint('[MAIN CALLKIT] No active CallKit calls found after cold start');
      return;
    }

    final firstRaw = activeCalls.first;
    final firstCall = _safeMap(firstRaw);

    debugPrint('[MAIN CALLKIT] first active call: $firstCall');

    final resolvedData = _extractCallData(firstCall);

    debugPrint('[MAIN CALLKIT] resolved active call data: $resolvedData');

    final conversationId = _readString(
      resolvedData,
      ['conversation_id', 'conversationId'],
    );

    final callerId = _readString(
      resolvedData,
      ['caller_id', 'callerId'],
    );

    if (conversationId.isEmpty || callerId.isEmpty) {
      debugPrint(
        '[MAIN CALLKIT] Active call missing conversationId/callerId. Cannot open socket screen.',
      );
      return;
    }

    await _handleCallKitAcceptFromMain(
      firstCall,
      source: 'activeCalls_cold_start',
    );
  } catch (e, st) {
    debugPrint('!!!!!!!!!! CHECK KILLED STATE CALLKIT ERROR !!!!!!!!!!');
    debugPrint('error: $e');
    debugPrint('stack: $st');
    debugPrint('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
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
    debugPrint('### HANDLE CALLKIT ACCEPT FROM MAIN');
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

    final isVideoCall = _readBool(
      data,
      ['is_video_call', 'isVideoCall', 'video'],
    );

    debugPrint('========== MAIN CALLKIT ACCEPT RESOLVED ==========');
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
        '[MAIN CALLKIT] ERROR: navigator is null. Cannot open CallWaitingScreen.',
      );
      return;
    }

    debugPrint('');
    debugPrint('################################################');
    debugPrint('### CALLING GlobalCallHandler.openIncomingCallFromCallKit');
    debugPrint('################################################');

    await GlobalCallHandler.instance.openIncomingCallFromCallKit(
      callId: callId,
      conversationId: conversationId,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      isVideoCall: isVideoCall,
    );
  } catch (e, st) {
    debugPrint('!!!!!!!!!! HANDLE CALLKIT ACCEPT FROM MAIN ERROR !!!!!!!!!!');
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
      debugPrint('[MAIN CALLKIT] decline endCall success');
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
      debugPrint('[MAIN CALLKIT] endCall success');
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
      return Map<String, dynamic>.from(extraRaw);
    }

    return body;
  }

  final extraRaw = rawData['extra'];

  if (extraRaw is Map) {
    return Map<String, dynamic>.from(extraRaw);
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
  Root global incoming-call listener.

  This is what makes IncomingCallScreen show everywhere while app is open:
    ChatListScreen
    Profile page
    Dashboard
    Settings
    Inside chat
    Any pushed screen
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

    final auth = context.read<AuthProvider>();

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
          builder: (context, child) {
            return GlobalCallBootstrapper(
              child: Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  const MiniCallOverlay(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}