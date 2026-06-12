// lib/call_waiting.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/core/call/call_socket_service.dart';
import 'package:messaging_app/core/config/app_config.dart';

class CallWaitingScreen extends StatefulWidget {
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  final String callerId;
  final String callerName;
  final String callerAvatar;
  final bool isVideoCall;
  final String? conversationId;
  final String? callId;
  final ChatItem? chat;

  /*
    Kept only so old code that passes this parameter does not break.

    Correct background CallKit accept flow:

    CallKit accept
    -> open CallWaitingScreen
    -> CallWaitingScreen connects socket directly
    -> CallWaitingScreen sends call_ready
    -> caller resends call_offer
    -> CallWaitingScreen receives call_offer
    -> opens CallScreen
    -> CallScreen sends call_answer
  */
  final bool emitAcceptOnOpen;

  const CallWaitingScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    required this.callerId,
    required this.callerName,
    required this.callerAvatar,
    required this.isVideoCall,
    this.conversationId,
    this.callId,
    this.chat,
    this.emitAcceptOnOpen = false,
  });

  @override
  State<CallWaitingScreen> createState() => _CallWaitingScreenState();
}

class _CallWaitingScreenState extends State<CallWaitingScreen> {
  Timer? _timeoutTimer;

  bool _openedCall = false;
  bool _sentReady = false;
  bool _connectingSocket = false;
  bool _navigatingToCall = false;

  String _resolvedCurrentUserId = '';
  String _resolvedCurrentUserName = '';
  String _resolvedCurrentUserAvatar = '';

  SocketHandler? _callOfferHandler;
  SocketHandler? _callEndHandler;
  SocketHandler? _callRejectHandler;
  SocketHandler? _callBusyHandler;
  SocketHandler? _callTimeoutHandler;

  String get _conversationId {
    return widget.conversationId?.toString().trim() ?? '';
  }

  String get _callId {
    return widget.callId?.toString().trim() ?? '';
  }

  void _log(String message) {
    debugPrint('========== CALL WAITING DEBUG ==========');
    debugPrint(message);
    debugPrint('========================================');
  }

  void _logSmall(String message) {
    debugPrint('[CALL WAITING] $message');
  }

  void _logState(String place) {
    debugPrint('========== CALL WAITING STATE: $place ==========');
    debugPrint('mounted: $mounted');
    debugPrint('openedCall: $_openedCall');
    debugPrint('sentReady: $_sentReady');
    debugPrint('connectingSocket: $_connectingSocket');
    debugPrint('navigatingToCall: $_navigatingToCall');
    debugPrint('SocketService.isConnected: ${SocketService.instance.isConnected}');
    debugPrint('widget.currentUserId: ${widget.currentUserId}');
    debugPrint('resolvedCurrentUserId: $_resolvedCurrentUserId');
    debugPrint('callerId: ${widget.callerId}');
    debugPrint('callerName: ${widget.callerName}');
    debugPrint('conversationId: $_conversationId');
    debugPrint('callId: $_callId');
    debugPrint('isVideoCall: ${widget.isVideoCall}');
    debugPrint('emitAcceptOnOpen: ${widget.emitAcceptOnOpen}');
    debugPrint('chatId: ${widget.chat?.id}');
    debugPrint('================================================');
  }

  @override
  void initState() {
    super.initState();

    debugPrint('');
    debugPrint('################################################');
    debugPrint('### CALL WAITING SCREEN OPENED');
    debugPrint('################################################');
    _logState('initState start');

    _registerSocketHandlers();

    Future.microtask(() async {
      _logSmall('Future.microtask started -> _connectSocketAndSendReady()');
      await _connectSocketAndSendReady();
    });

    if (widget.emitAcceptOnOpen) {
      _logSmall(
        'emitAcceptOnOpen=true but ignored. This screen only sends call_ready.',
      );
    }

    _timeoutTimer = Timer(const Duration(seconds: 45), () {
      _logSmall('45 second timeout timer fired');

      if (!mounted) {
        _logSmall('timeout ignored because widget is not mounted');
        return;
      }

      if (_openedCall) {
        _logSmall('timeout ignored because call already opened');
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call connection timeout')),
      );

      _cancel(reason: 'timeout_while_connecting');
    });

    _logSmall('timeout timer registered for 45 seconds');
  }

