// lib/core/call/call_notification.dart

import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';

import 'package:messaging_app/call_waiting.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/core/call/call_api.dart';
import 'package:messaging_app/core/call/call_socket_service.dart';
import 'package:messaging_app/core/call/global_call_handler.dart';
import 'package:messaging_app/core/config/app_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  debugPrint('================ BACKGROUND FCM ================');
  debugPrint('BACKGROUND DATA: ${message.data}');
  debugPrint('BACKGROUND TITLE: ${message.notification?.title}');
  debugPrint('BACKGROUND BODY: ${message.notification?.body}');
  debugPrint('================================================');

  final data = Map<String, dynamic>.from(message.data);

  if (data.isEmpty) {
    debugPrint('BACKGROUND FCM DATA EMPTY');
    return;
  }

  final type = data['type']?.toString();

  if (type == 'incoming_call') {
    await NotificationService.showIncomingCall(data);
    return;
  }

  debugPrint('BACKGROUND FCM IGNORED TYPE: $type');
}

class NotificationService {
  NotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static bool _initialized = false;
  static bool _callKitListenerRegistered = false;

  static bool _handlingDecline = false;
  static bool _handlingTimeout = false;

  static String? _openingCallKey;
  static DateTime? _openingCallKeyTime;

  static String? _lastShownCallKitKey;
  static DateTime? _lastShownCallKitKeyTime;

