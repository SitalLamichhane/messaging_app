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
  if (data.isEmpty) return;

  if (data['type']?.toString() == 'incoming_call') {
    await NotificationService.showIncomingCall(data);
    return;
  }

  debugPrint('BACKGROUND FCM IGNORED TYPE: ${data['type']}');
}

class NotificationService {
  NotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static bool _initialized = false;
  static bool _callKitListenerRegistered = false;

  static bool _handlingAccept = false;
  static bool _handlingDecline = false;
  static bool _handlingTimeout = false;

  static String? _lastShownCallKitKey;
  static DateTime? _lastShownCallKitKeyTime;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _requestFirebasePermission();
    await _requestCallKitPermissions();

    _listenCallKitEvents();

    await saveCurrentToken();

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      await _sendTokenToBackend(token);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('================ FOREGROUND FCM ================');
      debugPrint('FOREGROUND DATA: ${message.data}');
      debugPrint('================================================');

      final data = Map<String, dynamic>.from(message.data);
      if (data.isEmpty) return;

      final type = data['type']?.toString();

      if (type == 'incoming_call') {
        debugPrint('FOREGROUND FCM INCOMING -> OPEN IN-APP INCOMING SCREEN');

        // Foreground/app-open fallback: if the global websocket misses the event,
        // FCM still opens the Messenger-style incoming screen. If the websocket
        // already opened it, GlobalCallHandler duplicate locks will ignore it.
        await GlobalCallHandler.handleIncomingCall(data);
        return;
      }

      debugPrint('FOREGROUND FCM IGNORED TYPE: $type');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
  debugPrint('FCM onMessageOpenedApp IGNORED - CallKit handles navigation');
});

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      debugPrint('FCM getInitialMessage IGNORED - CallKit/main handles navigation');
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
          if (_handlingAccept) return;
          _handlingAccept = true;

          try {
            await _acceptCall(extra, body);
          } catch (e, st) {
            debugPrint('CALLKIT ACCEPT ERROR: $e');
            debugPrint(st.toString());
          } finally {
            Future.delayed(const Duration(milliseconds: 1500), () {
              _handlingAccept = false;
            });
          }
          break;

        case Event.actionCallDecline:
          if (_handlingDecline) return;
          _handlingDecline = true;

          try {
            await _declineCall(extra, body);
          } catch (e, st) {
            debugPrint('CALLKIT DECLINE ERROR: $e');
            debugPrint(st.toString());
          } finally {
            Future.delayed(const Duration(milliseconds: 1000), () {
              _handlingDecline = false;
            });
          }
          break;

        case Event.actionCallTimeout:
          if (_handlingTimeout) return;
          _handlingTimeout = true;

          try {
            await _timeoutCall(extra, body);
          } catch (e, st) {
            debugPrint('CALLKIT TIMEOUT ERROR: $e');
            debugPrint(st.toString());
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
    if (kIsWeb) return;

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

      final isVideoCall = _readBool(data['is_video_call']) ||
          _readBool(data['isVideoCall']) ||
          _readBool(data['video']) ||
          data['type'] == 1 ||
          data['type']?.toString() == '1';

      if (callerId.isEmpty || conversationId.isEmpty) {
        debugPrint('SHOW INCOMING CALL ERROR: missing caller/conversation');
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

  static Future<void> _acceptCall(
    Map<String, dynamic> extra,
    Map<String, dynamic> body,
  ) async {
    final callId = _readFirstString(extra, body, const [
      'call_id',
      'callId',
      'id',
      'uuid',
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

    debugPrint('================ CALLKIT ACCEPT ================');
    debugPrint('callId=$callId');
    debugPrint('callerId=$callerId');
    debugPrint('conversationId=$conversationId');
    debugPrint('isVideoCall=$isVideoCall');
    debugPrint('===============================================');

    if (callerId.isEmpty || conversationId.isEmpty) return;

    await GlobalCallHandler.instance.openIncomingCallFromCallKit(
      callId: callId,
      conversationId: conversationId,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      isVideoCall: isVideoCall,
    );

    if (callId.isNotEmpty) {
      unawaited(
        _safeUpdateCallStatus(
          callId: callId,
          status: 'accepted',
        ),
      );

      Future.delayed(const Duration(milliseconds: 900), () async {
        try {
          await FlutterCallkitIncoming.endCall(callId);
          debugPrint('CALLKIT ACCEPT CLEANUP END CALL: $callId');
        } catch (e) {
          debugPrint('CALLKIT ACCEPT CLEANUP ERROR: $e');
        }
      });
    }
  }

  static Future<void> _openDirectCallScreenFromData(
    Map<String, dynamic> data,
  ) async {
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

    final isVideoCall = _readBool(data['is_video_call']) ||
        _readBool(data['isVideoCall']) ||
        _readBool(data['video']) ||
        data['type'] == 1 ||
        data['type']?.toString() == '1';

    if (callerId.isEmpty || conversationId.isEmpty) return;

    await GlobalCallHandler.instance.openIncomingCallFromCallKit(
      callId: callId,
      conversationId: conversationId,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      isVideoCall: isVideoCall,
    );
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

    await _safeDisconnectCallSocket();
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

    await _safeDisconnectCallSocket();
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

      if (conversationId.isEmpty || currentUserId.isEmpty) return false;

      if (accessToken == null || accessToken.trim().isEmpty) {
        accessToken = await ApiClient.refreshAccessToken();
        if (accessToken == null || accessToken.trim().isEmpty) return false;
      }

      final parsedConversationId = int.tryParse(conversationId);
      if (parsedConversationId == null) return false;

      final url = AppConfig.callSocketUrl(
        conversationId: parsedConversationId,
        token: accessToken.trim(),
      );

      await GlobalCallHandler.connectCallSocket(
        url: url,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        currentUserAvatar: currentUserAvatar,
      );

      await Future.delayed(const Duration(milliseconds: 300));
      return SocketService.instance.isConnected;
    } catch (e, st) {
      debugPrint('CALL SOCKET CONNECT FROM NOTIFICATION ERROR: $e');
      debugPrint(st.toString());
      return false;
    }
  }

  static Future<void> _safeDisconnectCallSocket() async {
    try {
      await SocketService.instance.disconnect(
        clearHandlers: false,
        clearQueue: true,
        clearCache: true,
        forgetUrl: true,
      );
    } catch (e) {
      debugPrint('CALL SOCKET SAFE DISCONNECT ERROR: $e');
    }
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

      if (token == null || token.trim().isEmpty) return;

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
      if (access == null || access.trim().isEmpty) return;

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

  static Future<void> endAllNativeCalls() async {
    await endAllCalls();
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

  static String _buildCallKey({
    required String callId,
    required String conversationId,
    required String callerId,
  }) {
    if (callId.trim().isNotEmpty) return callId.trim();
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

    return DateTime.now().difference(existingTime).inSeconds <= withinSeconds;
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
}///////////  all good