  @override
  void dispose() {
    debugPrint('');
    debugPrint('################################################');
    debugPrint('### CALL WAITING SCREEN DISPOSE');
    debugPrint('################################################');
    _logState('dispose start');

    _timeoutTimer?.cancel();
    _removeSocketHandlers();

    super.dispose();
  }

  void _removeSocketHandlers() {
    _logSmall('Removing socket handlers');

    if (_callOfferHandler != null) {
      SocketService.instance.off(
        CallSocketEvents.callOffer,
        _callOfferHandler,
      );
      _callOfferHandler = null;
      _logSmall('Removed handler: ${CallSocketEvents.callOffer}');
    }

    if (_callEndHandler != null) {
      SocketService.instance.off(
        CallSocketEvents.callEnd,
        _callEndHandler,
      );
      _callEndHandler = null;
      _logSmall('Removed handler: ${CallSocketEvents.callEnd}');
    }

    if (_callRejectHandler != null) {
      SocketService.instance.off(
        CallSocketEvents.callReject,
        _callRejectHandler,
      );
      _callRejectHandler = null;
      _logSmall('Removed handler: ${CallSocketEvents.callReject}');
    }

    if (_callBusyHandler != null) {
      SocketService.instance.off(
        CallSocketEvents.callBusy,
        _callBusyHandler,
      );
      _callBusyHandler = null;
      _logSmall('Removed handler: ${CallSocketEvents.callBusy}');
    }

    if (_callTimeoutHandler != null) {
      SocketService.instance.off(
        CallSocketEvents.callTimeout,
        _callTimeoutHandler,
      );
      _callTimeoutHandler = null;
      _logSmall('Removed handler: ${CallSocketEvents.callTimeout}');
    }
  }

