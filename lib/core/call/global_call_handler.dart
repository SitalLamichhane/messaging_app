// lib/core/call/global_call_handler.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hiddenly/core/call/call_api.dart';
import 'package:hiddenly/groupCall/domain/presentation/screens/group_call_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiddenly/incoming_call_screen.dart';
import 'package:hiddenly/call_screen.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/core/config/app_config.dart';
import 'package:hiddenly/core/call/call_socket_service.dart';
import 'package:hiddenly/core/call/global_call_socket_service.dart';
import 'package:hiddenly/groupCall/domain/application/group_call_controller.dart';
import 'package:hiddenly/groupCall/domain/infrastructure/call_api_service.dart';
import 'package:hiddenly/groupCall/domain/presentation/screens/incoming_group_call_screen.dart';
import 'package:hiddenly/groupCall/domain/call_models.dart';
import 'package:hiddenly/realtime/realtime_service.dart';

class GlobalCallHandler {
  static final GlobalCallHandler instance = GlobalCallHandler._internal();
  GlobalCallHandler._internal();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  bool _registered = false;
  bool _callScreenOpen = false;
  bool _openingIncomingScreen = false;

  String? _currentUserId;
  String? _currentUserName;
  String? _currentUserAvatar;

  String? _activeIncomingCallerId;
  String? _activeIncomingConversationId;
  String? _activeIncomingCallId;

  String? _lastIncomingKey;
  DateTime? _lastIncomingKeyTime;

  String? _lastCallKitOpenKey;
  DateTime? _lastCallKitOpenKeyTime;

  String? _acceptedOrOpenedCallKey;
  DateTime? _acceptedOrOpenedCallKeyTime;

  Map<String, dynamic>? _pendingOffer;
  String? _pendingOfferCallerId;
  String? _pendingOfferConversationId;
  String? _pendingOfferCallId;

  SocketHandler? _incomingCallHandler;
  SocketHandler? _callOfferHandler;
  SocketHandler? _callEndHandler;
  SocketHandler? _callRejectHandler;
  SocketHandler? _callTimeoutHandler;

  GlobalSocketHandler? _globalConnectedHandler;
  GlobalSocketHandler? _globalIncomingCallHandler;
  GlobalSocketHandler? _globalCallCancelledHandler;

  /// Compatibility/control connector for /ws/call/<conversation>/.
  ///
  /// New outgoing/incoming CallScreen flows should let CallNotifier connect
  /// this socket. This method remains for native reject/control paths.
  static Future<void> connectCallSocket({
    required String url,
    required String currentUserId,
    String currentUserName = '',
    String currentUserAvatar = '',
  }) async {
    // Do not persist or print `url`; it contains the access token.
    await SocketService.instance.connect(url: url);

    GlobalCallHandler.instance.init(
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      currentUserAvatar: currentUserAvatar,
      forceRegister: false,
    );
  }

  Future<void> connectGlobalIncomingCallSocket({
    required String accessToken,
    required String currentUserId,
    required String currentUserName,
    required String currentUserAvatar,
    bool allowConnect = true,
  }) async {
    if (!allowConnect) {
      debugPrint('GLOBAL INCOMING SOCKET CONNECT DISABLED');
      return;
    }

    if (accessToken.trim().isEmpty) {
      debugPrint('GLOBAL INCOMING SOCKET ERROR: token empty');
      return;
    }

    if (currentUserId.trim().isEmpty) {
      debugPrint('GLOBAL INCOMING SOCKET ERROR: current user id empty');
      return;
    }

    _currentUserId = currentUserId.trim();
    _currentUserName = currentUserName.trim();
    _currentUserAvatar = currentUserAvatar.trim();

    await _saveCurrentUserToStorage(
      currentUserId: _currentUserId!,
      currentUserName: _currentUserName ?? '',
      currentUserAvatar: _currentUserAvatar ?? '',
    );

    _removeGlobalHandlers();

    _globalConnectedHandler = (data) async {
      debugPrint('### GLOBAL SOCKET CONNECTED EVENT ###');
    };

   _globalIncomingCallHandler = (data) async {
  debugPrint('### GLOBAL SOCKET incoming_call RECEIVED ###');

  await _loadCurrentUserFromStorage();

  final payload = _payloadFrom(data);

  await GlobalCallHandler.handleIncomingCall(payload);
};

    _globalCallCancelledHandler = (data) async {
      debugPrint('### GLOBAL SOCKET call_cancelled RECEIVED ###');

      final payload = _payloadFrom(data);
      _handleRemoteCallClosed(payload, reason: 'call_cancelled');
    };

    GlobalCallSocketService.instance.on(
      GlobalCallSocketEvents.connected,
      _globalConnectedHandler!,
    );

    GlobalCallSocketService.instance.on(
      GlobalCallSocketEvents.incomingCall,
      _globalIncomingCallHandler!,
    );

    GlobalCallSocketService.instance.on(
      GlobalCallSocketEvents.callCancelled,
      _globalCallCancelledHandler!,
    );

    final socket = GlobalCallSocketService.instance;

    // IMPORTANT:
    // Automatic reconnect must not reuse an old JWT forever. Before each
    // reconnect, rebuild the global-call websocket URL with a valid token.
    socket.setReconnectUrlProvider(() async {
      final freshUrl = await _buildFreshGlobalSocketUrl();
      return freshUrl;
    });

    final url = AppConfig.globalCallSocketUrl(token: accessToken.trim());
    await socket.connect(url: url);

    debugPrint('### GLOBAL INCOMING CALL SOCKET CONNECTED/READY ###');
    debugPrint('GLOBAL INCOMING CALL SOCKET ACTIVE');
    debugPrint('currentUserId: $_currentUserId');
  }

