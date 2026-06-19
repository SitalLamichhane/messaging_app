// lib/core/call/global_call_handler.dart

import 'package:flutter/material.dart';
import 'package:hiddenly/core/call/call_notification.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiddenly/incoming_call_screen.dart';
import 'package:hiddenly/call_screen.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/core/config/app_config.dart';
import 'package:hiddenly/core/call/call_socket_service.dart';
import 'package:hiddenly/core/call/global_call_socket_service.dart';

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

  static Future<void> connectCallSocket({
    required String url,
    required String currentUserId,
    String currentUserName = '',
    String currentUserAvatar = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('call_ws_url', url);

    debugPrint('GLOBAL SAVED CALL WS URL: $url');

    await SocketService.instance.connect(url: url);

    GlobalCallHandler.instance.init(
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      currentUserAvatar: currentUserAvatar,
      forceRegister: true,
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
      debugPrint('data: $data');
    };

   _globalIncomingCallHandler = (data) async {
  debugPrint('### GLOBAL SOCKET incoming_call RECEIVED ###');

  await _loadCurrentUserFromStorage();

  final payload = _payloadFrom(data);

  await GlobalCallHandler.handleIncomingCall(payload);
};

    _globalCallCancelledHandler = (data) async {
      debugPrint('### GLOBAL SOCKET call_cancelled RECEIVED ###');
      debugPrint('raw data: $data');

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

    final url = AppConfig.globalCallSocketUrl(token: accessToken.trim());
    await GlobalCallSocketService.instance.connect(url: url);

    debugPrint('### GLOBAL INCOMING CALL SOCKET CONNECTED/READY ###');
    debugPrint('url: $url');
    debugPrint('currentUserId: $_currentUserId');
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

    if (_registered && !forceRegister) {
      debugPrint('GLOBAL CALL HANDLER ALREADY REGISTERED');
      return;
    }

    _removeOldHandlers();

    _incomingCallHandler = (data) async {
  final payload = _payloadFrom(Map<String, dynamic>.from(data));

  debugPrint(
    'CONVERSATION SOCKET incoming_call IGNORED: global socket handles incoming UI',
  );
  debugPrint('payload: $payload');

  return;
};

    _callOfferHandler = (data) async {
      await _loadCurrentUserFromStorage();

      final currentId = _currentUserId ?? '';
      if (currentId.trim().isEmpty) return;

      final rawData = Map<String, dynamic>.from(data);
      final payload = _payloadFrom(rawData);

      final callerId =
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

      final offerRaw = payload['offer'];

      if (callerId.trim().isEmpty) return;
      if (callerId.trim() == currentId.trim()) return;

      if (!_isValidWebRtcOffer(offerRaw)) {
        debugPrint('CALL OFFER ERROR: valid offer missing');
        return;
      }

      final offer = Map<String, dynamic>.from(offerRaw as Map);

      /*
        IMPORTANT DOUBLE-SCREEN FIX:
        The global incoming_call socket is responsible for opening
        IncomingCallScreen. The conversation call_offer socket must NOT
        open another UI screen, otherwise receiver sees duplicate incoming
        screens or IncomingCallScreen + CallScreen.

        Here we only save the WebRTC offer. IncomingCallScreen/CallScreen
        can take this pending offer when user accepts.
      */
      _savePendingOffer(
        callerId: callerId,
        conversationId: conversationId,
        callId: callId,
        offer: offer,
      );

      debugPrint('CALL OFFER SAVED ONLY - UI OPEN BLOCKED TO PREVENT DOUBLE SCREEN');
      debugPrint('callerId: $callerId');
      debugPrint('conversationId: ${conversationId ?? ''}');
      debugPrint('callId: ${callId ?? ''}');

      return;
    };

    _callEndHandler = (data) async {
      final payload = _payloadFrom(Map<String, dynamic>.from(data));
      _handleRemoteCallClosed(payload, reason: 'call_end');
    };

    _callRejectHandler = (data) async {
      final payload = _payloadFrom(Map<String, dynamic>.from(data));
      _handleRemoteCallClosed(payload, reason: 'call_reject');
    };

    _callTimeoutHandler = (data) async {
      final payload = _payloadFrom(Map<String, dynamic>.from(data));
      _handleRemoteCallClosed(payload, reason: 'call_timeout');
    };

    SocketService.instance.on(CallSocketEvents.incomingCall, _incomingCallHandler!);
    SocketService.instance.on(CallSocketEvents.callOffer, _callOfferHandler!);
    SocketService.instance.on(CallSocketEvents.callEnd, _callEndHandler!);
    SocketService.instance.on(CallSocketEvents.callReject, _callRejectHandler!);
    SocketService.instance.on(CallSocketEvents.callTimeout, _callTimeoutHandler!);

    _registered = true;
    debugPrint('GLOBAL CALL HANDLER REGISTERED FOR CONVERSATION SOCKET');
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

  Future<void> rejectIncomingCallFromCallKit({
    required String callId,
    required String conversationId,
    required String callerId,
    required String reason,
  }) async {
    await _loadCurrentUserFromStorage();

    final currentId = _currentUserId ?? '';
    if (currentId.trim().isEmpty) return;

    SocketService.instance.emit(
      CallSocketEvents.callReject,
      {
        'from': currentId,
        'from_user': currentId,
        'reason': reason,
        'call_id': callId,
        'callId': callId,
        'conversation_id': conversationId,
        'conversationId': conversationId,
      },
      targetUser: callerId,
      conversationId: conversationId,
      queueIfDisconnected: true,
    );

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

      if (h._isAcceptedOrOpenedCall(incomingKey)) {
        debugPrint('GLOBAL INCOMING CALL IGNORED: already accepted/opened $incomingKey');
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

          h._sendBusyToCaller(
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

  void _sendBusyToCaller({
    required String currentId,
    required String callerId,
    required String? conversationId,
    required String? callId,
    required String reason,
  }) {
    SocketService.instance.emit(
      CallSocketEvents.callBusy,
      {
        'from': currentId,
        'from_user': currentId,
        'reason': reason,
        if (callId != null) 'call_id': callId,
        if (callId != null) 'callId': callId,
        if (conversationId != null) 'conversation_id': conversationId,
        if (conversationId != null) 'conversationId': conversationId,
      },
      targetUser: callerId,
      conversationId: conversationId,
      queueIfDisconnected: true,
    );
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
    _acceptedOrOpenedCallKey = incomingKey;
    _acceptedOrOpenedCallKeyTime = DateTime.now();

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

    // Keep a longer guard window because backend/global socket can resend
    // incoming_call after receiver already accepted and CallScreen is open.
    return DateTime.now()
            .difference(_acceptedOrOpenedCallKeyTime!)
            .inSeconds <=
        120;
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

    // Do NOT clear _lastIncomingKey or _acceptedOrOpenedCallKey here.
    // Backend/global socket can resend the same incoming_call after accept.
    // Keeping these keys briefly prevents the second incoming screen.
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
    _currentUserId = null;
    _currentUserName = null;
    _currentUserAvatar = null;
    _removeGlobalHandlers();
    _removeOldHandlers();
  }
}