  Future<bool> _connectSocket() async {
    _logState('_connectSocket called');

    if (_connectingSocket) {
      _logSmall(
        '_connectSocket ignored because already connecting. Current connected=${SocketService.instance.isConnected}',
      );
      return SocketService.instance.isConnected;
    }

    final conversationId = _conversationId;

    if (conversationId.isEmpty) {
      _log('CALL WAITING SOCKET ERROR: conversationId empty');
      return false;
    }

    final parsedConversationId = int.tryParse(conversationId);

    if (parsedConversationId == null) {
      _log(
        'CALL WAITING SOCKET ERROR: conversationId is not number: $conversationId',
      );
      return false;
    }

    _connectingSocket = true;

    try {
      _logSmall('Reading access token from secure storage...');
      String? accessToken = await ApiClient.storage.read(key: 'access');

      debugPrint('========== CALL WAITING TOKEN DEBUG ==========');
      debugPrint('access exists: ${accessToken != null}');
      debugPrint('access empty: ${accessToken == null || accessToken.trim().isEmpty}');
      debugPrint('access length: ${accessToken?.length ?? 0}');
      debugPrint('==============================================');

      if (accessToken == null || accessToken.trim().isEmpty) {
        _logSmall('Access token empty. Trying ApiClient.refreshAccessToken()...');
        accessToken = await ApiClient.refreshAccessToken();

        debugPrint('========== CALL WAITING REFRESH TOKEN RESULT ==========');
        debugPrint('new access exists: ${accessToken != null}');
        debugPrint('new access empty: ${accessToken == null || accessToken.trim().isEmpty}');
        debugPrint('new access length: ${accessToken?.length ?? 0}');
        debugPrint('=======================================================');
      }

      if (accessToken == null || accessToken.trim().isEmpty) {
        _log('CALL WAITING SOCKET ERROR: access token still empty');
        return false;
      }

      _logSmall('Reading stored user data...');
      final storedUserId =
          (await ApiClient.storage.read(key: 'user_id'))?.trim() ?? '';

      final storedUserName =
          (await ApiClient.storage.read(key: 'full_name'))?.trim() ?? '';

      final storedUserAvatar =
          (await ApiClient.storage.read(key: 'avatar_url'))?.trim() ??
              (await ApiClient.storage.read(key: 'image_url'))?.trim() ??
              '';

      debugPrint('========== CALL WAITING STORED USER DEBUG ==========');
      debugPrint('storedUserId: $storedUserId');
      debugPrint('storedUserName: $storedUserName');
      debugPrint('storedUserAvatar: $storedUserAvatar');
      debugPrint('widget.currentUserId: ${widget.currentUserId}');
      debugPrint('widget.currentUserName: ${widget.currentUserName}');
      debugPrint('widget.currentUserAvatar: ${widget.currentUserAvatar}');
      debugPrint('===================================================');

      _resolvedCurrentUserId = widget.currentUserId.trim().isNotEmpty
          ? widget.currentUserId.trim()
          : storedUserId;

      _resolvedCurrentUserName = widget.currentUserName.trim().isNotEmpty
          ? widget.currentUserName.trim()
          : storedUserName;

      _resolvedCurrentUserAvatar = widget.currentUserAvatar.trim().isNotEmpty
          ? widget.currentUserAvatar.trim()
          : storedUserAvatar;

      if (_resolvedCurrentUserId.isEmpty) {
        _log('CALL WAITING SOCKET ERROR: currentUserId empty after resolving');
        return false;
      }

      final url = AppConfig.callSocketUrl(
        conversationId: parsedConversationId,
        token: accessToken.trim(),
      );

      debugPrint('');
      debugPrint('========== CALL WAITING SOCKET CONNECT DEBUG ==========');
      debugPrint('conversationId raw: ${widget.conversationId}');
      debugPrint('conversationId resolved: $conversationId');
      debugPrint('parsedConversationId: $parsedConversationId');
      debugPrint('callId: $_callId');
      debugPrint('currentUserId: $_resolvedCurrentUserId');
      debugPrint('currentUserName: $_resolvedCurrentUserName');
      debugPrint('currentUserAvatar: $_resolvedCurrentUserAvatar');
      debugPrint('callerId: ${widget.callerId}');
      debugPrint('callerName: ${widget.callerName}');
      debugPrint('callerAvatar: ${widget.callerAvatar}');
      debugPrint('isVideoCall: ${widget.isVideoCall}');
      debugPrint('AppConfig.wsBaseUrl: ${AppConfig.wsBaseUrl}');
      debugPrint('CALL WAITING SOCKET URL: $url');
      debugPrint('SocketService.isConnected BEFORE connect: ${SocketService.instance.isConnected}');
      debugPrint('======================================================');
      debugPrint('');

      /*
        Important:
        Do NOT use GlobalCallHandler.connectCallSocket() here.

        That can register global handlers again and open another
        IncomingCallScreen after this waiting screen.
      */
      _logSmall('Calling SocketService.instance.connect(url: url)...');
      await SocketService.instance.connect(url: url);

      _logSmall('SocketService.connect() returned. Waiting 300ms...');
      await Future.delayed(const Duration(milliseconds: 300));

      debugPrint('========== CALL WAITING SOCKET CONNECT RESULT ==========');
      debugPrint('SocketService.isConnected AFTER connect: ${SocketService.instance.isConnected}');
      debugPrint('=======================================================');

      if (!SocketService.instance.isConnected) {
        _log('CALL WAITING SOCKET ERROR: SocketService.isConnected false after connect');
        return false;
      }

      _log('CALL WAITING SOCKET CONNECTED SUCCESSFULLY');
      return true;
    } catch (e, st) {
      debugPrint('');
      debugPrint('!!!!!!!!!! CALL WAITING SOCKET CONNECT EXCEPTION !!!!!!!!!!');
      debugPrint('error: $e');
      debugPrint('stack: $st');
      debugPrint('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
      debugPrint('');
      return false;
    } finally {
      _connectingSocket = false;
      _logState('_connectSocket finally');
    }
  }

  Future<void> _connectSocketAndSendReady() async {
    _logState('_connectSocketAndSendReady start');

    final connected = await _connectSocket();

    if (!mounted) {
      _logSmall('_connectSocketAndSendReady stopped: widget unmounted');
      return;
    }

    if (!connected) {
      _log('CALL WAITING: socket not connected, cannot send call_ready');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not connect call socket')),
      );

      return;
    }

    if (_sentReady) {
      _logSmall('call_ready already sent. Skipping duplicate emit.');
      return;
    }

    _sentReady = true;

    final payload = {
      'from': _resolvedCurrentUserId,
      'from_user': _resolvedCurrentUserId,
      if (_callId.isNotEmpty) 'call_id': _callId,
      if (_callId.isNotEmpty) 'callId': _callId,
      'conversation_id': _conversationId,
      'conversationId': _conversationId,
      'is_video_call': widget.isVideoCall.toString(),
      'isVideoCall': widget.isVideoCall.toString(),
      'accepted_from_call_waiting': 'true',
    };

    debugPrint('');
    debugPrint('========== CALL WAITING EMIT call_ready ==========');
    debugPrint('event: ${CallSocketEvents.callReady}');
    debugPrint('payload: $payload');
    debugPrint('targetUser: ${widget.callerId}');
    debugPrint('conversationId: $_conversationId');
    debugPrint('queueIfDisconnected: true');
    debugPrint('SocketService.isConnected before emit: ${SocketService.instance.isConnected}');
    debugPrint('=================================================');
    debugPrint('');

    SocketService.instance.emit(
      CallSocketEvents.callReady,
      payload,
      targetUser: widget.callerId,
      conversationId: _conversationId,
      queueIfDisconnected: true,
    );

    _log('CALL WAITING SENT call_ready');
  }