  static Future<void> init() async {
    if (_initialized) {
      debugPrint('NotificationService already initialized');
      return;
    }

    _initialized = true;

    await _requestFirebasePermission();
    await _requestCallKitPermissions();

    /*
      This listener handles DECLINE and TIMEOUT only.
      ANSWER is handled in main.dart to avoid duplicate screens.
    */
    _listenCallKitEvents();

    await saveCurrentToken();

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      await _sendTokenToBackend(token);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('================ FOREGROUND FCM ================');
      debugPrint('FOREGROUND DATA: ${message.data}');
      debugPrint('FOREGROUND TITLE: ${message.notification?.title}');
      debugPrint('FOREGROUND BODY: ${message.notification?.body}');
      debugPrint('================================================');

      final data = Map<String, dynamic>.from(message.data);

      if (data.isEmpty) {
        debugPrint('FOREGROUND FCM DATA EMPTY');
        return;
      }

      final type = data['type']?.toString();

      if (type == 'incoming_call') {
        debugPrint(
          'FOREGROUND INCOMING CALL FCM SKIPPED: global socket handles UI',
        );
        return;
      }

      debugPrint('FOREGROUND FCM IGNORED TYPE: $type');
    });

    /*
      User taps the notification body, not ANSWER.
      In that case, open CallWaitingScreen.
    */
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      debugPrint('OPENED FROM BACKGROUND FCM DATA: ${message.data}');

      final data = Map<String, dynamic>.from(message.data);

      if (data['type']?.toString() == 'incoming_call') {
        await _openCallWaitingScreenFromData(data);
      }
    });

    /*
      App opened from terminated state by tapping notification body.
      This is not CallKit ANSWER. ANSWER is handled in main.dart.
    */
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      debugPrint('OPENED FROM TERMINATED FCM DATA: ${initialMessage.data}');

      final data = Map<String, dynamic>.from(initialMessage.data);

      if (data['type']?.toString() == 'incoming_call') {
        Future.delayed(const Duration(milliseconds: 900), () async {
          await _openCallWaitingScreenFromData(data);
        });
      }
    }

    await _debugActiveCallKitCalls();
  }

  static Future<void> _requestFirebasePermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
        provisional: false,
      );

      debugPrint('FCM PERMISSION STATUS: ${settings.authorizationStatus}');

      if (!kIsWeb && Platform.isIOS) {
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e, st) {
      debugPrint('FCM PERMISSION ERROR: $e');
      debugPrint(st.toString());
    }
  }

  static Future<void> _requestCallKitPermissions() async {
    if (kIsWeb) return;

    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'rationaleMessagePermission':
            'Notification permission is required to show incoming calls.',
        'postNotificationMessageRequired':
            'Please allow notification permission from settings.',
      });

      if (Platform.isAndroid) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }

      debugPrint('CALLKIT PERMISSIONS REQUESTED');
    } catch (e, st) {
      debugPrint('CALLKIT PERMISSION ERROR: $e');
      debugPrint(st.toString());
    }
  }

  static void _listenCallKitEvents() {
    if (_callKitListenerRegistered) return;

    _callKitListenerRegistered = true;

    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;

      debugPrint('================ CALLKIT EVENT ================');
      debugPrint('CALLKIT EVENT: ${event.event}');
      debugPrint('CALLKIT BODY: ${event.body}');
      debugPrint('===============================================');

      final body = _asMap(event.body);
      final extra = _asMap(body['extra']);

      switch (event.event) {
        case Event.actionCallAccept:
          /*
            IMPORTANT:
            Do not open CallWaitingScreen here.
            main.dart handles ANSWER. If this file also handles ANSWER,
            two screens can open or the app can fall back to ChatListScreen.
          */
          debugPrint(
            'CALLKIT ACCEPT IGNORED IN NotificationService. main.dart handles ANSWER.',
          );
          break;

        case Event.actionCallDecline:
          if (_handlingDecline) {
            debugPrint('CALLKIT DECLINE IGNORED: already handling');
            return;
          }

          _handlingDecline = true;

          try {
            await _declineCall(extra, body);
          } finally {
            Future.delayed(const Duration(milliseconds: 1000), () {
              _handlingDecline = false;
            });
          }

          break;

        case Event.actionCallTimeout:
          if (_handlingTimeout) {
            debugPrint('CALLKIT TIMEOUT IGNORED: already handling');
            return;
          }

          _handlingTimeout = true;

          try {
            await _timeoutCall(extra, body);
          } finally {
            Future.delayed(const Duration(milliseconds: 1000), () {
              _handlingTimeout = false;
            });
          }

          break;

        case Event.actionCallEnded:
          final callId = _readFirstString(extra, body, const [
            'call_id',
            'callId',
            'id',
          ]);

          debugPrint('CALLKIT ACTION ENDED IGNORED: $callId');
          break;

        default:
          debugPrint('CALLKIT EVENT IGNORED: ${event.event}');
          break;
      }
    });
  }

  static Future<void> showIncomingCall(Map<String, dynamic> data) async {
    if (kIsWeb) {
      debugPrint('CALLKIT NOT SUPPORTED ON WEB');
      return;
    }

    try {
      final callId = _readFirstString(data, const {}, const [
        'call_id',
        'callId',
        'id',
      ]);

      final callerId = _readFirstString(data, const {}, const [
        'caller_id',
        'callerId',
        'from',
        'from_user',
      ]);

      final callerName = _readFirstString(
        data,
        const {},
        const [
          'caller_name',
          'callerName',
          'nameCaller',
          'name',
        ],
        fallback: 'Incoming call',
      );

      final callerAvatar = _readFirstString(data, const {}, const [
        'caller_avatar',
        'callerAvatar',
        'avatar',
      ]);

      final conversationId = _readFirstString(data, const {}, const [
        'conversation_id',
        'conversationId',
      ]);

      final isVideoCall =
      _readBool(data['is_video_call']) ||
      _readBool(data['isVideoCall']) ||
      _readBool(data['video']) ||
       data['type'] == 1 ||
       data['type']?.toString() == '1';

      if (callerId.isEmpty) {
        debugPrint('SHOW INCOMING CALL ERROR: callerId empty');
        return;
      }

      if (conversationId.isEmpty) {
        debugPrint('SHOW INCOMING CALL ERROR: conversationId empty');
        return;
      }

      final id = callId.isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : callId;

      final callKey = _buildCallKey(
        callId: id,
        conversationId: conversationId,
        callerId: callerId,
      );

      if (_isRecentDuplicate(
        key: callKey,
        existingKey: _lastShownCallKitKey,
        existingTime: _lastShownCallKitKeyTime,
        withinSeconds: 30,
      )) {
        debugPrint('CALLKIT SHOW SKIP DUPLICATE: $callKey');
        return;
      }

      _lastShownCallKitKey = callKey;
      _lastShownCallKitKeyTime = DateTime.now();

      final extra = <String, dynamic>{
        'type': 'incoming_call',
        'call_id': id,
        'callId': id,
        'conversation_id': conversationId,
        'conversationId': conversationId,
        'caller_id': callerId,
        'callerId': callerId,
        'caller_name': callerName,
        'callerName': callerName,
        'caller_avatar': callerAvatar,
        'callerAvatar': callerAvatar,
        'is_video_call': isVideoCall.toString(),
        'isVideoCall': isVideoCall.toString(),
      };

      final params = CallKitParams(
        id: id,
        nameCaller: callerName,
        appName: 'SocialConnect',
        avatar: callerAvatar,
        handle: callerId,
        type: isVideoCall ? 1 : 0,
        textAccept: 'Accept',
        textDecline: 'Decline',
        duration: 30000,
        extra: extra,
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Missed call',
          callbackText: 'Call back',
        ),
        android: AndroidParams(
          isCustomNotification: true,
          isShowLogo: true,
          ringtonePath: 'incoming_call',
          backgroundColor: '#0F172A',
          backgroundUrl: callerAvatar,
          actionColor: '#4CAF50',
          textColor: '#FFFFFF',
          incomingCallNotificationChannelName: 'Incoming Calls',
          missedCallNotificationChannelName: 'Missed Calls',
          isShowCallID: false,
        ),
        ios: const IOSParams(
          iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: true,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'incoming_call.mp3',
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);

      debugPrint('CALLKIT INCOMING SHOWN: $extra');
    } catch (e, st) {
      debugPrint('SHOW INCOMING CALL ERROR: $e');
      debugPrint(st.toString());
    }
  }

  /*
    Kept as a fallback/helper, but NotificationService does not call this from
    Event.actionCallAccept anymore. main.dart handles ANSWER.
  */
  static Future<void> _acceptCall(
    Map<String, dynamic> extra,
    Map<String, dynamic> body,
  ) async {
    final callId = _readFirstString(extra, body, const [
      'call_id',
      'callId',
      'id',
    ]);

    final callerId = _readFirstString(extra, body, const [
      'caller_id',
      'callerId',
      'from',
      'from_user',
      'handle',
    ]);

    final callerName = _readFirstString(
      extra,
      body,
      const [
        'caller_name',
        'callerName',
        'nameCaller',
        'name',
      ],
      fallback: 'Incoming call',
    );

    final callerAvatar = _readFirstString(extra, body, const [
      'caller_avatar',
      'callerAvatar',
      'avatar',
    ]);

    final conversationId = _readFirstString(extra, body, const [
      'conversation_id',
      'conversationId',
    ]);

    final isVideoCall = _readBool(extra['is_video_call']) ||
        _readBool(extra['isVideoCall']) ||
        _readBool(body['is_video_call']) ||
        _readBool(body['isVideoCall']) ||
        body['type'] == 1 ||
        body['type']?.toString() == '1';

    final currentUserId =
        (await ApiClient.storage.read(key: 'user_id'))?.trim() ?? '';

    final currentUserName =
        (await ApiClient.storage.read(key: 'full_name'))?.trim() ?? '';

    final currentUserAvatar =
        (await ApiClient.storage.read(key: 'avatar_url'))?.trim() ??
            (await ApiClient.storage.read(key: 'image_url'))?.trim() ??
            '';

    debugPrint('================ CALL ACCEPT FALLBACK ================');
    debugPrint('CALL ACCEPT currentUserId=$currentUserId');
    debugPrint('CALL ACCEPT callId=$callId');
    debugPrint('CALL ACCEPT callerId=$callerId');
    debugPrint('CALL ACCEPT conversationId=$conversationId');
    debugPrint('CALL ACCEPT isVideoCall=$isVideoCall');
    debugPrint('=====================================================');

    if (currentUserId.isEmpty) {
      debugPrint('CALL ACCEPT ERROR: currentUserId empty');
      return;
    }

    if (callerId.isEmpty) {
      debugPrint('CALL ACCEPT ERROR: callerId empty');
      return;
    }

    if (conversationId.isEmpty) {
      debugPrint('CALL ACCEPT ERROR: conversationId empty');
      return;
    }

    await _openCallWaitingScreen(
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      currentUserAvatar: currentUserAvatar,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      isVideoCall: isVideoCall,
      conversationId: conversationId,
      callId: callId,
    );

    /*
      Do NOT call endCall(callId) here.
      ANSWER means accepted, not ended.
    */
    if (callId.isNotEmpty) {
      unawaited(
        _safeUpdateCallStatus(
          callId: callId,
          status: 'accepted',
        ),
      );
    }
  }

  static Future<void> _declineCall(
    Map<String, dynamic> extra,
    Map<String, dynamic> body,
  ) async {
    final callId = _readFirstString(extra, body, const [
      'call_id',
      'callId',
      'id',
    ]);

    final callerId = _readFirstString(extra, body, const [
      'caller_id',
      'callerId',
      'from',
      'from_user',
      'handle',
    ]);

    final conversationId = _readFirstString(extra, body, const [
      'conversation_id',
      'conversationId',
    ]);

    final currentUserId =
        (await ApiClient.storage.read(key: 'user_id'))?.trim() ?? '';

    bool socketConnected = false;

    if (conversationId.isNotEmpty) {
      socketConnected = await _ensureCallSocketConnectedForPayload({
        'conversation_id': conversationId,
        'conversationId': conversationId,
      });
    }

    if (!socketConnected) {
      debugPrint('CALL DECLINE WARNING: socket not connected');
    }

    if (currentUserId.isNotEmpty &&
        callerId.isNotEmpty &&
        conversationId.isNotEmpty) {
      SocketService.instance.emit(
        CallSocketEvents.callReject,
        {
          'from': currentUserId,
          'from_user': currentUserId,
          'call_id': callId,
          'callId': callId,
          'conversation_id': conversationId,
          'conversationId': conversationId,
          'reason': 'rejected',
          'rejected_from_callkit': 'true',
        },
        targetUser: callerId,
        conversationId: conversationId,
        queueIfDisconnected: true,
      );
    }

    if (callId.isNotEmpty) {
      await _safeUpdateCallStatus(
        callId: callId,
        status: 'rejected',
      );

      await endCall(callId);
    }

    _clearOpeningCallGuard(callId: callId, conversationId: conversationId);
  }

  static Future<void> _timeoutCall(
    Map<String, dynamic> extra,
    Map<String, dynamic> body,
  ) async {
    final callId = _readFirstString(extra, body, const [
      'call_id',
      'callId',
      'id',
    ]);

    final callerId = _readFirstString(extra, body, const [
      'caller_id',
      'callerId',
      'from',
      'from_user',
      'handle',
    ]);

    final conversationId = _readFirstString(extra, body, const [
      'conversation_id',
      'conversationId',
    ]);

    final currentUserId =
        (await ApiClient.storage.read(key: 'user_id'))?.trim() ?? '';

    bool socketConnected = false;

    if (conversationId.isNotEmpty) {
      socketConnected = await _ensureCallSocketConnectedForPayload({
        'conversation_id': conversationId,
        'conversationId': conversationId,
      });
    }

    if (!socketConnected) {
      debugPrint('CALL TIMEOUT WARNING: socket not connected');
    }

    if (currentUserId.isNotEmpty &&
        callerId.isNotEmpty &&
        conversationId.isNotEmpty) {
      SocketService.instance.emit(
        CallSocketEvents.callTimeout,
        {
          'from': currentUserId,
          'from_user': currentUserId,
          'call_id': callId,
          'callId': callId,
          'conversation_id': conversationId,
          'conversationId': conversationId,
          'reason': 'timeout',
          'timeout_from_callkit': 'true',
        },
        targetUser: callerId,
        conversationId: conversationId,
        queueIfDisconnected: true,
      );
    }

    if (callId.isNotEmpty) {
      await _safeUpdateCallStatus(
        callId: callId,
        status: 'missed',
      );

      await endCall(callId);
    }

    _clearOpeningCallGuard(callId: callId, conversationId: conversationId);
  }

  static Future<bool> _ensureCallSocketConnectedForPayload(
    Map<String, dynamic> data,
  ) async {
    try {
      String? accessToken = await ApiClient.storage.read(key: 'access');

      final currentUserId =
          (await ApiClient.storage.read(key: 'user_id'))?.trim() ?? '';

      final currentUserName =
          (await ApiClient.storage.read(key: 'full_name'))?.trim() ?? '';

      final currentUserAvatar =
          (await ApiClient.storage.read(key: 'avatar_url'))?.trim() ??
              (await ApiClient.storage.read(key: 'image_url'))?.trim() ??
              '';

      final conversationId = _readFirstString(data, const {}, const [
        'conversation_id',
        'conversationId',
      ]);

      debugPrint('========== CALL SOCKET CONNECT DEBUG ==========');
      debugPrint('conversationId: $conversationId');
      debugPrint(
        'accessToken empty before refresh: ${accessToken == null || accessToken.trim().isEmpty}',
      );
      debugPrint('accessToken length before refresh: ${accessToken?.length ?? 0}');
      debugPrint('currentUserId: $currentUserId');
      debugPrint('currentUserName: $currentUserName');
      debugPrint('AppConfig.apiBaseUrl: ${AppConfig.apiBaseUrl}');
      debugPrint('AppConfig.wsBaseUrl: ${AppConfig.wsBaseUrl}');
      debugPrint('================================================');

      if (conversationId.isEmpty) {
        debugPrint('CALL SOCKET CONNECT ERROR: conversation id empty');
        return false;
      }

      if (currentUserId.isEmpty) {
        debugPrint('CALL SOCKET CONNECT ERROR: current user id empty');
        return false;
      }

      if (accessToken == null || accessToken.trim().isEmpty) {
        debugPrint('CALL SOCKET ACCESS EMPTY: trying refresh token');

        accessToken = await ApiClient.refreshAccessToken();

        if (accessToken == null || accessToken.trim().isEmpty) {
          debugPrint(
            'CALL SOCKET CONNECT ERROR: access token empty after refresh',
          );
          return false;
        }
      }

      final parsedConversationId = int.tryParse(conversationId);

      if (parsedConversationId == null) {
        debugPrint(
          'CALL SOCKET CONNECT ERROR: conversation id is not number: $conversationId',
        );
        return false;
      }

      final url = AppConfig.callSocketUrl(
        conversationId: parsedConversationId,
        token: accessToken.trim(),
      );

      debugPrint('CALL SOCKET FINAL URL: $url');

      await GlobalCallHandler.connectCallSocket(
        url: url,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        currentUserAvatar: currentUserAvatar,
      );

      await Future.delayed(const Duration(milliseconds: 300));

      if (!SocketService.instance.isConnected) {
        debugPrint('CALL SOCKET CONNECT ERROR: SocketService.isConnected false');
        return false;
      }

      debugPrint('CALL SOCKET CONNECTED FROM CALL NOTIFICATION');
      return true;
    } catch (e, st) {
      debugPrint('CALL SOCKET CONNECT FROM NOTIFICATION ERROR: $e');
      debugPrint(st.toString());
      return false;
    }
  }

  static Future<void> _openCallWaitingScreenFromData(
    Map<String, dynamic> data,
  ) async {
    final currentUserId =
        (await ApiClient.storage.read(key: 'user_id'))?.trim() ?? '';

    final currentUserName =
        (await ApiClient.storage.read(key: 'full_name'))?.trim() ?? '';

    final currentUserAvatar =
        (await ApiClient.storage.read(key: 'avatar_url'))?.trim() ??
            (await ApiClient.storage.read(key: 'image_url'))?.trim() ??
            '';

    final callerId = _readFirstString(data, const {}, const [
      'caller_id',
      'callerId',
      'from',
      'from_user',
    ]);

    final callerName = _readFirstString(
      data,
      const {},
      const [
        'caller_name',
        'callerName',
        'nameCaller',
        'name',
      ],
      fallback: 'Incoming call',
    );

    final callerAvatar = _readFirstString(data, const {}, const [
      'caller_avatar',
      'callerAvatar',
      'avatar',
    ]);

    final conversationId = _readFirstString(data, const {}, const [
      'conversation_id',
      'conversationId',
    ]);

    final callId = _readFirstString(data, const {}, const [
      'call_id',
      'callId',
      'id',
    ]);

     final isVideoCall =
     _readBool(data['is_video_call']) ||
     _readBool(data['isVideoCall']) ||
     _readBool(data['video']) ||
     data['type'] == 1 ||
     data['type']?.toString() == '1';

    debugPrint('OPEN CALL WAITING FROM FCM CLICK');
    debugPrint('currentUserId=$currentUserId');
    debugPrint('callerId=$callerId');
    debugPrint('conversationId=$conversationId');
    debugPrint('callId=$callId');

    await _openCallWaitingScreen(
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      currentUserAvatar: currentUserAvatar,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      isVideoCall: isVideoCall,
      conversationId: conversationId,
      callId: callId,
    );
  }

  static Future<void> _openCallWaitingScreen({
    required String currentUserId,
    required String currentUserName,
    required String currentUserAvatar,
    required String callerId,
    required String callerName,
    required String callerAvatar,
    required bool isVideoCall,
    required String conversationId,
    required String callId,
  }) async {
    if (currentUserId.isEmpty) {
      debugPrint('OPEN CALL WAITING ERROR: currentUserId empty');
      return;
    }

    if (callerId.isEmpty) {
      debugPrint('OPEN CALL WAITING ERROR: callerId empty');
      return;
    }

    if (conversationId.isEmpty) {
      debugPrint('OPEN CALL WAITING ERROR: conversationId empty');
      return;
    }

    final callKey = _buildCallKey(
      callId: callId,
      conversationId: conversationId,
      callerId: callerId,
    );

    if (_isRecentDuplicate(
      key: callKey,
      existingKey: _openingCallKey,
      existingTime: _openingCallKeyTime,
      withinSeconds: 30,
    )) {
      debugPrint('OPEN CALL WAITING SKIP DUPLICATE: $callKey');
      return;
    }

    _openingCallKey = callKey;
    _openingCallKeyTime = DateTime.now();

    debugPrint('OPEN CALL WAITING SCHEDULED FORCE ROUTE: $callKey');

    unawaited(
      Future.delayed(const Duration(milliseconds: 1200), () async {
        final navigator = await _waitForNavigator();

        if (navigator == null) {
          debugPrint('OPEN CALL WAITING ERROR: navigator still null after retry');
          _clearOpeningCallGuard(
            callId: callId,
            conversationId: conversationId,
          );
          return;
        }

        final context = navigator.context;

        if (!context.mounted) {
          debugPrint('OPEN CALL WAITING ERROR: navigator context not mounted');
          _clearOpeningCallGuard(
            callId: callId,
            conversationId: conversationId,
          );
          return;
        }

        debugPrint('OPEN CALL WAITING FORCE PUSHING ROUTE: $callKey');

        navigator.pushAndRemoveUntil(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => CallWaitingScreen(
              currentUserId: currentUserId,
              currentUserName: currentUserName,
              currentUserAvatar: currentUserAvatar,
              callerId: callerId,
              callerName: callerName,
              callerAvatar: callerAvatar,
              isVideoCall: isVideoCall,
              conversationId: conversationId,
              callId: callId,
              chat: null,
              emitAcceptOnOpen: true,
            ),
          ),
          (route) => route.isFirst,
        );

        Future.delayed(const Duration(seconds: 5), () {
          _clearOpeningCallGuard(
            callId: callId,
            conversationId: conversationId,
          );
        });
      }),
    );
  }

  static Future<NavigatorState?> _waitForNavigator() async {
    for (int i = 0; i < 50; i++) {
      final navigator = GlobalCallHandler.navigatorKey.currentState;

      if (navigator != null) {
        return navigator;
      }

      await Future.delayed(const Duration(milliseconds: 250));
    }

    return null;
  }

  static Future<void> _debugActiveCallKitCalls() async {
    if (kIsWeb) return;

    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      debugPrint('ACTIVE CALLKIT CALLS: $activeCalls');
    } catch (e, st) {
      debugPrint('ACTIVE CALLKIT ERROR: $e');
      debugPrint(st.toString());
    }
  }

  static Future<void> saveCurrentToken() async {
    try {
      if (kIsWeb) return;

      final token = await _messaging.getToken();

      debugPrint('FCM TOKEN: $token');

      if (token == null || token.trim().isEmpty) {
        debugPrint('FCM TOKEN EMPTY');
        return;
      }

      await ApiClient.storage.write(
        key: 'fcm_token',
        value: token.trim(),
      );

      await _sendTokenToBackend(token.trim());
    } catch (e, st) {
      debugPrint('FCM TOKEN ERROR: $e');
      debugPrint(st.toString());
    }
  }

  static Future<void> _sendTokenToBackend(String token) async {
    try {
      final access = await ApiClient.storage.read(key: 'access');

      if (access == null || access.trim().isEmpty) {
        debugPrint('FCM TOKEN SKIP BACKEND: user not logged in yet');
        return;
      }

      String platform = 'android';
      String deviceName = 'Android';

      if (Platform.isIOS) {
        platform = 'ios';
        deviceName = 'iOS';
      } else if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        deviceName = '${info.manufacturer} ${info.model}'.trim();
      }

      await ApiClient.dio.post(
        '/chat/fcm-token/',
        data: {
          'token': token.trim(),
          'platform': platform,
          'device_id': deviceName,
          'device_name': deviceName,
        },
      );

      debugPrint('FCM TOKEN SAVED TO BACKEND /chat/fcm-token/');
    } catch (e, st) {
      debugPrint('FCM TOKEN SAVE BACKEND ERROR: $e');
      debugPrint(st.toString());
    }
  }

  static Future<void> endCall(String callId) async {
    if (callId.trim().isEmpty) return;

    try {
      await FlutterCallkitIncoming.endCall(callId.trim());
      debugPrint('CALLKIT END CALL: $callId');
    } catch (e, st) {
      debugPrint('CALLKIT END CALL ERROR: $e');
      debugPrint(st.toString());
    }
  }

  static Future<void> endAllCalls() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
      debugPrint('CALLKIT END ALL CALLS');
    } catch (e, st) {
      debugPrint('CALLKIT END ALL CALLS ERROR: $e');
      debugPrint(st.toString());
    }
  }

  static Future<void> _safeUpdateCallStatus({
    required String callId,
    required String status,
  }) async {
    if (callId.trim().isEmpty) return;

    try {
      await CallApi.updateCallStatus(
        callId: callId.trim(),
        status: status,
      );
    } catch (e, st) {
      debugPrint('CALL STATUS UPDATE ERROR: $e');
      debugPrint(st.toString());
    }
  }

  static void _clearOpeningCallGuard({
    required String callId,
    required String conversationId,
  }) {
    if (_openingCallKey == null) return;

    final currentKey = _openingCallKey ?? '';

    if (callId.isNotEmpty && currentKey == callId) {
      _openingCallKey = null;
      _openingCallKeyTime = null;
      return;
    }

    if (conversationId.isNotEmpty && currentKey.contains(conversationId)) {
      _openingCallKey = null;
      _openingCallKeyTime = null;
    }
  }

  static String _buildCallKey({
    required String callId,
    required String conversationId,
    required String callerId,
  }) {
    if (callId.trim().isNotEmpty) {
      return callId.trim();
    }

    return '${conversationId.trim()}_${callerId.trim()}';
  }

  static bool _isRecentDuplicate({
    required String key,
    required String? existingKey,
    required DateTime? existingTime,
    required int withinSeconds,
  }) {
    if (key.trim().isEmpty) return false;
    if (existingKey == null || existingKey.trim().isEmpty) return false;
    if (existingTime == null) return false;
    if (existingKey != key) return false;

    final diff = DateTime.now().difference(existingTime).inSeconds;

    return diff <= withinSeconds;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  static String _readFirstString(
    Map<String, dynamic> primary,
    Map<String, dynamic> secondary,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = primary[key];

      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }

    for (final key in keys) {
      final value = secondary[key];

      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }

    return fallback;
  }

  static bool _readBool(dynamic value) {
    if (value is bool) return value;

    if (value == null) return false;

    final text = value.toString().trim().toLowerCase();

    return text == 'true' || text == '1' || text == 'yes';
  }
}