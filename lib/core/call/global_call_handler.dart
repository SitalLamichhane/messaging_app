// lib/core/call/global_call_handler.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:messaging_app/incoming_call_screen.dart';
import 'package:messaging_app/call_waiting.dart';
import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/core/config/app_config.dart';
import 'package:messaging_app/core/call/call_socket_service.dart';
import 'package:messaging_app/core/call/global_call_socket_service.dart';

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

  /*
    Old compatibility method.

    This connects the conversation call socket:
      /ws/call/<conversation_id>/

    Do NOT use this for the global incoming socket.
  */
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

  /*
    Connect once after login.

    This keeps /ws/global-call/ alive while app is open.
    It receives incoming_call anywhere: chat list, profile, settings, inside chat.
  */
  Future<void> connectGlobalIncomingCallSocket({
    required String accessToken,
    required String currentUserId,
    required String currentUserName,
    required String currentUserAvatar,
  }) async {
    debugPrint('');
    debugPrint('################################################');
    debugPrint('### CONNECT GLOBAL INCOMING CALL SOCKET');
    debugPrint('################################################');
    debugPrint('currentUserId: $currentUserId');
    debugPrint('currentUserName: $currentUserName');
    debugPrint('token exists: ${accessToken.trim().isNotEmpty}');
    debugPrint('already connected: ${GlobalCallSocketService.instance.isConnected}');
    debugPrint('current url: ${GlobalCallSocketService.instance.currentUrl ?? ""}');
    debugPrint('################################################');

    if (accessToken.trim().isEmpty) {
      debugPrint('GLOBAL INCOMING SOCKET ERROR: access token empty');
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
      debugPrint('');
      debugPrint('################################################');
      debugPrint('### GLOBAL SOCKET CONNECTED EVENT RECEIVED');
      debugPrint('################################################');
      debugPrint('data: $data');
      debugPrint('################################################');
    };

    _globalIncomingCallHandler = (data) async {
      debugPrint('');
      debugPrint('################################################');
      debugPrint('### GLOBAL SOCKET incoming_call RECEIVED');
      debugPrint('################################################');
      debugPrint('raw data: $data');

      await _loadCurrentUserFromStorage();

      final payload = _payloadFrom(data);

      debugPrint('payload: $payload');
      debugPrint('################################################');

      await GlobalCallHandler.handleIncomingCall(payload);
    };

    _globalCallCancelledHandler = (data) async {
      debugPrint('');
      debugPrint('################################################');
      debugPrint('### GLOBAL SOCKET call_cancelled RECEIVED');
      debugPrint('################################################');
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

    debugPrint('');
    debugPrint('################################################');
    debugPrint('### GLOBAL INCOMING CALL SOCKET CONNECTED/READY');
    debugPrint('################################################');
    debugPrint('url: $url');
    debugPrint('currentUserId: $_currentUserId');
    debugPrint('################################################');
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
    debugPrint('========== GLOBAL LOAD CURRENT USER ==========');

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
      debugPrint('GLOBAL LOAD SECURE STORAGE ERROR: $e');
      debugPrint(st.toString());
    }

    debugPrint('prefUserId: $prefUserId');
    debugPrint('prefUserName: $prefUserName');
    debugPrint('secureUserId: $secureUserId');
    debugPrint('secureUserName: $secureUserName');

    final finalUserId = _firstNotEmpty([
      _currentUserId,
      secureUserId,
      prefUserId,
    ]);

    final finalUserName = _firstNotEmpty([
      _currentUserName,
      secureUserName,
      prefUserName,
    ]);

    final finalUserAvatar = _firstNotEmpty([
      _currentUserAvatar,
      secureUserAvatar,
      prefUserAvatar,
    ]);

    _currentUserId = finalUserId;
    _currentUserName = finalUserName;
    _currentUserAvatar = finalUserAvatar;

    if (finalUserId.isNotEmpty) {
      await prefs.setString('user_id', finalUserId);
      await prefs.setString('user_name', finalUserName);
      await prefs.setString('user_avatar', finalUserAvatar);
    }

    debugPrint('GLOBAL FINAL USER ID: ${_currentUserId ?? ''}');
    debugPrint('GLOBAL FINAL USER NAME: ${_currentUserName ?? ''}');
    debugPrint('=============================================');
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

  /*
    Registers conversation-call socket handlers.
    This is for /ws/call/<conversation_id>/ only.
  */
  void init({
    required String currentUserId,
    required String currentUserName,
    required String currentUserAvatar,
    bool forceRegister = false,
  }) {
    _currentUserId = currentUserId;
    _currentUserName = currentUserName;
    _currentUserAvatar = currentUserAvatar;

    _saveCurrentUserToStorage(
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      currentUserAvatar: currentUserAvatar,
    );

    if (_registered && !forceRegister) {
      debugPrint('GLOBAL CALL HANDLER ALREADY REGISTERED');
      return;
    }

    _removeOldHandlers();

    _incomingCallHandler = (data) async {
      final rawData = Map<String, dynamic>.from(data);
      final payload = _payloadFrom(rawData);

      debugPrint('CONVERSATION SOCKET incoming_call DATA: $rawData');
      debugPrint('CONVERSATION SOCKET incoming_call PAYLOAD: $payload');

      await handleIncomingCall(payload);
    };

    _callOfferHandler = (data) async {
      await _loadCurrentUserFromStorage();

      final currentId = _currentUserId ?? '';

      if (currentId.trim().isEmpty) {
        debugPrint('CALL OFFER ERROR: current user id empty');
        return;
      }

      final rawData = Map<String, dynamic>.from(data);
      final payload = _payloadFrom(rawData);

      final callerId =
          payload['from']?.toString() ??
          payload['from_user']?.toString() ??
          payload['caller_id']?.toString() ??
          payload['callerId']?.toString() ??
          rawData['from_user']?.toString() ??
          rawData['from']?.toString() ??
          '';

      final conversationId =
          payload['conversationId']?.toString() ??
          payload['conversation_id']?.toString() ??
          rawData['conversationId']?.toString() ??
          rawData['conversation_id']?.toString();

      final callId =
          payload['call_id']?.toString() ??
          payload['callId']?.toString() ??
          rawData['call_id']?.toString() ??
          rawData['callId']?.toString();

      final offerRaw = payload['offer'];

      if (callerId.trim().isEmpty) {
        debugPrint('CALL OFFER ERROR: caller id missing');
        return;
      }

      if (callerId == currentId) {
        debugPrint('CALL OFFER IGNORED: caller is current user');
        return;
      }

      if (!_isValidWebRtcOffer(offerRaw)) {
        debugPrint('CALL OFFER ERROR: valid WebRTC offer missing');
        debugPrint('CALL OFFER RAW OFFER: $offerRaw');
        return;
      }

      final offer = Map<String, dynamic>.from(offerRaw as Map);

      if (_isSameActiveIncomingCall(
        callerId: callerId,
        conversationId: conversationId,
        callId: callId,
      )) {
        _savePendingOffer(
          callerId: callerId,
          conversationId: conversationId,
          callId: callId,
          offer: offer,
        );

        debugPrint('CALL OFFER STORED: same incoming screen already open');
        return;
      }

      if (_callScreenOpen || _openingIncomingScreen) {
        _sendBusyToCaller(
          currentId: currentId,
          callerId: callerId,
          conversationId: conversationId,
          callId: callId,
          reason: 'busy',
        );
        return;
      }

      final isVideoCall =
          payload['isVideoCall'] == true ||
          payload['is_video_call'] == true ||
          payload['isVideoCall']?.toString() == 'true' ||
          payload['is_video_call']?.toString() == 'true';

      final callerName =
          payload['callerName']?.toString() ??
          payload['caller_name']?.toString() ??
          'Unknown';

      final callerAvatar =
          payload['callerAvatar']?.toString() ??
          payload['caller_avatar']?.toString() ??
          '';

      _savePendingOffer(
        callerId: callerId,
        conversationId: conversationId,
        callId: callId,
        offer: offer,
      );

      debugPrint('OPENING INCOMING CALL SCREEN FROM SOCKET OFFER');
      debugPrint('CURRENT USER ID: $currentId');
      debugPrint('CALLER ID: $callerId');
      debugPrint('CALL ID: ${callId ?? ''}');
      debugPrint('CONVERSATION ID: ${conversationId ?? ''}');
      debugPrint('IS VIDEO CALL: $isVideoCall');

      await _openIncomingCallScreen(
        currentUserId: currentId,
        currentUserName: _currentUserName ?? '',
        currentUserAvatar: _currentUserAvatar ?? '',
        callerId: callerId,
        callerName: callerName,
        callerAvatar: callerAvatar,
        isVideoCall: isVideoCall,
        offer: offer,
        conversationId: conversationId,
        callId: callId,
      );
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

    SocketService.instance.on(
      CallSocketEvents.incomingCall,
      _incomingCallHandler!,
    );

    SocketService.instance.on(
      CallSocketEvents.callOffer,
      _callOfferHandler!,
    );

    SocketService.instance.on(
      CallSocketEvents.callEnd,
      _callEndHandler!,
    );

    SocketService.instance.on(
      CallSocketEvents.callReject,
      _callRejectHandler!,
    );

    SocketService.instance.on(
      CallSocketEvents.callTimeout,
      _callTimeoutHandler!,
    );

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
    debugPrint('');
    debugPrint('################################################');
    debugPrint('### GLOBAL CALLKIT ANSWER RECEIVED');
    debugPrint('### OPEN CALL SCREEN DIRECTLY');
    debugPrint('################################################');
    debugPrint('callId: $callId');
    debugPrint('conversationId: $conversationId');
    debugPrint('callerId: $callerId');
    debugPrint('callerName: $callerName');
    debugPrint('callerAvatar: $callerAvatar');
    debugPrint('isVideoCall: $isVideoCall');
    debugPrint('################################################');

    await _loadCurrentUserFromStorage();

    final currentId = _currentUserId ?? '';
    final currentName = _currentUserName ?? '';
    final currentAvatar = _currentUserAvatar ?? '';

    if (currentId.trim().isEmpty) {
      debugPrint('CALLKIT ANSWER ERROR: current user id empty');
      return;
    }

    if (conversationId.trim().isEmpty) {
      debugPrint('CALLKIT ANSWER ERROR: conversation id empty');
      return;
    }

    if (callerId.trim().isEmpty) {
      debugPrint('CALLKIT ANSWER ERROR: caller id empty');
      return;
    }

    if (callerId.trim() == currentId.trim()) {
      debugPrint('CALLKIT ANSWER IGNORED: caller is current user');
      return;
    }

    final cleanCallId = callId.trim().isNotEmpty ? callId.trim() : null;
    final cleanConversationId = conversationId.trim();
    final cleanCallerId = callerId.trim();

    if (_isSameActiveIncomingCall(
      callerId: cleanCallerId,
      conversationId: cleanConversationId,
      callId: cleanCallId,
    )) {
      debugPrint('CALLKIT ANSWER IGNORED: same call already open/opening');
      return;
    }

    if (_callScreenOpen || _openingIncomingScreen) {
      debugPrint(
        'CALLKIT ANSWER IGNORED: another call screen already open/opening',
      );
      return;
    }

    _openingIncomingScreen = true;
    _callScreenOpen = true;
    _activeIncomingCallerId = cleanCallerId;
    _activeIncomingConversationId = cleanConversationId;
    _activeIncomingCallId = cleanCallId;
    _lastIncomingKey = _buildIncomingKey(
      callerId: cleanCallerId,
      conversationId: cleanConversationId,
      callId: cleanCallId,
    );
    _lastIncomingKeyTime = DateTime.now();

    final navigator = await _waitForNavigator();

    if (navigator == null) {
      debugPrint('CALLKIT ANSWER ERROR: navigator null after wait');
      markCallScreenClosed();
      return;
    }

    try {
      debugPrint('CALLKIT ANSWER: pushing CallScreen directly');

      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CallScreen(
            name: callerName.trim().isEmpty
                ? 'Incoming call'
                : callerName.trim(),
            avatarUrl: callerAvatar.trim(),
            isVideoCall: isVideoCall,
            chat: null,
            currentUserId: currentId.trim(),
            currentUserName: currentName.trim(),
            currentUserAvatar: currentAvatar.trim(),
            receiverId: cleanCallerId,
            isCaller: false,

            /*
              Killed/background CallKit ANSWER:
              - Open CallScreen directly.
              - SDP offer may not exist yet.
              - CallScreen connects /ws/call/<conversation_id>/.
              - CallProvider waits for call_offer.
              - CallScreen sends call_ready after provider handlers are ready.
            */
            incomingOffer: null,

            conversationId: cleanConversationId,
            callId: cleanCallId,
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (e, st) {
      debugPrint('CALLKIT ANSWER OPEN CALL SCREEN ERROR: $e');
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

    if (currentId.trim().isEmpty) {
      debugPrint('CALLKIT REJECT ERROR: current user id empty');
      return;
    }

    if (callerId.trim().isEmpty) {
      debugPrint('CALLKIT REJECT ERROR: caller id empty');
      return;
    }

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
      await GlobalCallHandler.instance._loadCurrentUserFromStorage();

      final currentId = GlobalCallHandler.instance._currentUserId ?? '';

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

      if (callerId == currentId) {
        debugPrint('GLOBAL INCOMING CALL IGNORED: caller is current user');
        return;
      }

      final conversationId =
          data['conversation_id']?.toString() ??
          data['conversationId']?.toString();

      final callId =
          data['call_id']?.toString() ??
          data['callId']?.toString();

      if (GlobalCallHandler.instance._isSameActiveIncomingCall(
        callerId: callerId,
        conversationId: conversationId,
        callId: callId,
      )) {
        debugPrint('GLOBAL INCOMING CALL IGNORED: same screen already open');
        return;
      }

      if (GlobalCallHandler.instance._callScreenOpen ||
          GlobalCallHandler.instance._openingIncomingScreen) {
        debugPrint('GLOBAL INCOMING CALL WHILE BUSY');

        GlobalCallHandler.instance._sendBusyToCaller(
          currentId: currentId,
          callerId: callerId,
          conversationId: conversationId,
          callId: callId,
          reason: 'busy',
        );

        return;
      }

      final isVideoCall =
          data['is_video_call'] == true ||
          data['isVideoCall'] == true ||
          data['is_video_call']?.toString() == 'true' ||
          data['isVideoCall']?.toString() == 'true';

      final callerName =
          data['caller_name']?.toString() ??
          data['callerName']?.toString() ??
          'Incoming call';

      final callerAvatar =
          data['caller_avatar']?.toString() ??
          data['callerAvatar']?.toString() ??
          '';

      final offerRaw = data['offer'];

      Map<String, dynamic>? offer;

      if (GlobalCallHandler.instance._isValidWebRtcOffer(offerRaw)) {
        offer = Map<String, dynamic>.from(offerRaw as Map);

        GlobalCallHandler.instance._savePendingOffer(
          callerId: callerId,
          conversationId: conversationId,
          callId: callId,
          offer: offer,
        );
      } else {
        offer = null;
        debugPrint(
          'GLOBAL INCOMING CALL: no WebRTC offer yet. Opening screen anyway.',
        );
        debugPrint('GLOBAL INCOMING CALL RAW OFFER: $offerRaw');
      }

      debugPrint('GLOBAL INCOMING CALL RECEIVED');
      debugPrint('CURRENT USER ID: $currentId');
      debugPrint('CALLER ID: $callerId');
      debugPrint('CALL ID: ${callId ?? ''}');
      debugPrint('CONVERSATION ID: ${conversationId ?? ''}');
      debugPrint('IS VIDEO CALL: $isVideoCall');

      await GlobalCallHandler.instance._openIncomingCallScreen(
        currentUserId: currentId,
        currentUserName: GlobalCallHandler.instance._currentUserName ?? '',
        currentUserAvatar: GlobalCallHandler.instance._currentUserAvatar ?? '',
        callerId: callerId,
        callerName: callerName,
        callerAvatar: callerAvatar,
        isVideoCall: isVideoCall,
        offer: offer,
        conversationId: conversationId,
        callId: callId,
      );
    } catch (e, stack) {
      debugPrint('GLOBAL INCOMING CALL ERROR: $e');
      debugPrint(stack.toString());
    }
  }

  void _sendBusyToCaller({
    required String currentId,
    required String callerId,
    required String? conversationId,
    required String? callId,
    required String reason,
  }) {
    debugPrint('========== GLOBAL SEND BUSY ==========');
    debugPrint('from: $currentId');
    debugPrint('to: $callerId');
    debugPrint('conversationId: ${conversationId ?? ''}');
    debugPrint('callId: ${callId ?? ''}');
    debugPrint('reason: $reason');
    debugPrint('SocketService connected: ${SocketService.instance.isConnected}');
    debugPrint('=====================================');

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

  Future<void> _openCallWaitingScreen({
    required String currentUserId,
    required String currentUserName,
    required String currentUserAvatar,
    required String callerId,
    required String callerName,
    required String callerAvatar,
    required bool isVideoCall,
    required String conversationId,
    required String? callId,
  }) async {
    final incomingKey = _buildIncomingKey(
      callerId: callerId,
      conversationId: conversationId,
      callId: callId,
    );

    debugPrint('========== GLOBAL OPEN CALL WAITING ==========');
    debugPrint('incomingKey: $incomingKey');
    debugPrint('callScreenOpen: $_callScreenOpen');
    debugPrint('openingIncomingScreen: $_openingIncomingScreen');
    debugPrint('currentUserId: $currentUserId');
    debugPrint('callerId: $callerId');
    debugPrint('conversationId: $conversationId');
    debugPrint('callId: ${callId ?? ''}');
    debugPrint('=============================================');

    if (_isRecentDuplicateIncoming(incomingKey)) {
      debugPrint('GLOBAL OPEN CALL WAITING SKIP DUPLICATE KEY: $incomingKey');
      return;
    }

    if (_callScreenOpen || _openingIncomingScreen) {
      debugPrint('GLOBAL OPEN CALL WAITING: call screen already open/opening');
      return;
    }

    _openingIncomingScreen = true;
    _callScreenOpen = true;
    _activeIncomingCallerId = callerId;
    _activeIncomingConversationId = conversationId;
    _activeIncomingCallId = callId;
    _lastIncomingKey = incomingKey;
    _lastIncomingKeyTime = DateTime.now();

    final navigator = await _waitForNavigator();

    if (navigator == null) {
      debugPrint('GLOBAL OPEN CALL WAITING ERROR: navigator null after wait');
      markCallScreenClosed();
      return;
    }

    try {
      debugPrint('');
      debugPrint('################################################');
      debugPrint('### GLOBAL PUSHING CallWaitingScreen NOW');
      debugPrint('################################################');

      await navigator.push(
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
      );
    } finally {
      markCallScreenClosed();
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
    final incomingKey = _buildIncomingKey(
      callerId: callerId,
      conversationId: conversationId,
      callId: callId,
    );

    if (_isRecentDuplicateIncoming(incomingKey)) {
      debugPrint('GLOBAL OPEN INCOMING SKIP DUPLICATE KEY: $incomingKey');
      return;
    }

    if (_callScreenOpen || _openingIncomingScreen) {
      debugPrint('GLOBAL CALL HANDLER: incoming screen already opening/open');
      return;
    }

    _openingIncomingScreen = true;
    _callScreenOpen = true;
    _activeIncomingCallerId = callerId;
    _activeIncomingConversationId = conversationId;
    _activeIncomingCallId = callId;
    _lastIncomingKey = incomingKey;
    _lastIncomingKeyTime = DateTime.now();

    final navigator = await _waitForNavigator();

    if (navigator == null) {
      debugPrint('GLOBAL CALL HANDLER ERROR: navigator null after wait');
      markCallScreenClosed();
      return;
    }

    try {
      debugPrint('');
      debugPrint('################################################');
      debugPrint('### GLOBAL PUSHING IncomingCallScreen NOW');
      debugPrint('################################################');

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
    for (int i = 0; i < 30; i++) {
      final navigator = navigatorKey.currentState;

      if (navigator != null) {
        return navigator;
      }

      await Future.delayed(const Duration(milliseconds: 250));
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
    if (offerRaw is! Map) {
      return false;
    }

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

    debugPrint('PENDING OFFER SAVED');
    debugPrint('PENDING OFFER CALLER ID: $callerId');
    debugPrint('PENDING OFFER CONVERSATION ID: ${conversationId ?? ''}');
    debugPrint('PENDING OFFER CALL ID: ${callId ?? ''}');
  }

  Map<String, dynamic>? takePendingOffer({
    required String callerId,
    String? conversationId,
    String? callId,
  }) {
    if (_pendingOffer == null) {
      debugPrint('PENDING OFFER NOT FOUND');
      return null;
    }

    final sameCaller = _pendingOfferCallerId == callerId;

    final sameConversation =
        conversationId == null ||
        _pendingOfferConversationId == null ||
        _pendingOfferConversationId == conversationId;

    final sameCall =
        callId == null ||
        _pendingOfferCallId == null ||
        _pendingOfferCallId == callId;

    if (!sameCaller || !sameConversation || !sameCall) {
      debugPrint('PENDING OFFER NOT MATCHED');
      debugPrint('EXPECTED CALLER: $_pendingOfferCallerId GOT: $callerId');
      debugPrint(
        'EXPECTED CONVERSATION: $_pendingOfferConversationId GOT: $conversationId',
      );
      debugPrint('EXPECTED CALL ID: $_pendingOfferCallId GOT: $callId');
      return null;
    }

    final offer = Map<String, dynamic>.from(_pendingOffer!);

    _pendingOffer = null;
    _pendingOfferCallerId = null;
    _pendingOfferConversationId = null;
    _pendingOfferCallId = null;

    debugPrint('PENDING OFFER TAKEN');

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
        payload['call_id']?.toString() ??
        payload['callId']?.toString();

    final sameCaller =
        fromUser.trim().isEmpty ||
        _activeIncomingCallerId == null ||
        _activeIncomingCallerId == fromUser;

    final sameConversation =
        conversationId == null ||
        _activeIncomingConversationId == null ||
        _activeIncomingConversationId == conversationId;

    final sameCall =
        callId != null &&
        callId.trim().isNotEmpty &&
        _activeIncomingCallId != null &&
        _activeIncomingCallId!.trim().isNotEmpty &&
        _activeIncomingCallId == callId;

    if (!sameCaller || !sameConversation || !sameCall) {
      debugPrint('GLOBAL REMOTE CLOSE IGNORED: not same call');
      debugPrint('REASON: $reason');
      debugPrint('FROM USER: $fromUser');
      debugPrint('CONVERSATION ID: ${conversationId ?? ''}');
      debugPrint('CALL ID: ${callId ?? ''}');
      debugPrint('ACTIVE CALL ID: ${_activeIncomingCallId ?? ''}');
      return;
    }

    debugPrint('GLOBAL CALL CLOSED BY REMOTE: $reason');

    clearPendingOffer();

    final navigator = navigatorKey.currentState;

    if (_callScreenOpen && navigator != null && navigator.canPop()) {
      navigator.pop();
    }

    markCallScreenClosed();
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
        callId == null ||
        _activeIncomingCallId == null ||
        _activeIncomingCallId == callId;

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

    if (conv.isNotEmpty) {
      return 'conversation_${conv}_caller_${callerId.trim()}';
    }

    return 'caller_${callerId.trim()}';
  }

  bool _isRecentDuplicateIncoming(String incomingKey) {
    if (incomingKey.trim().isEmpty) return false;
    if (_lastIncomingKey == null) return false;
    if (_lastIncomingKeyTime == null) return false;
    if (_lastIncomingKey != incomingKey) return false;

    final diff = DateTime.now().difference(_lastIncomingKeyTime!).inSeconds;

    return diff <= 30;
  }

  void markCallScreenClosed() {
    _callScreenOpen = false;
    _openingIncomingScreen = false;
    _activeIncomingCallerId = null;
    _activeIncomingConversationId = null;
    _activeIncomingCallId = null;
    _lastIncomingKey = null;
    _lastIncomingKeyTime = null;
  }

  void _removeOldHandlers() {
    if (_incomingCallHandler != null) {
      SocketService.instance.off(
        CallSocketEvents.incomingCall,
        _incomingCallHandler,
      );
      _incomingCallHandler = null;
    }

    if (_callOfferHandler != null) {
      SocketService.instance.off(
        CallSocketEvents.callOffer,
        _callOfferHandler,
      );
      _callOfferHandler = null;
    }

    if (_callEndHandler != null) {
      SocketService.instance.off(
        CallSocketEvents.callEnd,
        _callEndHandler,
      );
      _callEndHandler = null;
    }

    if (_callRejectHandler != null) {
      SocketService.instance.off(
        CallSocketEvents.callReject,
        _callRejectHandler,
      );
      _callRejectHandler = null;
    }

    if (_callTimeoutHandler != null) {
      SocketService.instance.off(
        CallSocketEvents.callTimeout,
        _callTimeoutHandler,
      );
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
    _callScreenOpen = false;
    _openingIncomingScreen = false;
    _currentUserId = null;
    _currentUserName = null;
    _currentUserAvatar = null;
    _activeIncomingCallerId = null;
    _activeIncomingConversationId = null;
    _activeIncomingCallId = null;
    _lastIncomingKey = null;
    _lastIncomingKeyTime = null;

    clearPendingOffer();
    _removeGlobalHandlers();
    _removeOldHandlers();
  }
}