  void _registerSocketHandlers() {
    _logSmall('Registering socket handlers...');

    _callOfferHandler = (data) async {
      debugPrint('');
      debugPrint('################################################');
      debugPrint('### CALL WAITING RECEIVED call_offer');
      debugPrint('################################################');
      debugPrint('raw data: $data');
      _logState('call_offer handler start');

      if (!mounted) {
        _logSmall('Ignoring call_offer because widget is unmounted');
        return;
      }

      if (_openedCall) {
        _logSmall('Ignoring call_offer because _openedCall=true');
        return;
      }

      if (_navigatingToCall) {
        _logSmall('Ignoring call_offer because _navigatingToCall=true');
        return;
      }

      final rawPayload = data['payload'];

      debugPrint('========== CALL WAITING OFFER PAYLOAD DEBUG ==========');
      debugPrint('rawPayload runtimeType: ${rawPayload.runtimeType}');
      debugPrint('rawPayload: $rawPayload');
      debugPrint('=====================================================');

      if (rawPayload is! Map) {
        _log('CALL WAITING INVALID PAYLOAD: payload is not Map. data=$data');
        return;
      }

      final payload = Map<String, dynamic>.from(rawPayload);

      final from = payload['from']?.toString() ??
          payload['from_user']?.toString() ??
          payload['caller_id']?.toString() ??
          payload['callerId']?.toString() ??
          payload['sender_id']?.toString() ??
          '';

      debugPrint('========== CALL WAITING OFFER FROM DEBUG ==========');
      debugPrint('from resolved: $from');
      debugPrint('expected callerId: ${widget.callerId}');
      debugPrint('==================================================');

      if (from.trim().isNotEmpty && from.trim() != widget.callerId.trim()) {
        _log('CALL WAITING IGNORED OFFER FROM DIFFERENT USER: $from');
        return;
      }

      final payloadConversationId = payload['conversation_id']?.toString() ??
          payload['conversationId']?.toString() ??
          '';

      debugPrint('========== CALL WAITING OFFER CONVERSATION DEBUG ==========');
      debugPrint('payloadConversationId: $payloadConversationId');
      debugPrint('screen conversationId: $_conversationId');
      debugPrint('==========================================================');

      if (payloadConversationId.trim().isNotEmpty &&
          _conversationId.isNotEmpty &&
          payloadConversationId.trim() != _conversationId) {
        _log(
          'CALL WAITING IGNORED OFFER FROM DIFFERENT CONVERSATION: $payloadConversationId',
        );
        return;
      }

      Map<String, dynamic>? offer;

      final rawOffer = payload['offer'];

      debugPrint('========== CALL WAITING RAW OFFER DEBUG ==========');
      debugPrint('rawOffer runtimeType: ${rawOffer.runtimeType}');
      debugPrint('rawOffer: $rawOffer');
      debugPrint('payload direct type: ${payload['type']}');
      debugPrint('payload direct sdp exists: ${payload['sdp'] != null}');
      debugPrint('payload direct sdp length: ${payload['sdp']?.toString().length ?? 0}');
      debugPrint('=================================================');

      if (rawOffer is Map<String, dynamic>) {
        offer = Map<String, dynamic>.from(rawOffer);
      } else if (rawOffer is Map) {
        offer = Map<String, dynamic>.from(rawOffer);
      } else {
        final directType = payload['type']?.toString() ?? '';
        final directSdp = payload['sdp']?.toString() ?? '';

        if (directType.trim().isNotEmpty && directSdp.trim().isNotEmpty) {
          offer = {
            'type': directType,
            'sdp': directSdp,
          };
        }
      }

      if (offer == null) {
        _log('CALL WAITING OFFER MISSING SDP. payload=$payload');
        return;
      }

      final type = offer['type']?.toString() ?? '';
      final sdp = offer['sdp']?.toString() ?? '';

      debugPrint('========== CALL WAITING FINAL OFFER DEBUG ==========');
      debugPrint('offer type: $type');
      debugPrint('offer sdp empty: ${sdp.trim().isEmpty}');
      debugPrint('offer sdp length: ${sdp.length}');
      debugPrint('===================================================');

      if (type.trim().isEmpty || sdp.trim().isEmpty) {
        _log('CALL WAITING INVALID SDP OFFER: $offer');
        return;
      }

      _openedCall = true;
      _navigatingToCall = true;
      _timeoutTimer?.cancel();

      _logSmall('Valid offer received. Preparing to open CallScreen...');

      final callId = payload['call_id']?.toString() ??
          payload['callId']?.toString() ??
          widget.callId;

      final conversationId = payload['conversation_id']?.toString() ??
          payload['conversationId']?.toString() ??
          widget.conversationId;

      final callerName = payload['callerName']?.toString() ??
          payload['caller_name']?.toString() ??
          widget.callerName;

      final callerAvatar = payload['callerAvatar']?.toString() ??
          payload['caller_avatar']?.toString() ??
          widget.callerAvatar;

      final isVideoCall = payload['isVideoCall'] == true ||
          payload['is_video_call'] == true ||
          payload['isVideoCall']?.toString() == 'true' ||
          payload['is_video_call']?.toString() == 'true' ||
          widget.isVideoCall;

      debugPrint('========== CALL WAITING NAVIGATION DATA ==========');
      debugPrint('callId: $callId');
      debugPrint('conversationId: $conversationId');
      debugPrint('callerName: $callerName');
      debugPrint('callerAvatar: $callerAvatar');
      debugPrint('isVideoCall: $isVideoCall');
      debugPrint('currentUserId: ${_resolvedCurrentUserId.isNotEmpty ? _resolvedCurrentUserId : widget.currentUserId}');
      debugPrint('currentUserName: ${_resolvedCurrentUserName.isNotEmpty ? _resolvedCurrentUserName : widget.currentUserName}');
      debugPrint('currentUserAvatar: ${_resolvedCurrentUserAvatar.isNotEmpty ? _resolvedCurrentUserAvatar : widget.currentUserAvatar}');
      debugPrint('receiverId/callerId: ${widget.callerId}');
      debugPrint('=================================================');

      if ((callId ?? '').trim().isNotEmpty) {
        try {
          _logSmall('Ending CallKit call with id: ${callId!.trim()}');
          await FlutterCallkitIncoming.endCall(callId.trim());
          _logSmall('CallKit endCall success');
        } catch (e, st) {
          debugPrint('!!!!!!!!!! CALL WAITING END CALLKIT ERROR !!!!!!!!!!');
          debugPrint('error: $e');
          debugPrint('stack: $st');
          debugPrint('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        }
      } else {
        _logSmall('Skipping CallKit endCall because callId is empty');
      }

      if (!mounted) {
        _logSmall('Not opening CallScreen because widget unmounted after CallKit end');
        return;
      }

      /*
        Remove waiting handlers before opening CallScreen.
        CallScreen should manage its own WebRTC handlers.
      */
      _removeSocketHandlers();

      _log('CALL WAITING OPENING CallScreen NOW');

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            name: callerName,
            avatarUrl: callerAvatar,
            isVideoCall: isVideoCall,
            chat: widget.chat,
            currentUserId: _resolvedCurrentUserId.isNotEmpty
                ? _resolvedCurrentUserId
                : widget.currentUserId,
            currentUserName: _resolvedCurrentUserName.isNotEmpty
                ? _resolvedCurrentUserName
                : widget.currentUserName,
            currentUserAvatar: _resolvedCurrentUserAvatar.isNotEmpty
                ? _resolvedCurrentUserAvatar
                : widget.currentUserAvatar,
            receiverId: widget.callerId,
            isCaller: false,
            incomingOffer: offer!,
            conversationId: conversationId ?? widget.chat?.id,
            callId: (callId ?? '').trim().isNotEmpty ? callId : null,
          ),
        ),
      );
    };