  bool _jwtNeedsRefresh(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;

      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(decoded);

      if (payload is! Map) return false;

      final expRaw = payload['exp'];
      final exp = expRaw is num
          ? expRaw.toInt()
          : int.tryParse(expRaw?.toString() ?? '');

      if (exp == null) return false;

      final expiry = DateTime.fromMillisecondsSinceEpoch(
        exp * 1000,
        isUtc: true,
      );

      return DateTime.now().toUtc().add(const Duration(minutes: 1)).isAfter(
            expiry,
          );
    } catch (_) {
      // If this is not a JWT, keep the current token and let the server decide.
      return false;
    }
  }

  Future<String?> _freshAccessToken() async {
    String token =
        (await ApiClient.storage.read(key: 'access'))?.trim() ?? '';

    if (token.isEmpty || _jwtNeedsRefresh(token)) {
      final refreshed = await ApiClient.refreshAccessToken();
      token = refreshed?.trim() ?? '';
    }

    if (token.isEmpty) {
      token =
          (await ApiClient.storage.read(key: 'access_token'))?.trim() ?? '';
    }

    if (token.isEmpty) {
      token = (await ApiClient.storage.read(key: 'token'))?.trim() ?? '';
    }

    return token.isEmpty ? null : token;
  }

  Future<String?> _buildFreshGlobalSocketUrl() async {
    try {
      final token = await _freshAccessToken();

      if (token == null || token.isEmpty) {
        debugPrint('GLOBAL SOCKET FRESH URL ERROR: no access token');
        return null;
      }

      return AppConfig.globalCallSocketUrl(token: token);
    } catch (e, st) {
      debugPrint('GLOBAL SOCKET FRESH URL ERROR: $e');
      debugPrint(st.toString());
      return null;
    }
  }

  Future<void> ensureGlobalIncomingCallSocketConnected() async {
    final socket = GlobalCallSocketService.instance;

    if (socket.isConnected || socket.isConnecting) {
      return;
    }

    if ((_currentUserId ?? '').trim().isEmpty) {
      await _loadCurrentUserFromStorage();
    }

    final currentUserId = (_currentUserId ?? '').trim();

    if (currentUserId.isEmpty) {
      debugPrint('GLOBAL SOCKET ENSURE ERROR: user id unavailable');
      return;
    }

    socket.setReconnectUrlProvider(() => _buildFreshGlobalSocketUrl());

    await socket.ensureConnected();
  }

  Future<void> _saveCurrentUserToStorage({
    required String currentUserId,
    required String currentUserName,
    required String currentUserAvatar,
  }) async {
    if (currentUserId.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', currentUserId);
    await prefs.setString('user_name', currentUserName);
    await prefs.setString('user_avatar', currentUserAvatar);

    debugPrint('GLOBAL USER SAVED TO STORAGE: $currentUserId');
  }

  Future<void> _loadCurrentUserFromStorage() async {
    final prefs = await SharedPreferences.getInstance();

    final prefUserId = prefs.getString('user_id') ?? '';
    final prefUserName = prefs.getString('user_name') ?? '';
    final prefUserAvatar = prefs.getString('user_avatar') ?? '';

    String secureUserId = '';
    String secureUserName = '';
    String secureUserAvatar = '';

    try {
      secureUserId =
          (await ApiClient.storage.read(key: 'user_id'))?.trim() ?? '';
      secureUserName =
          (await ApiClient.storage.read(key: 'full_name'))?.trim() ?? '';
      secureUserAvatar =
          (await ApiClient.storage.read(key: 'avatar_url'))?.trim() ??
              (await ApiClient.storage.read(key: 'image_url'))?.trim() ??
              '';
    } catch (e, st) {
      debugPrint('GLOBAL LOAD STORAGE ERROR: $e');
      debugPrint(st.toString());
    }

    _currentUserId = _firstNotEmpty([
      _currentUserId,
      secureUserId,
      prefUserId,
    ]);

    _currentUserName = _firstNotEmpty([
      _currentUserName,
      secureUserName,
      prefUserName,
    ]);

    _currentUserAvatar = _firstNotEmpty([
      _currentUserAvatar,
      secureUserAvatar,
      prefUserAvatar,
    ]);

    if ((_currentUserId ?? '').isNotEmpty) {
      await prefs.setString('user_id', _currentUserId ?? '');
      await prefs.setString('user_name', _currentUserName ?? '');
      await prefs.setString('user_avatar', _currentUserAvatar ?? '');
    }

    debugPrint('GLOBAL FINAL USER ID: ${_currentUserId ?? ''}');
  }

  String _firstNotEmpty(List<String?> values) {
    for (final value in values) {
      final clean = value?.trim() ?? '';
      if (clean.isNotEmpty && clean != 'null') return clean;
    }
    return '';
  }

  /// Stores current user identity only.
  ///
  /// GlobalCallHandler owns the persistent *global* incoming-call socket.
  /// CallNotifier exclusively owns handlers on the per-conversation signaling
  /// socket. This prevents duplicate call_offer/call_end processing.
  void init({
    required String currentUserId,
    required String currentUserName,
    required String currentUserAvatar,
    bool forceRegister = false,
  }) {
    _currentUserId = currentUserId.trim();
    _currentUserName = currentUserName.trim();
    _currentUserAvatar = currentUserAvatar.trim();

    _saveCurrentUserToStorage(
      currentUserId: _currentUserId ?? '',
      currentUserName: _currentUserName ?? '',
      currentUserAvatar: _currentUserAvatar ?? '',
    );

    // Remove handlers left behind by older app versions/hot reload.
    _removeOldHandlers();
    _registered = true;

    debugPrint('GLOBAL CALL HANDLER READY (global socket only)');
  }

  Future<void> openIncomingCallFromCallKit({
    required String callId,
    required String conversationId,
    required String callerId,
    required String callerName,
    required String callerAvatar,
    required bool isVideoCall,
  }) async {
    debugPrint('### CALLKIT ANSWER: FORCE OPEN CALLSCREEN ###');

    await _loadCurrentUserFromStorage();

    final currentId = _currentUserId ?? '';
    final currentName = _currentUserName ?? '';
    final currentAvatar = _currentUserAvatar ?? '';

    if (currentId.trim().isEmpty) return;
    if (conversationId.trim().isEmpty) return;
    if (callerId.trim().isEmpty) return;
    if (callerId.trim() == currentId.trim()) return;

    final cleanCallId = callId.trim().isNotEmpty ? callId.trim() : null;
    final cleanConversationId = conversationId.trim();
    final cleanCallerId = callerId.trim();

    final callKitKey = _buildIncomingKey(
      callerId: cleanCallerId,
      conversationId: cleanConversationId,
      callId: cleanCallId,
    );
    if (_isRecentDuplicateCallKitOpen(callKitKey)) {
      debugPrint('CALLKIT ANSWER OPEN SKIPPED DUPLICATE: $callKitKey');
      return;
    }

    if (_callScreenOpen || _openingIncomingScreen) {
      if (_isSameActiveIncomingCall(
        callerId: cleanCallerId,
        conversationId: cleanConversationId,
        callId: cleanCallId,
      )) {
        debugPrint('CALLKIT ANSWER OPEN SKIPPED: same call already open');
        return;
      }
    }

    forceResetCallUiLocks(reason: 'callkit_accept_force_open');

    _lastCallKitOpenKey = callKitKey;
    _lastCallKitOpenKeyTime = DateTime.now();
    _acceptedOrOpenedCallKey = callKitKey;
    _acceptedOrOpenedCallKeyTime = DateTime.now();

    _openingIncomingScreen = true;
    _callScreenOpen = true;
    _activeIncomingCallerId = cleanCallerId;
    _activeIncomingConversationId = cleanConversationId;
    _activeIncomingCallId = cleanCallId;
    _lastIncomingKeyTime = DateTime.now();

    final navigator = await _waitForNavigator();

    if (navigator == null) {
      markCallScreenClosed();
      return;
    }

    try {
      await navigator.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CallScreen(
            name: callerName.trim().isEmpty ? 'Incoming call' : callerName.trim(),
            avatarUrl: callerAvatar.trim(),
            isVideoCall: isVideoCall,
            chat: null,
            currentUserId: currentId.trim(),
            currentUserName: currentName.trim(),
            currentUserAvatar: currentAvatar.trim(),
            receiverId: cleanCallerId,
            isCaller: false,
            incomingOffer: null,
            conversationId: cleanConversationId,
            callId: cleanCallId,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('CALLKIT ANSWER OPEN CALLSCREEN ERROR: $e');
      debugPrint(st.toString());
      markCallScreenClosed();
    } finally {
      _openingIncomingScreen = false;
    }
  }

  Future<bool> _ensureControlSocket(String conversationId) async {
    final cleanConversationId = conversationId.trim();
    final parsedConversationId = int.tryParse(cleanConversationId);
    if (parsedConversationId == null) return false;

    if (SocketService.instance.isConnected &&
        SocketService.instance.activeConversationId == cleanConversationId) {
      return true;
    }

    // Never tear down another active call just to send a busy/reject event.
    if (SocketService.instance.isConnected &&
        SocketService.instance.activeConversationId != null &&
        SocketService.instance.activeConversationId != cleanConversationId) {
      return false;
    }

    String? token = await ApiClient.storage.read(key: 'access');
    if (token == null || token.trim().isEmpty) {
      token = await ApiClient.refreshAccessToken();
    }
    if (token == null || token.trim().isEmpty) return false;

    final url = AppConfig.callSocketUrl(
      conversationId: parsedConversationId,
      token: token.trim(),
    );

    await SocketService.instance.connect(url: url);
    return SocketService.instance.isConnected;
  }

  Future<void> rejectIncomingCallFromCallKit({
    required String callId,
    required String conversationId,
    required String callerId,
    required String reason,
  }) async {
    await _loadCurrentUserFromStorage();

    final currentId = _currentUserId?.trim() ?? '';
    final cleanCallId = callId.trim();
    final cleanConversationId = conversationId.trim();
    final cleanCallerId = callerId.trim();

    if (currentId.isEmpty ||
        cleanCallId.isEmpty ||
        cleanConversationId.isEmpty ||
        cleanCallerId.isEmpty) {
      return;
    }

    // Persist first so stale ringing records are not left behind even if
    // signaling cannot be established from a background/native action.
    try {
      await CallApi.reject(cleanCallId);
    } catch (e) {
      debugPrint('CALLKIT REJECT API ERROR: $e');
    }

    try {
      final connected = await _ensureControlSocket(cleanConversationId);
      if (connected) {
        SocketService.instance.emit(
          CallSocketEvents.callReject,
          <String, dynamic>{
            'from': currentId,
            'from_user': currentId,
            'reason': reason,
            'call_id': cleanCallId,
            'callId': cleanCallId,
            'conversation_id': cleanConversationId,
            'conversationId': cleanConversationId,
          },
          targetUser: cleanCallerId,
          conversationId: cleanConversationId,
          queueIfDisconnected: false,
        );
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      debugPrint('CALLKIT REJECT SIGNAL ERROR: $e');
    }

    clearPendingOffer();
    markCallScreenClosed();
  }

  static Future<void> handleIncomingCall(Map<String, dynamic> data) async {
    try {
      final h = GlobalCallHandler.instance;

      await h._loadCurrentUserFromStorage();

      final currentId = h._currentUserId ?? '';
      if (currentId.trim().isEmpty) {
        debugPrint('GLOBAL INCOMING CALL ERROR: current user id empty');
        return;
      }

      final callerId =
          data['caller_id']?.toString() ??
          data['callerId']?.toString() ??
          data['from_user']?.toString() ??
          data['from']?.toString() ??
          '';

      if (callerId.trim().isEmpty) {
        debugPrint('GLOBAL INCOMING CALL ERROR: caller id empty');
        return;
      }

      if (callerId.trim() == currentId.trim()) {
        debugPrint('GLOBAL INCOMING CALL IGNORED: caller is current user');
        return;
      }

      final conversationId =
          data['conversation_id']?.toString() ??
          data['conversationId']?.toString();

      final callId =
          data['call_id']?.toString() ?? data['callId']?.toString();

      final incomingKey = h._buildIncomingKey(
        callerId: callerId,
        conversationId: conversationId,
        callId: callId,
      );

      // GROUP CALLS MUST NEVER ENTER THE PRIVATE WebRTC SIGNALING FLOW.
      //
      // Some FCM/CallKit payloads omit the group markers. Verify the active
      // group call with the backend BEFORE falling through to private WebRTC.
      bool isGroupCall = h._isGroupCallPayload(data);

      if (!isGroupCall && conversationId != null) {
        final parsedConversationId = int.tryParse(conversationId.trim());

        if (parsedConversationId != null && parsedConversationId > 0) {
          try {
            final active = await CallApiService().getActiveGroupCall(
              parsedConversationId,
            );

            final activeCall = active.call;
            final sameCall = active.active &&
                activeCall != null &&
                activeCall.isActive &&
                (callId == null ||
                    callId.trim().isEmpty ||
                    activeCall.callId.toString() == callId.trim());

            if (sameCall) {
              isGroupCall = true;
              data['conversation_type'] = 'group';
              data['is_group_call'] = true;
              data['isGroupCall'] = true;

              debugPrint(
                'GLOBAL GROUP DETECTED BY BACKEND: '
                'conversation=$parsedConversationId '
                'call=${activeCall.callId}',
              );
            }
          } catch (e, st) {
            debugPrint('GLOBAL GROUP BACKEND CHECK ERROR: $e');
            debugPrint(st.toString());
          }
        }
      }

      if (isGroupCall) {
        final parsedConversationId =
            int.tryParse(conversationId?.trim() ?? '');

        if (parsedConversationId == null || parsedConversationId <= 0) {
          debugPrint('GROUP INCOMING CALL ERROR: invalid conversation id');
          return;
        }

        await h._openIncomingGroupCallScreen(
          data: data,
          callerId: callerId,
          conversationId: parsedConversationId,
          callId: callId,
          incomingKey: incomingKey,
        );
        return;
      }

      // If the real per-conversation signaling socket is already active for
      // this same call, this is only a duplicate global notification caused by
      // offer resend / call_ready. Ignore it without using a long-lived UI lock.
      final activeCallId = SocketService.instance.activeCallId?.trim() ?? '';
      final activeConversationId =
          SocketService.instance.activeConversationId?.trim() ?? '';
      final cleanIncomingCallId = callId?.trim() ?? '';
      final cleanIncomingConversationId = conversationId?.trim() ?? '';

      final sameActiveCall =
          cleanIncomingCallId.isNotEmpty && activeCallId == cleanIncomingCallId;
      final sameActiveConversation =
          SocketService.instance.isConnected &&
          cleanIncomingConversationId.isNotEmpty &&
          activeConversationId == cleanIncomingConversationId;

      if (sameActiveCall || sameActiveConversation) {
        debugPrint(
          'GLOBAL INCOMING CALL IGNORED: active call socket already owns this call',
        );
        return;
      }

      if (h._isAcceptedOrOpenedCall(incomingKey)) {
        debugPrint(
          'GLOBAL INCOMING CALL IGNORED: short duplicate guard $incomingKey',
        );
        return;
      }

      if (h._isSameActiveIncomingCall(
        callerId: callerId,
        conversationId: conversationId,
        callId: callId,
      )) {
        debugPrint('GLOBAL INCOMING CALL IGNORED: same call already open');
        return;
      }

      if (h._callScreenOpen || h._openingIncomingScreen) {
        if (h._isIncomingUiLockExpired()) {
          h.forceResetCallUiLocks(reason: 'stale_incoming_call_lock');
        } else {
          debugPrint('GLOBAL INCOMING CALL WHILE REAL BUSY');

          await h._sendBusyToCaller(
            currentId: currentId,
            callerId: callerId,
            conversationId: conversationId,
            callId: callId,
            reason: 'busy',
          );
          return;
        }
      }

      final isVideoCall =
          data['is_video_call'] == true ||
          data['isVideoCall'] == true ||
          data['is_video_call']?.toString() == 'true' ||
          data['isVideoCall']?.toString() == 'true' ||
          data['video']?.toString() == 'true' ||
          data['type']?.toString() == '1';

      final callerName =
          data['caller_name']?.toString() ??
          data['callerName']?.toString() ??
          data['nameCaller']?.toString() ??
          data['name']?.toString() ??
          'Incoming call';

      final callerAvatar =
          data['caller_avatar']?.toString() ??
          data['callerAvatar']?.toString() ??
          data['avatar']?.toString() ??
          '';

      final offerRaw = data['offer'];
      Map<String, dynamic>? offer;

      if (h._isValidWebRtcOffer(offerRaw)) {
        offer = Map<String, dynamic>.from(offerRaw as Map);
        h._savePendingOffer(
          callerId: callerId,
          conversationId: conversationId,
          callId: callId,
          offer: offer,
        );
      } else {
        offer = null;
        debugPrint('GLOBAL INCOMING CALL: no offer yet, opening anyway');
      }

      debugPrint('### GLOBAL INCOMING CALL RECEIVED ###');
      debugPrint('currentId: $currentId');
      debugPrint('callerId: $callerId');
      debugPrint('conversationId: ${conversationId ?? ''}');
      debugPrint('callId: ${callId ?? ''}');

      await h._openIncomingCallScreen(
        currentUserId: currentId,
        currentUserName: h._currentUserName ?? '',
        currentUserAvatar: h._currentUserAvatar ?? '',
        callerId: callerId,
        callerName: callerName,
        callerAvatar: callerAvatar,
        isVideoCall: isVideoCall,
        offer: offer,
        conversationId: conversationId,
        callId: callId,
      );
    } catch (e, st) {
      debugPrint('GLOBAL INCOMING CALL ERROR: $e');
      debugPrint(st.toString());
    }
  }

  bool _readBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final clean = value?.toString().trim().toLowerCase() ?? '';
    return clean == 'true' || clean == '1' || clean == 'yes';
  }

  bool _isGroupCallPayload(Map<String, dynamic> data) {
    final conversationType =
        (data['conversation_type'] ?? data['conversationType'])
            ?.toString()
            .trim()
            .toLowerCase();

    return _readBool(data['is_group_call']) ||
        _readBool(data['isGroupCall']) ||
        conversationType == 'group';
  }

  Future<Uri> _buildConversationRealtimeUri(int conversationId) async {
    final token = await _freshAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('No valid access token for conversation websocket.');
    }

    return Uri.parse(
      AppConfig.chatSocketUrl(
        conversationId: conversationId,
        token: token.trim(),
      ),
    );
  }

  Future<void> _openIncomingGroupCallScreen({
    required Map<String, dynamic> data,
    required String callerId,
    required int conversationId,
    required String? callId,
    required String incomingKey,
  }) async {
    if (_isRecentDuplicateIncoming(incomingKey)) {
      debugPrint('GROUP INCOMING SKIP DUPLICATE: $incomingKey');
      return;
    }

    if (_callScreenOpen || _openingIncomingScreen) {
      if (_isSameActiveIncomingCall(
        callerId: callerId,
        conversationId: conversationId.toString(),
        callId: callId,
      )) {
        debugPrint('GROUP INCOMING IGNORED: same call already open');
        return;
      }

      if (_isIncomingUiLockExpired()) {
        forceResetCallUiLocks(reason: 'stale_group_incoming_lock');
      } else {
        debugPrint('GROUP INCOMING BLOCKED: another call UI is active');
        return;
      }
    }

    final payloadData = Map<String, dynamic>.from(data);
    payloadData['conversation_id'] = conversationId;
    payloadData['conversationId'] = conversationId;
    payloadData['is_group_call'] = true;
    payloadData['isGroupCall'] = true;
    payloadData['conversation_type'] = 'group';

    final payload = IncomingCallPayload.fromMap(payloadData);

    if (!payload.isValid) {
      debugPrint('GROUP INCOMING ERROR: invalid IncomingCallPayload');
      return;
    }

    final realtime = ConversationRealtimeService(
      uriBuilder: _buildConversationRealtimeUri,
    );

    final controller = GroupCallController(
      conversationId: conversationId,
      api: CallApiService(),
      realtime: realtime,
    );

    _openingIncomingScreen = true;
    _callScreenOpen = true;
    _activeIncomingCallerId = callerId;
    _activeIncomingConversationId = conversationId.toString();
    _activeIncomingCallId = callId;
    _lastIncomingKey = incomingKey;
    _lastIncomingKeyTime = DateTime.now();

    final navigator = await _waitForNavigator();
    if (navigator == null) {
      controller.dispose();
      await realtime.dispose();
      markCallScreenClosed();
      return;
    }

    try {
      await realtime.connect(conversationId);

      final acceptedFromCallKit = _readBool(data['accepted_from_callkit']);

      if (acceptedFromCallKit) {
        debugPrint(
          'GROUP CALLKIT ACCEPT -> DIRECT LIVEKIT JOIN ' 
          'conversation=$conversationId call=${callId ?? ''}',
        );

        final activeCall = await controller.checkActiveCall(conversationId);
        if (activeCall == null) {
          throw StateError('No active group call found after CallKit accept.');
        }

        if (callId != null &&
            callId.trim().isNotEmpty &&
            activeCall.callId.toString() != callId.trim()) {
          throw StateError(
            'Active group call mismatch: expected $callId, got ${activeCall.callId}.',
          );
        }

        await controller.joinExistingCall(activeCall);

        if (!controller.connected) {
          throw StateError(
            controller.error ?? 'LiveKit did not connect after CallKit accept.',
          );
        }

        debugPrint(
          'GROUP CALLKIT ACCEPT -> LIVEKIT CONNECTED ' 
          'call=${activeCall.callId}',
        );

        await navigator.push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => GroupCallScreen(controller: controller),
          ),
        );
        return;
      }

      debugPrint(
        'GROUP INCOMING -> IncomingGroupCallScreen '
        'conversation=$conversationId call=${callId ?? ''}',
      );

      await navigator.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => IncomingGroupCallScreen(
            payload: payload,
            controller: controller,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('GROUP INCOMING OPEN ERROR: $e');
      debugPrint(st.toString());
    } finally {
      // IncomingGroupCallScreen replaces itself with GroupCallScreen on accept.
      // navigator.push() completes only after that whole route eventually closes,
      // so this is the correct owner for standalone incoming-call resources.
      controller.dispose();
      await realtime.dispose();
      markCallScreenClosed();
    }
  }

  Future<void> _sendBusyToCaller({
    required String currentId,
    required String callerId,
    required String? conversationId,
    required String? callId,
    required String reason,
  }) async {
    final cleanCallId = callId?.trim() ?? '';

    // The backend has no "busy" status action. Rejecting this second call is
    // the only authoritative terminal transition available today.
    if (cleanCallId.isNotEmpty) {
      try {
        await CallApi.reject(cleanCallId);
      } catch (e) {
        debugPrint('BUSY REJECT API ERROR: $e');
      }
    }

    // If this exact conversation socket is already connected, also send a
    // low-latency busy event. Never switch away from another active call.
    if (SocketService.instance.isConnected &&
        SocketService.instance.activeConversationId == conversationId) {
      SocketService.instance.emit(
        CallSocketEvents.callBusy,
        <String, dynamic>{
          'from': currentId,
          'from_user': currentId,
          'reason': reason,
          if (cleanCallId.isNotEmpty) 'call_id': cleanCallId,
          if (cleanCallId.isNotEmpty) 'callId': cleanCallId,
          if (conversationId != null) 'conversation_id': conversationId,
          if (conversationId != null) 'conversationId': conversationId,
        },
        targetUser: callerId,
        conversationId: conversationId,
        queueIfDisconnected: false,
      );
    }
  }

  Future<void> _openIncomingCallScreen({
    required String currentUserId,
    required String currentUserName,
    required String currentUserAvatar,
    required String callerId,
    required String callerName,
    required String callerAvatar,
    required bool isVideoCall,
    required Map<String, dynamic>? offer,
    required String? conversationId,
    required String? callId,
  }) async {
    final conv = conversationId?.trim() ?? '';
    if (conv.isEmpty) {
      debugPrint('GLOBAL OPEN INCOMING ERROR: conversationId empty');
      return;
    }

    final incomingKey = _buildIncomingKey(
      callerId: callerId,
      conversationId: conversationId,
      callId: callId,
    );

    if (_isRecentDuplicateIncoming(incomingKey)) {
      debugPrint('GLOBAL OPEN INCOMING SKIP DUPLICATE: $incomingKey');
      return;
    }

    if (_callScreenOpen || _openingIncomingScreen) {
      if (_isIncomingUiLockExpired()) {
        forceResetCallUiLocks(reason: 'expired_before_open_incoming');
      } else {
        debugPrint('GLOBAL OPEN INCOMING BLOCKED: already open/opening');
        return;
      }
    }

    _openingIncomingScreen = true;
    _callScreenOpen = true;
    _activeIncomingCallerId = callerId;
    _activeIncomingConversationId = conversationId;
    _activeIncomingCallId = callId;
    _lastIncomingKey = incomingKey;
    _lastIncomingKeyTime = DateTime.now();

    // Do NOT mark the call as accepted/opened here. This is only the ringing
    // screen. Marking it accepted here used to block later incoming calls for
    // up to 120 seconds and made killing/restarting the app appear necessary.

    final navigator = await _waitForNavigator();

    if (navigator == null) {
      markCallScreenClosed();
      return;
    }

    try {
      await navigator.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => IncomingCallScreen(
            currentUserId: currentUserId,
            currentUserName: currentUserName,
            currentUserAvatar: currentUserAvatar,
            callerId: callerId,
            callerName: callerName,
            callerAvatar: callerAvatar,
            isVideoCall: isVideoCall,
            offer: offer,
            conversationId: conversationId,
            callId: callId,
          ),
        ),
      );
    } finally {
      markCallScreenClosed();
    }
  }

  Future<NavigatorState?> _waitForNavigator() async {
    for (int i = 0; i < 40; i++) {
      final navigator = navigatorKey.currentState;
      if (navigator != null) return navigator;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return null;
  }

  Map<String, dynamic> _payloadFrom(Map<String, dynamic> data) {
    final rawPayload = data['payload'];

    if (rawPayload is Map<String, dynamic>) {
      return Map<String, dynamic>.from(rawPayload);
    }

    if (rawPayload is Map) {
      return Map<String, dynamic>.from(rawPayload);
    }

    return Map<String, dynamic>.from(data);
  }

  bool _isValidWebRtcOffer(dynamic offerRaw) {
    if (offerRaw is! Map) return false;

    final offer = Map<String, dynamic>.from(offerRaw);
    final type = offer['type']?.toString() ?? '';
    final sdp = offer['sdp']?.toString() ?? '';

    return type.trim().isNotEmpty && sdp.trim().isNotEmpty;
  }

  void _savePendingOffer({
    required String callerId,
    required String? conversationId,
    required String? callId,
    required Map<String, dynamic> offer,
  }) {
    _pendingOffer = Map<String, dynamic>.from(offer);
    _pendingOfferCallerId = callerId;
    _pendingOfferConversationId = conversationId;
    _pendingOfferCallId = callId;
  }

  Map<String, dynamic>? takePendingOffer({
    required String callerId,
    String? conversationId,
    String? callId,
  }) {
    if (_pendingOffer == null) return null;

    final sameCaller = _pendingOfferCallerId == callerId;

    final sameConversation =
        conversationId == null ||
        _pendingOfferConversationId == null ||
        _pendingOfferConversationId == conversationId;

    final sameCall =
        callId == null || _pendingOfferCallId == null || _pendingOfferCallId == callId;

    if (!sameCaller || !sameConversation || !sameCall) return null;

    final offer = Map<String, dynamic>.from(_pendingOffer!);
    clearPendingOffer();
    return offer;
  }

  void clearPendingOffer() {
    _pendingOffer = null;
    _pendingOfferCallerId = null;
    _pendingOfferConversationId = null;
    _pendingOfferCallId = null;
  }

  void _handleRemoteCallClosed(
    Map<String, dynamic> payload, {
    required String reason,
  }) {
    final fromUser =
        payload['from']?.toString() ??
        payload['from_user']?.toString() ??
        payload['caller_id']?.toString() ??
        payload['callerId']?.toString() ??
        '';

    final conversationId =
        payload['conversation_id']?.toString() ??
        payload['conversationId']?.toString();

    final callId =
        payload['call_id']?.toString() ?? payload['callId']?.toString();

    final sameCaller =
        fromUser.trim().isEmpty ||
        _activeIncomingCallerId == null ||
        _activeIncomingCallerId == fromUser;

    final sameConversation =
        conversationId == null ||
        _activeIncomingConversationId == null ||
        _activeIncomingConversationId == conversationId;

    final sameCall =
        callId == null ||
        callId.trim().isEmpty ||
        _activeIncomingCallId == null ||
        _activeIncomingCallId!.trim().isEmpty ||
        _activeIncomingCallId == callId;

    if (!sameCaller || !sameConversation || !sameCall) {
      debugPrint('GLOBAL REMOTE CLOSE IGNORED: not same call');
      return;
    }

    final navigator = navigatorKey.currentState;
    if (_callScreenOpen && navigator != null && navigator.canPop()) {
      navigator.pop();
    }

    markCallScreenClosed();
  }

  bool _isIncomingUiLockExpired() {
    if (!_callScreenOpen && !_openingIncomingScreen) return false;

    final t = _lastIncomingKeyTime;

    if (t == null) {
      return true;
    }

    return DateTime.now().difference(t).inSeconds > 15;
  }

  bool _isSameActiveIncomingCall({
    required String callerId,
    required String? conversationId,
    required String? callId,
  }) {
    if (!_callScreenOpen && !_openingIncomingScreen) return false;

    final sameCaller =
        _activeIncomingCallerId == null || _activeIncomingCallerId == callerId;

    final sameConversation =
        conversationId == null ||
        _activeIncomingConversationId == null ||
        _activeIncomingConversationId == conversationId;

    final sameCall =
        callId == null || _activeIncomingCallId == null || _activeIncomingCallId == callId;

    return sameCaller && sameConversation && sameCall;
  }

  String _buildIncomingKey({
    required String callerId,
    required String? conversationId,
    required String? callId,
  }) {
    if (callId != null && callId.trim().isNotEmpty) {
      return 'call_${callId.trim()}';
    }

    final conv = conversationId?.trim() ?? '';
    if (conv.isNotEmpty) return 'conversation_${conv}_caller_${callerId.trim()}';

    return 'caller_${callerId.trim()}';
  }


  bool _isAcceptedOrOpenedCall(String key) {
    if (key.trim().isEmpty) return false;
    if (_acceptedOrOpenedCallKey == null ||
        _acceptedOrOpenedCallKeyTime == null) {
      return false;
    }

    if (_acceptedOrOpenedCallKey != key) return false;

    // This is only a very short debounce for the native CallKit accept path.
    // The authoritative duplicate guard for an active call is the real
    // per-conversation SocketService activeCallId/activeConversationId above.
    return DateTime.now()
            .difference(_acceptedOrOpenedCallKeyTime!)
            .inSeconds <=
        8;
  }

  bool _isRecentDuplicateCallKitOpen(String key) {
    if (key.trim().isEmpty) return false;
    if (_lastCallKitOpenKey == null || _lastCallKitOpenKeyTime == null) {
      return false;
    }
    if (_lastCallKitOpenKey != key) return false;

    return DateTime.now().difference(_lastCallKitOpenKeyTime!).inSeconds <= 3;
  }

  bool _isRecentDuplicateIncoming(String incomingKey) {
    if (incomingKey.trim().isEmpty) return false;
    if (_lastIncomingKey == null || _lastIncomingKeyTime == null) return false;
    if (_lastIncomingKey != incomingKey) return false;

    return DateTime.now().difference(_lastIncomingKeyTime!).inSeconds <= 5;
  }

  void markCallScreenClosed() {
    _callScreenOpen = false;
    _openingIncomingScreen = false;
    _activeIncomingCallerId = null;
    _activeIncomingConversationId = null;
    _activeIncomingCallId = null;

    // A closed call screen must not leave a long-lived in-memory block.
    // Keep only the 5-second _lastIncomingKey debounce; clear accepted/opened
    // state so a legitimate next call can arrive without killing the app.
    _acceptedOrOpenedCallKey = null;
    _acceptedOrOpenedCallKeyTime = null;

    clearPendingOffer();
  }

  void forceResetCallUiLocks({String reason = 'manual_cleanup'}) {
    debugPrint('GLOBAL FORCE RESET CALL UI LOCKS: $reason');
    markCallScreenClosed();
    _lastIncomingKey = null;
    _lastIncomingKeyTime = null;
    _lastCallKitOpenKey = null;
    _lastCallKitOpenKeyTime = null;
    _acceptedOrOpenedCallKey = null;
    _acceptedOrOpenedCallKeyTime = null;
  }

  void _removeOldHandlers() {
    if (_incomingCallHandler != null) {
      SocketService.instance.off(CallSocketEvents.incomingCall, _incomingCallHandler);
      _incomingCallHandler = null;
    }

    if (_callOfferHandler != null) {
      SocketService.instance.off(CallSocketEvents.callOffer, _callOfferHandler);
      _callOfferHandler = null;
    }

    if (_callEndHandler != null) {
      SocketService.instance.off(CallSocketEvents.callEnd, _callEndHandler);
      _callEndHandler = null;
    }

    if (_callRejectHandler != null) {
      SocketService.instance.off(CallSocketEvents.callReject, _callRejectHandler);
      _callRejectHandler = null;
    }

    if (_callTimeoutHandler != null) {
      SocketService.instance.off(CallSocketEvents.callTimeout, _callTimeoutHandler);
      _callTimeoutHandler = null;
    }
  }

  void _removeGlobalHandlers() {
  if (_globalConnectedHandler != null) {
    GlobalCallSocketService.instance.off(
      GlobalCallSocketEvents.connected,
      _globalConnectedHandler!,
    );
    _globalConnectedHandler = null;
  }

  if (_globalIncomingCallHandler != null) {
    GlobalCallSocketService.instance.off(
      GlobalCallSocketEvents.incomingCall,
      _globalIncomingCallHandler!,
    );
    _globalIncomingCallHandler = null;
  }

  if (_globalCallCancelledHandler != null) {
    GlobalCallSocketService.instance.off(
      GlobalCallSocketEvents.callCancelled,
      _globalCallCancelledHandler!,
    );
    _globalCallCancelledHandler = null;
  }
}
  void dispose() {
    _registered = false;
    forceResetCallUiLocks(reason: 'dispose');

    _removeGlobalHandlers();
    _removeOldHandlers();

    final socket = GlobalCallSocketService.instance;
    socket.setReconnectUrlProvider(null);

    // Logout/user switch must stop the old user's persistent global socket.
    unawaited(
      socket.disconnect(
        clearHandlers: false,
        forgetUrl: true,
        manual: true,
      ),
    );

    _currentUserId = null;
    _currentUserName = null;
    _currentUserAvatar = null;
  }
}