    _callEndHandler = (data) async {
      debugPrint('========== CALL WAITING RECEIVED call_end ==========');
      debugPrint('data: $data');
      debugPrint('===================================================');

      if (!mounted || _openedCall) return;

      _timeoutTimer?.cancel();
      Navigator.of(context).maybePop();
    };

    _callRejectHandler = (data) async {
      debugPrint('========== CALL WAITING RECEIVED call_reject ==========');
      debugPrint('data: $data');
      debugPrint('======================================================');

      if (!mounted || _openedCall) return;

      _timeoutTimer?.cancel();
      Navigator.of(context).maybePop();
    };

    _callBusyHandler = (data) async {
      debugPrint('========== CALL WAITING RECEIVED call_busy ==========');
      debugPrint('data: $data');
      debugPrint('====================================================');

      if (!mounted || _openedCall) return;

      _timeoutTimer?.cancel();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User is busy')),
      );

      Navigator.of(context).maybePop();
    };

    _callTimeoutHandler = (data) async {
      debugPrint('========== CALL WAITING RECEIVED call_timeout ==========');
      debugPrint('data: $data');
      debugPrint('=======================================================');

      if (!mounted || _openedCall) return;

      _timeoutTimer?.cancel();
      Navigator.of(context).maybePop();
    };

    SocketService.instance.on(
      CallSocketEvents.callOffer,
      _callOfferHandler!,
    );
    _logSmall('Registered handler: ${CallSocketEvents.callOffer}');

    SocketService.instance.on(
      CallSocketEvents.callEnd,
      _callEndHandler!,
    );
    _logSmall('Registered handler: ${CallSocketEvents.callEnd}');

    SocketService.instance.on(
      CallSocketEvents.callReject,
      _callRejectHandler!,
    );
    _logSmall('Registered handler: ${CallSocketEvents.callReject}');

    SocketService.instance.on(
      CallSocketEvents.callBusy,
      _callBusyHandler!,
    );
    _logSmall('Registered handler: ${CallSocketEvents.callBusy}');

    SocketService.instance.on(
      CallSocketEvents.callTimeout,
      _callTimeoutHandler!,
    );
    _logSmall('Registered handler: ${CallSocketEvents.callTimeout}');

    _logSmall('All CallWaitingScreen socket handlers registered');
  }

  Future<void> _cancel({String reason = 'cancelled_while_connecting'}) async {
    debugPrint('');
    debugPrint('################################################');
    debugPrint('### CALL WAITING CANCEL CLICKED');
    debugPrint('################################################');
    debugPrint('reason: $reason');
    _logState('_cancel start');

    final connected = await _connectSocket();

    if (!connected) {
      _logSmall('CALL WAITING CANCEL WARNING: socket not connected');
    }

    final currentUserId = _resolvedCurrentUserId.isNotEmpty
        ? _resolvedCurrentUserId
        : widget.currentUserId;

    final payload = {
      'from': currentUserId,
      'from_user': currentUserId,
      'reason': reason,
      if (_callId.isNotEmpty) 'call_id': _callId,
      if (_callId.isNotEmpty) 'callId': _callId,
      if (_conversationId.isNotEmpty) 'conversation_id': _conversationId,
      if (_conversationId.isNotEmpty) 'conversationId': _conversationId,
    };

    debugPrint('========== CALL WAITING EMIT call_reject ==========');
    debugPrint('event: ${CallSocketEvents.callReject}');
    debugPrint('payload: $payload');
    debugPrint('targetUser: ${widget.callerId}');
    debugPrint('conversationId: $_conversationId');
    debugPrint('queueIfDisconnected: true');
    debugPrint('SocketService.isConnected before emit: ${SocketService.instance.isConnected}');
    debugPrint('==================================================');

    SocketService.instance.emit(
      CallSocketEvents.callReject,
      payload,
      targetUser: widget.callerId,
      conversationId: _conversationId,
      queueIfDisconnected: true,
    );

    if (_callId.isNotEmpty) {
      try {
        _logSmall('Ending CallKit call from cancel. callId=$_callId');
        await FlutterCallkitIncoming.endCall(_callId);
        _logSmall('CallKit endCall from cancel success');
      } catch (e, st) {
        debugPrint('!!!!!!!!!! CALL WAITING CANCEL END CALLKIT ERROR !!!!!!!!!!');
        debugPrint('error: $e');
        debugPrint('stack: $st');
        debugPrint('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
      }
    } else {
      _logSmall('Skipping CallKit endCall from cancel because callId empty');
    }

    if (mounted) {
      _logSmall('Popping CallWaitingScreen after cancel');
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.callerName.trim().isEmpty
        ? 'Incoming call'
        : widget.callerName.trim();

    final avatar = widget.callerAvatar.trim();
    final hasAvatar = avatar.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 62,
                backgroundColor: const Color(0xFF1F2937),
                backgroundImage: hasAvatar ? NetworkImage(avatar) : null,
                onBackgroundImageError: hasAvatar
                    ? (Object error, StackTrace? stackTrace) {
                        debugPrint('CALL WAITING AVATAR ERROR: $error');
                      }
                    : null,
                child: !hasAvatar
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 24),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.isVideoCall
                    ? 'Connecting video call...'
                    : 'Connecting call...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),
              const CircularProgressIndicator(color: Colors.white),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 46),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => _cancel(),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF3B30),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call_end_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}