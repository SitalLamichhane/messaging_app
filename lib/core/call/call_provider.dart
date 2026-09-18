// lib/core/call/call_provider.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/core/config/app_config.dart';
import 'package:hiddenly/core/call/call_api.dart';
import 'package:hiddenly/core/call/call_socket_service.dart';
import 'package:hiddenly/core/call/call_sound_service.dart';
import 'package:hiddenly/core/call/call_state.dart';
import 'package:hiddenly/core/call/global_call_handler.dart';
import 'package:hiddenly/core/call/call_notification.dart';
import 'package:hiddenly/core/call/webrct_servide.dart';


class CallStartConflictException implements Exception {
  final String message;
  final String? existingCallId;
  final String? existingStatus;

  const CallStartConflictException(
    this.message, {
    this.existingCallId,
    this.existingStatus,
  });

  @override
  String toString() => message;
}

final callProvider = StateNotifierProvider<CallNotifier, CallState>((ref) {
  final notifier = CallNotifier();

  ref.onDispose(() {
    notifier.disposeCall();
  });

  return notifier;
});

class CallNotifier extends StateNotifier<CallState> {
  CallNotifier() : super(const CallState()) {
    _onCallOffer = _handleCallOffer;
    _onCallAnswer = _handleCallAnswer;
    _onIceCandidate = _handleIceCandidate;
    _onRenegotiateOffer = _handleRenegotiateOffer;
    _onRenegotiateAnswer = _handleRenegotiateAnswer;
    _onVideoToggle = _handleVideoToggle;
    _onVideoUpgradeRejected = _handleVideoUpgradeRejected;
    _onCallReject = _handleCallReject;
    _onCallEnd = _handleCallEnd;
    _onCallLeave = _handleCallLeave;
    _onCallBusy = _handleCallBusy;
    _onCallTimeout = _handleCallTimeout;
  }

  final WebRTCService webrtc = WebRTCService();

  Timer? _durationTimer;
  Timer? _timeoutTimer;

  bool _disposed = false;
  bool _finishing = false;
  bool _switchingVideo = false;
  bool _socketEventsListening = false;
  bool _waitingForOfferAfterCallKitAccept = false;
  bool _iceRestarting = false;
  bool _answeringOffer = false;
  bool _remoteAnswerApplied = false;
  String? _lastAnsweredOfferFingerprint;

  // Video-upgrade requests are reusable during the same audio call.
  // These ids prevent a late/queued decline or answer from an older request
  // from affecting a newer request.
  String? _activeVideoUpgradeRequestId;
  String? _pendingVideoUpgradeRequestId;
  String? _pendingVideoUpgradeRequesterId;
  String? _lastResolvedVideoUpgradeRequestId;

  String? _conversationId;
  String? _callId;
  String _currentUserNameForOffer = '';
  String _currentUserAvatarForOffer = '';

  late final SocketHandler _onCallOffer;
  late final SocketHandler _onCallAnswer;
  late final SocketHandler _onIceCandidate;
  late final SocketHandler _onRenegotiateOffer;
  late final SocketHandler _onRenegotiateAnswer;
  late final SocketHandler _onVideoToggle;
  late final SocketHandler _onVideoUpgradeRejected;
  late final SocketHandler _onCallReject;
  late final SocketHandler _onCallEnd;
  late final SocketHandler _onCallLeave;
  late final SocketHandler _onCallBusy;
  late final SocketHandler _onCallTimeout;

  bool get _canUpdate => mounted && !_disposed;

  void _safeState(CallState newState) {
    if (!_canUpdate) return;
    state = newState;
  }

  String _cleanName(String value) {
    final cleaned = value.trim();
    return cleaned.isEmpty ? 'Unknown' : cleaned;
  }

  String _cleanAvatar(String value) {
    return value.trim();
  }

  Map<String, dynamic> _payloadFrom(Map<String, dynamic> data) {
    final raw = data['payload'];
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : Map<String, dynamic>.from(data);
  }

  String _payloadCallId(Map<String, dynamic> payload) {
    return (payload['call_id'] ?? payload['callId'])?.toString().trim() ?? '';
  }

  String _payloadConversationId(Map<String, dynamic> payload) {
    return (payload['conversation_id'] ?? payload['conversationId'])
            ?.toString()
            .trim() ??
        '';
  }

  String _payloadFromUser(Map<String, dynamic> payload) {
    return (payload['from'] ??
                payload['from_user'] ??
                payload['fromUser'] ??
                payload['caller_id'] ??
                payload['callerId'])
            ?.toString()
            .trim() ??
        '';
  }

  String _payloadVideoRequestId(Map<String, dynamic> payload) {
    return (payload['video_request_id'] ?? payload['videoRequestId'])
            ?.toString()
            .trim() ??
        '';
  }

  String _newVideoUpgradeRequestId(String currentUserId) {
    final callPart = (_callId ?? 'call').trim();
    final now = DateTime.now().microsecondsSinceEpoch;
    return '${callPart}_${currentUserId}_$now';
  }

  bool _matchesActiveEvent(
    Map<String, dynamic> payload, {
    bool allowAdoptCallId = false,
  }) {
    final incomingConversationId = _payloadConversationId(payload);
    final incomingCallId = _payloadCallId(payload);
    final fromUser = _payloadFromUser(payload);

    final activeConversationId = _conversationId?.trim() ?? '';
    final activeCallId = _callId?.trim() ?? '';
    final expectedRemoteUser = state.receiverId?.trim() ?? '';

    if (incomingConversationId.isNotEmpty &&
        activeConversationId.isNotEmpty &&
        incomingConversationId != activeConversationId) {
      return false;
    }

    if (fromUser.isNotEmpty &&
        expectedRemoteUser.isNotEmpty &&
        fromUser != expectedRemoteUser) {
      return false;
    }

    if (activeCallId.isNotEmpty && incomingCallId.isEmpty) {
      return false;
    }

    if (incomingCallId.isNotEmpty && activeCallId.isNotEmpty) {
      return incomingCallId == activeCallId;
    }

    if (incomingCallId.isNotEmpty &&
        activeCallId.isEmpty &&
        allowAdoptCallId) {
      _callId = incomingCallId;
      SocketService.instance.setActiveCallContext(
        callId: _callId,
        conversationId: _conversationId,
      );
    }

    return true;
  }

  Future<void> _connectConversationCallSocket() async {
    final conversationId = _conversationId?.trim() ?? '';

    if (conversationId.isEmpty) {
      throw StateError('Conversation id is missing');
    }

    final parsedConversationId = int.tryParse(conversationId);
    if (parsedConversationId == null) {
      throw StateError('Invalid conversation id: $conversationId');
    }

    String? accessToken = await ApiClient.storage.read(key: 'access');

    if (accessToken == null || accessToken.trim().isEmpty) {
      accessToken = await ApiClient.refreshAccessToken();
    }

    if (accessToken == null || accessToken.trim().isEmpty) {
      throw StateError('Access token is missing');
    }

    final url = AppConfig.callSocketUrl(
      conversationId: parsedConversationId,
      token: accessToken.trim(),
    );

    // Never log the URL here: it contains the JWT query parameter.
    debugPrint('CALL PROVIDER: connecting signaling socket for conversation $conversationId');

    await SocketService.instance.connect(url: url, autoReconnect: true);

    if (!SocketService.instance.isConnected) {
      throw StateError('Call signaling socket is not connected');
    }
  }

  Future<String> _createServerCall({
    required String receiverId,
    required String conversationId,
    required bool isVideoCall,
  }) async {
    final result = await CallApi.createCall(
      receiverId: receiverId,
      conversationId: conversationId,
      isVideoCall: isVideoCall,
    );

    // A 409 means Django did NOT create a new call for this attempt.
    // It may still return the identity of an already-existing call. Do not
    // automatically adopt that existing call here: it can be a legitimate
    // active call on another device, or a stale call that Django must clean up.
    if (result.conflict) {
      final message = result.error?.trim().isNotEmpty == true
          ? result.error!.trim()
          : 'A call is already active in this conversation';

      final existingCallId = result.callId?.trim() ?? '';
      final existingCallUuid = result.callUuid?.trim() ?? '';
      final existingStatus = result.status?.trim().toLowerCase() ?? '';

      debugPrint('');
      debugPrint('########################################');
      debugPrint('SERVER CALL CONFLICT');
      debugPrint('conversationId: $conversationId');
      debugPrint('receiverId: $receiverId');
      debugPrint('existingCallId: $existingCallId');
      debugPrint('existingCallUuid: $existingCallUuid');
      debugPrint('existingStatus: $existingStatus');
      debugPrint('message: $message');
      debugPrint('########################################');

      _safeState(
        state.copyWith(
          status: CallStatus.busy,
          errorMessage: message,
        ),
      );

      throw CallStartConflictException(
        message,
        existingCallId: existingCallId.isEmpty ? null : existingCallId,
        existingStatus: existingStatus.isEmpty ? null : existingStatus,
      );
    }

    final serverCallUuid = result.callUuid?.trim() ?? '';
    final serverCallId = result.callId?.trim() ?? '';

    if (!result.created) {
      throw StateError('Backend did not create a call session');
    }

    if (serverCallId.isEmpty && serverCallUuid.isEmpty) {
      throw StateError(
        'Backend created a call but returned neither call_id nor call_uuid',
      );
    }

    // IMPORTANT: Django's lifecycle endpoint currently uses:
    //   calls/<int:call_id>/status/
    // so the active call key must be the numeric database call_id.
    // The same key is also sent through signaling so both peers agree on it.
    if (serverCallId.isEmpty) {
      throw StateError(
        'Backend created the call but did not return numeric call_id. '
        'The current Django status endpoint requires <int:call_id>.',
      );
    }

    final callKey = serverCallId;

    debugPrint('');
    debugPrint('========================================');
    debugPrint('SERVER CALL CREATED');
    debugPrint('callId: $serverCallId');
    debugPrint('callUuid: $serverCallUuid');
    debugPrint('activeKey: $callKey');
    debugPrint('status: ${result.status}');
    debugPrint('========================================');

    return callKey;
  }

  Future<void> _sendCallReady() async {
    if (!_canUpdate || state.isCaller) return;

    final currentUserId = state.currentUserId?.trim() ?? '';
    final receiverId = state.receiverId?.trim() ?? '';
    final conversationId = _conversationId?.trim() ?? '';
    final callId = _callId?.trim() ?? '';

    if (currentUserId.isEmpty ||
        receiverId.isEmpty ||
        conversationId.isEmpty ||
        callId.isEmpty) {
      debugPrint('CALL READY NOT SENT: active call identity is incomplete');
      return;
    }

    SocketService.instance.emit(
      CallSocketEvents.callReady,
      <String, dynamic>{
        'from': currentUserId,
        'from_user': currentUserId,
        'call_id': callId,
        'callId': callId,
        'conversation_id': conversationId,
        'conversationId': conversationId,
      },
      targetUser: receiverId,
      conversationId: conversationId,
      queueIfDisconnected: true,
    );

    debugPrint('CALL READY SENT');
  }

  Map<String, dynamic>? _normalizeOffer(Map<String, dynamic>? source) {
    if (source == null) return null;

    Map<String, dynamic> candidate = Map<String, dynamic>.from(source);

    // Accept all shapes used by foreground WS, FCM/CallKit, and cached events:
    // {payload: {offer: {...}}}, {offer: {...}}, or {type: offer, sdp: ...}.
    final rawPayload = candidate['payload'];
    if (rawPayload is Map) {
      candidate = Map<String, dynamic>.from(rawPayload);
    }

    final rawOffer = candidate['offer'];
    if (rawOffer is Map) {
      candidate = Map<String, dynamic>.from(rawOffer);
    }

    final type =
        candidate['type']?.toString().trim().toLowerCase() ?? '';
    final rawSdp = candidate['sdp'];

    if (type != 'offer' || rawSdp is! String || rawSdp.trim().isEmpty) {
      return null;
    }

    // IMPORTANT: preserve SDP exactly. Do not trim/reformat it.
    return <String, dynamic>{
      'type': 'offer',
      'sdp': rawSdp,
    };
  }

  Future<void> startCall({
    required String currentUserId,
    required String receiverId,
    required String currentUserName,
    required String currentUserAvatar,

    // These two values must always be the OTHER user's info.
    required String name,
    required String avatarUrl,

    required bool isVideoCall,
    required bool isCaller,
    String? conversationId,
    Map<String, dynamic>? incomingOffer,
    String? callId,
  }) async {
    final cleanCurrentUserId = currentUserId.trim();
    final cleanReceiverId = receiverId.trim();
    final cleanConversationId = conversationId?.trim() ?? '';
    final suppliedCallId = callId?.trim() ?? '';

    if (cleanCurrentUserId.isEmpty) {
      throw ArgumentError('currentUserId is required for a call');
    }
    if (cleanReceiverId.isEmpty) {
      throw ArgumentError('receiverId is required for a call');
    }
    if (cleanConversationId.isEmpty) {
      throw ArgumentError('conversationId is required for a call');
    }

    // One active call at a time. Do not reset a live call just because another
    // screen accidentally called startCall() twice.
    if (state.status != CallStatus.idle && !_isFinalStatus(state.status)) {
      final sameCall = state.conversationId == cleanConversationId &&
          state.receiverId == cleanReceiverId;
      if (sameCall) {
        debugPrint('CALL START IGNORED: same call is already starting/active');
        return;
      }
      throw StateError('Another call is already active on this device');
    }

    _disposed = false;
    _finishing = false;
    _switchingVideo = false;
    _waitingForOfferAfterCallKitAccept = false;
    _iceRestarting = false;
    _answeringOffer = false;
    _remoteAnswerApplied = false;
    _lastAnsweredOfferFingerprint = null;
    _activeVideoUpgradeRequestId = null;
    _pendingVideoUpgradeRequestId = null;
    _pendingVideoUpgradeRequesterId = null;
    _lastResolvedVideoUpgradeRequestId = null;

    _durationTimer?.cancel();
    _timeoutTimer?.cancel();
    _removeSocketEvents();

    _conversationId = cleanConversationId;
    _callId = suppliedCallId.isEmpty ? null : suppliedCallId;
    _currentUserNameForOffer = currentUserName.trim();
    _currentUserAvatarForOffer = currentUserAvatar.trim();

    final remoteName = _cleanName(name);
    final remoteAvatar = _cleanAvatar(avatarUrl);

    _safeState(
      CallState(
        status: isCaller ? CallStatus.calling : CallStatus.incoming,
        currentUserId: cleanCurrentUserId,
        receiverId: cleanReceiverId,
        callId: _callId,
        conversationId: cleanConversationId,
        name: remoteName,
        avatarUrl: remoteAvatar,
        isVideoCall: isVideoCall,
        isCaller: isCaller,
        incomingOffer: incomingOffer,
        isCameraOff: !isVideoCall,
        isRemoteCameraOff: !isVideoCall,
        isSpeakerOn: isVideoCall,
        duration: Duration.zero,
      ),
    );

    bool backendCallWasCreatedOrAccepted = false;

    try {
      // ------------------------------------------------------------
      // 1. AUTHORITATIVE SERVER LIFECYCLE FIRST
      // ------------------------------------------------------------
      // Caller: Django creates the call id.
      // Receiver: the server records Accept before media signaling starts.
      if (isCaller) {
        if ((_callId ?? '').isEmpty) {
          _callId = await _createServerCall(
            receiverId: cleanReceiverId,
            conversationId: cleanConversationId,
            isVideoCall: isVideoCall,
          );
        }
        backendCallWasCreatedOrAccepted = true;
      } else {
        if ((_callId ?? '').isEmpty) {
          throw StateError('Incoming call is missing server call_id');
        }

        await CallApi.accept(_callId!);
        backendCallWasCreatedOrAccepted = true;
      }

      if (!_canUpdate) return;

      _safeState(
        state.copyWith(
          status: CallStatus.ringing,
          callId: _callId,
          conversationId: _conversationId,
          clearError: true,
        ),
      );

      // ------------------------------------------------------------
      // 2. CONNECT THE PER-CALL SIGNALING CHANNEL
      // ------------------------------------------------------------
      await _connectConversationCallSocket();

      SocketService.instance.setActiveCallContext(
        callId: _callId,
        conversationId: _conversationId,
      );

      _listenSocketEvents();

      // ------------------------------------------------------------
      // 3. PREPARE WEBRTC ONLY AFTER SERVER CALL CREATION/ACCEPT
      // ------------------------------------------------------------
      await webrtc.dispose();
      await webrtc.disposeRenderers();
      if (!_canUpdate) return;

      await webrtc.initRenderers();

      await webrtc.createConnection(
        isVideoCall: isVideoCall,
        onIceCandidate: (candidate) {
          if (!_canUpdate || _isFinalStatus(state.status)) return;

          SocketService.instance.emit(
            CallSocketEvents.iceCandidate,
            <String, dynamic>{
              'from': cleanCurrentUserId,
              'from_user': cleanCurrentUserId,
              'candidate': candidate.toMap(),
              if (_callId != null) 'call_id': _callId,
              if (_callId != null) 'callId': _callId,
              'conversation_id': cleanConversationId,
              'conversationId': cleanConversationId,
            },
            targetUser: cleanReceiverId,
            conversationId: cleanConversationId,
            queueIfDisconnected: true,
          );
        },
        onRemoteStream: () {
          if (!_canUpdate || _isFinalStatus(state.status)) return;
          _safeState(
            state.copyWith(
              localRenderer: webrtc.localRenderer,
              remoteRenderer: webrtc.remoteRenderer,
            ),
          );
        },
        onConnectionEstablished: () async {
          await setConnected();
        },
        onConnectionLost: () {
          debugPrint('CALL MEDIA TEMPORARILY DISCONNECTED');
        },
        onIceRestartNeeded: () async {
          await _restartIceAndSendOffer();
        },
      );

      _safeState(
        state.copyWith(
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );

      if (isCaller) {
        try {
          await CallSoundService.instance.playOutgoingTone();
        } catch (_) {}

        _startCallTimeout();

        // The first offer is sent only after Django has created the call. The
        // socket service caches it; a receiver that accepts from FCM/CallKit
        // sends call_ready and the cached offer is automatically resent.
        final offer = await webrtc.createOffer();

        SocketService.instance.emit(
          CallSocketEvents.callOffer,
          <String, dynamic>{
            'from': cleanCurrentUserId,
            'from_user': cleanCurrentUserId,
            'callerName': currentUserName.trim(),
            'caller_name': currentUserName.trim(),
            'callerAvatar': currentUserAvatar.trim(),
            'caller_avatar': currentUserAvatar.trim(),
            'isVideoCall': isVideoCall,
            'is_video_call': isVideoCall,
            'offer': offer.toMap(),
            'call_id': _callId,
            'callId': _callId,
            'conversation_id': cleanConversationId,
            'conversationId': cleanConversationId,
          },
          targetUser: cleanReceiverId,
          conversationId: cleanConversationId,
          queueIfDisconnected: true,
        );

        debugPrint('CALL OFFER SENT FOR SERVER CALL $_callId');
        return;
      }

      try {
        await CallSoundService.instance.stop();
      } catch (_) {}

      // Foreground incoming_call normally contains the offer. CallKit/FCM can
      // open the app before that offer arrives; call_ready asks the caller to
      // resend its cached offer in that case.
      final normalizedIncomingOffer = _normalizeOffer(incomingOffer);

      if (normalizedIncomingOffer == null) {
        _waitingForOfferAfterCallKitAccept = true;
        await _sendCallReady();

        if (incomingOffer == null) {
          debugPrint('RECEIVER ACCEPTED. WAITING FOR CALL_OFFER...');
        } else {
          debugPrint(
            'RECEIVER ACCEPTED. SUPPLIED OFFER WAS NOT A VALID SDP OFFER; '
            'WAITING FOR FRESH CALL_OFFER...',
          );
        }
        return;
      }

      debugPrint(
        'DIRECT INCOMING OFFER NORMALIZED: '
        'type=${normalizedIncomingOffer['type']} '
        'sdpLength=${(normalizedIncomingOffer['sdp'] as String).length}',
      );

      await _answerIncomingOffer(
        offer: normalizedIncomingOffer,
        currentUserId: cleanCurrentUserId,
        receiverId: cleanReceiverId,
      );
    } on CallStartConflictException catch (e) {
      debugPrint('');
      debugPrint('########################################');
      debugPrint('CALL START BLOCKED BY SERVER');
      debugPrint('message: ${e.message}');
      debugPrint('existingCallId: ${e.existingCallId ?? "unknown"}');
      debugPrint('existingStatus: ${e.existingStatus ?? "unknown"}');
      debugPrint('########################################');

      _timeoutTimer?.cancel();

      try {
        await CallSoundService.instance.stop();
      } catch (soundError) {
        debugPrint('CALL CONFLICT SOUND STOP ERROR: $soundError');
      }

      // Do not initialize signaling/WebRTC and do not adopt the returned
      // existing call id automatically. This call attempt did not create a
      // new backend session. Django must decide whether the existing call is
      // active or stale.
      return;
    } catch (e, st) {
      debugPrint('Start call error: $e');
      debugPrint(st.toString());

      if (_canUpdate) {
        _safeState(state.copyWith(errorMessage: e.toString()));

        await _finishCall(
          CallStatus.failed,
          emitSocket: backendCallWasCreatedOrAccepted,
          updateBackend: backendCallWasCreatedOrAccepted,
        );
      }
    }
  }

  void _listenSocketEvents() {
    if (_socketEventsListening) {
      debugPrint('CALL SOCKET EVENTS ALREADY LISTENING - SKIP');
      return;
    }

    _socketEventsListening = true;

    final socket = SocketService.instance;

    socket.on(CallSocketEvents.callOffer, _onCallOffer);
    socket.on(CallSocketEvents.callAnswer, _onCallAnswer);
    socket.on(CallSocketEvents.iceCandidate, _onIceCandidate);
    socket.on(CallSocketEvents.callRenegotiateOffer, _onRenegotiateOffer);
    socket.on(CallSocketEvents.callRenegotiateAnswer, _onRenegotiateAnswer);
    socket.on(CallSocketEvents.callVideoToggle, _onVideoToggle);
    socket.on(
      CallSocketEvents.callVideoUpgradeRejected,
      _onVideoUpgradeRejected,
    );
    socket.on(CallSocketEvents.callReject, _onCallReject);
    socket.on(CallSocketEvents.callEnd, _onCallEnd);
    socket.on(CallSocketEvents.callLeave, _onCallLeave);
    socket.on(CallSocketEvents.callBusy, _onCallBusy);
    socket.on(CallSocketEvents.callTimeout, _onCallTimeout);
  }

  Future<void> _handleCallOffer(Map<String, dynamic> data) async {
    if (!_canUpdate || _isFinalStatus(state.status)) return;
    if (state.isCaller) return;

    final payload = _payloadFrom(data);

    if (!_matchesActiveEvent(payload, allowAdoptCallId: true)) {
      debugPrint('CALL OFFER IGNORED: it does not belong to the active call');
      return;
    }

    final fromUser = payload['from']?.toString() ??
        payload['from_user']?.toString() ??
        payload['caller_id']?.toString() ??
        payload['callerId']?.toString();

    if (fromUser != null &&
        fromUser.trim().isNotEmpty &&
        state.receiverId != null &&
        fromUser.trim() != state.receiverId.toString()) {
      debugPrint('CALL OFFER IGNORED: from different user $fromUser');
      return;
    }

    final payloadConversationId = payload['conversation_id']?.toString() ??
        payload['conversationId']?.toString();

    if (payloadConversationId != null &&
        payloadConversationId.trim().isNotEmpty &&
        _conversationId != null &&
        _conversationId!.trim().isNotEmpty &&
        payloadConversationId.trim() != _conversationId!.trim()) {
      debugPrint(
        'CALL OFFER IGNORED: different conversation $payloadConversationId',
      );
      return;
    }

    final offer = _normalizeOffer(payload);

    if (offer == null) {
      debugPrint(
        'CALL OFFER INVALID: expected a WebRTC offer with type=offer and SDP',
      );
      return;
    }

    final callIdFromPayload =
        payload['call_id']?.toString() ?? payload['callId']?.toString();

    final conversationIdFromPayload = payload['conversation_id']?.toString() ??
        payload['conversationId']?.toString();

    if ((_callId == null || _callId!.trim().isEmpty) &&
        callIdFromPayload != null &&
        callIdFromPayload.trim().isNotEmpty) {
      _callId = callIdFromPayload.trim();
    }

    if ((_conversationId == null || _conversationId!.trim().isEmpty) &&
        conversationIdFromPayload != null &&
        conversationIdFromPayload.trim().isNotEmpty) {
      _conversationId = conversationIdFromPayload.trim();
    }

    final currentUserId = state.currentUserId;
    final receiverId = state.receiverId;

    if (currentUserId == null || receiverId == null) {
      debugPrint('CALL OFFER ERROR: state currentUserId/receiverId missing');
      return;
    }

    debugPrint('CALL OFFER RECEIVED. CREATING ANSWER...');
    _waitingForOfferAfterCallKitAccept = false;

    await _answerIncomingOffer(
      offer: offer,
      currentUserId: currentUserId,
      receiverId: receiverId,
    );
  }

  Future<void> _answerIncomingOffer({
    required Map<String, dynamic> offer,
    required String currentUserId,
    required String receiverId,
  }) async {
    final normalizedOffer = _normalizeOffer(offer);

    if (normalizedOffer == null) {
      debugPrint(
        'ANSWER INCOMING OFFER ERROR: malformed offer; requesting resend',
      );
      _waitingForOfferAfterCallKitAccept = true;
      await _sendCallReady();
      return;
    }

    final offerType = normalizedOffer['type'] as String;
    final offerSdp = normalizedOffer['sdp'] as String;
    final fingerprint = '$offerType:${offerSdp.hashCode}';

    if (_lastAnsweredOfferFingerprint == fingerprint) {
      debugPrint('DUPLICATE CALL OFFER IGNORED');
      return;
    }

    if (_answeringOffer) {
      debugPrint('CALL OFFER IGNORED: answer creation already in progress');
      return;
    }

    _answeringOffer = true;

    try {
      debugPrint(
        'ANSWERING OFFER: type=$offerType sdpLength=${offerSdp.length}',
      );

      await webrtc.setRemoteDescription(normalizedOffer);
      final answer = await webrtc.createAnswer();

      SocketService.instance.emit(
        CallSocketEvents.callAnswer,
        {
          'from': currentUserId,
          'from_user': currentUserId,
          'answer': answer.toMap(),
          if (_callId != null) 'call_id': _callId,
          if (_callId != null) 'callId': _callId,
          if (_conversationId != null) 'conversation_id': _conversationId,
          if (_conversationId != null) 'conversationId': _conversationId,
        },
        targetUser: receiverId,
        conversationId: _conversationId,
        queueIfDisconnected: true,
      );

      _lastAnsweredOfferFingerprint = fingerprint;
      _waitingForOfferAfterCallKitAccept = false;

      _safeState(
        state.copyWith(
          incomingOffer: normalizedOffer,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );

      debugPrint('CALL ANSWER SENT');
    } catch (e, st) {
      debugPrint('ANSWER INCOMING OFFER ERROR: $e');
      debugPrint(st.toString());

      // Do not immediately end an accepted backend call because one SDP copy
      // was malformed/stale. Request the caller's current local offer again.
      if (_canUpdate && !_isFinalStatus(state.status)) {
        _waitingForOfferAfterCallKitAccept = true;
        await _sendCallReady();
        debugPrint('REMOTE OFFER APPLY FAILED; REQUESTED FRESH CALL_OFFER');
      }
    } finally {
      _answeringOffer = false;
    }
  }

  Future<void> _handleCallAnswer(Map<String, dynamic> data) async {
    if (!_canUpdate || _isFinalStatus(state.status)) return;
    if (!state.isCaller || _remoteAnswerApplied) return;

    final payload = _payloadFrom(data);

    if (!_matchesActiveEvent(payload, allowAdoptCallId: false)) {
      debugPrint('CALL ANSWER IGNORED: it does not belong to the active call');
      return;
    }

    final rawAnswer = payload['answer'];
    Map<String, dynamic>? answer;

    if (rawAnswer is Map) {
      answer = Map<String, dynamic>.from(rawAnswer);
    } else {
      final type = payload['type']?.toString().trim() ?? '';
      final sdp = payload['sdp']?.toString().trim() ?? '';

      if (type.isNotEmpty && sdp.isNotEmpty) {
        answer = <String, dynamic>{'type': type, 'sdp': sdp};
      }
    }

    final type = answer?['type']?.toString().trim() ?? '';
    final sdp = answer?['sdp']?.toString().trim() ?? '';

    if (type.isEmpty || sdp.isEmpty) {
      debugPrint('CALL ANSWER MISSING SDP');
      return;
    }

    try {
      await webrtc.setRemoteDescription(answer!);
      _remoteAnswerApplied = true;
      _timeoutTimer?.cancel();

      _safeState(
        state.copyWith(
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );
    } catch (e, st) {
      debugPrint('CALL ANSWER ERROR: $e');
      debugPrint(st.toString());
      await _finishCall(CallStatus.failed, emitSocket: false);
    }
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    if (!_canUpdate || _isFinalStatus(state.status)) return;

    final payload = _payloadFrom(data);

    if (!_matchesActiveEvent(payload, allowAdoptCallId: true)) {
      debugPrint('ICE CANDIDATE IGNORED: wrong active call');
      return;
    }

    final rawCandidate = payload['candidate'];
    if (rawCandidate is! Map) return;

    try {
      await webrtc.addCandidate(Map<String, dynamic>.from(rawCandidate));
    } catch (e, st) {
      debugPrint('ICE ERROR: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> _handleRenegotiateOffer(Map<String, dynamic> data) async {
    if (!_canUpdate || _isFinalStatus(state.status)) return;

    final rawPayload = data['payload'];
    if (rawPayload is! Map) return;

    final payload = Map<String, dynamic>.from(rawPayload);
    if (!_matchesActiveEvent(payload)) return;

    final rawOffer = payload['offer'];
    if (rawOffer is! Map) return;

    final requestType = payload['requestType']?.toString() ??
        payload['request_type']?.toString() ??
        '';

    /*
      ICE restart must be answered automatically.
      Do NOT show video upgrade popup for this renegotiation.
    */
    if (requestType == 'ice_restart') {
      final currentUserId = state.currentUserId;
      final receiverId = state.receiverId;

      if (currentUserId == null || receiverId == null) return;

      try {
        final answer = await webrtc.handleRenegotiationOffer(
          Map<String, dynamic>.from(rawOffer),
        );

        SocketService.instance.emit(
          CallSocketEvents.callRenegotiateAnswer,
          {
            'from': currentUserId,
            'from_user': currentUserId,
            'answer': answer.toMap(),
            'requestType': 'ice_restart',
            'request_type': 'ice_restart',
            if (_callId != null) 'call_id': _callId,
            if (_callId != null) 'callId': _callId,
            if (_conversationId != null) 'conversation_id': _conversationId,
            if (_conversationId != null) 'conversationId': _conversationId,
          },
          targetUser: receiverId,
          conversationId: _conversationId,
          queueIfDisconnected: true,
        );

        _safeState(
          state.copyWith(
            localRenderer: webrtc.localRenderer,
            remoteRenderer: webrtc.remoteRenderer,
          ),
        );

        debugPrint('ICE RESTART ANSWER SENT');
      } catch (e, st) {
        debugPrint('ICE RESTART OFFER HANDLE ERROR: $e');
        debugPrint(st.toString());
      }

      return;
    }

    // Only video-upgrade renegotiation should show the Accept/Decline popup.
    // This avoids accidentally treating an unrelated renegotiation as video.
    if (requestType.isNotEmpty && requestType != 'video_upgrade') {
      debugPrint('RENEGOTIATION OFFER IGNORED: unsupported type $requestType');
      return;
    }

    final requestId = _payloadVideoRequestId(payload);
    final requestFromUser = _payloadFromUser(payload);

    // Remember the ACTUAL user who sent this upgrade request.
    // Accept/Decline must reply to this user, not blindly to state.receiverId.
    _pendingVideoUpgradeRequesterId =
        requestFromUser.isEmpty ? null : requestFromUser;

    debugPrint(
      'VIDEO UPGRADE REQUEST FROM USER: '
      '${_pendingVideoUpgradeRequesterId ?? "unknown"}',
    );

    // A duplicated/late copy of an already answered or declined request must
    // never reopen the popup. This is what makes repeated requests reliable.
    if (requestId.isNotEmpty &&
        requestId == _lastResolvedVideoUpgradeRequestId) {
      debugPrint(
        'DUPLICATE RESOLVED VIDEO UPGRADE REQUEST IGNORED: $requestId',
      );
      return;
    }

    _pendingVideoUpgradeRequestId =
        requestId.isEmpty ? null : requestId;

    _safeState(
      state.copyWith(
        hasPendingVideoUpgrade: true,
        pendingVideoOffer: Map<String, dynamic>.from(rawOffer),
        isVideoUpgradeRequesting: false,
        isVideoUpgradeRejected: false,
        clearError: true,
      ),
    );

    debugPrint(
      'VIDEO UPGRADE REQUEST RECEIVED: '
      '${_pendingVideoUpgradeRequestId ?? "legacy/no-id"}',
    );
  }

  Future<void> _handleRenegotiateAnswer(Map<String, dynamic> data) async {
    if (!_canUpdate || _isFinalStatus(state.status)) return;

    final rawPayload = data['payload'];
    if (rawPayload is! Map) return;

    final payload = Map<String, dynamic>.from(rawPayload);
    if (!_matchesActiveEvent(payload)) return;

    final rawAnswer = payload['answer'];
    if (rawAnswer is! Map) {
      debugPrint('VIDEO UPGRADE ANSWER IGNORED: answer payload missing');
      return;
    }

    debugPrint(
      'VIDEO UPGRADE ANSWER RECEIVED FROM: ${_payloadFromUser(payload)}',
    );

    final requestType = payload['requestType']?.toString() ??
        payload['request_type']?.toString() ??
        '';

    if (requestType != 'ice_restart') {
      final incomingRequestId = _payloadVideoRequestId(payload);
      final activeRequestId = _activeVideoUpgradeRequestId?.trim() ?? '';
      final lastResolvedId = _lastResolvedVideoUpgradeRequestId?.trim() ?? '';

      // If the fallback call_video_toggle event already carried and applied
      // this exact SDP answer, do NOT apply the same answer a second time.
      // Applying an answer twice while the PC is already stable can throw and
      // previously caused the requester to roll back to audio.
      if (incomingRequestId.isNotEmpty &&
          incomingRequestId == lastResolvedId &&
          state.isVideoCall) {
        debugPrint(
          'DUPLICATE VIDEO UPGRADE ANSWER IGNORED: $incomingRequestId',
        );
        return;
      }

      // If ids are present, only the answer for the CURRENT request is valid.
      if (activeRequestId.isNotEmpty &&
          incomingRequestId.isNotEmpty &&
          incomingRequestId != activeRequestId) {
        debugPrint(
          'STALE VIDEO UPGRADE ANSWER IGNORED: '
          'incoming=$incomingRequestId active=$activeRequestId',
        );
        return;
      }
    }

    try {
      await webrtc.handleRenegotiationAnswer(
        Map<String, dynamic>.from(rawAnswer),
      );

      await webrtc.setSpeaker(true);

      if (requestType == 'ice_restart') {
        _safeState(
          state.copyWith(
            localRenderer: webrtc.localRenderer,
            remoteRenderer: webrtc.remoteRenderer,
          ),
        );

        debugPrint('ICE RESTART ANSWER SET');
        return;
      }

      final resolvedRequestId = _activeVideoUpgradeRequestId;
      _activeVideoUpgradeRequestId = null;
      if (resolvedRequestId != null && resolvedRequestId.isNotEmpty) {
        _lastResolvedVideoUpgradeRequestId = resolvedRequestId;
      }

      _safeState(
        state.copyWith(
          isVideoCall: true,
          isCameraOff: false,
          isRemoteCameraOff: false,
          isSpeakerOn: true,
          isVideoUpgradeRequesting: false,
          isVideoUpgradeRejected: false,
          clearError: true,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );

      debugPrint(
        'VIDEO UPGRADE ANSWER APPLIED: '
        '${resolvedRequestId ?? "legacy/no-id"}',
      );
    } catch (e, st) {
      debugPrint('Renegotiation answer error: $e');
      debugPrint(st.toString());

      if (requestType == 'ice_restart') {
        return;
      }

      final failedRequestId = _activeVideoUpgradeRequestId;
      _activeVideoUpgradeRequestId = null;
      if (failedRequestId != null && failedRequestId.isNotEmpty) {
        _lastResolvedVideoUpgradeRequestId = failedRequestId;
      }

      await webrtc.disableVideoHard();
      await webrtc.setSpeaker(false);

      _safeState(
        state.copyWith(
          isVideoCall: false,
          isCameraOff: true,
          isRemoteCameraOff: true,
          isSpeakerOn: false,
          isVideoUpgradeRequesting: false,
          isVideoUpgradeRejected: false,
          errorMessage: 'Unable to switch to video. Please try again.',
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );
    } finally {
      if (requestType != 'ice_restart') {
        _switchingVideo = false;
      }
    }
  }

  Future<void> _handleVideoToggle(Map<String, dynamic> data) async {
    if (!_canUpdate || _isFinalStatus(state.status)) return;

    final rawPayload = data['payload'];
    if (rawPayload is! Map) return;

    final payload = Map<String, dynamic>.from(rawPayload);
    if (!_matchesActiveEvent(payload)) return;

    final fromUserId = _payloadFromUser(payload);
    final currentUserId = state.currentUserId?.trim() ?? '';

    if (fromUserId.isNotEmpty &&
        currentUserId.isNotEmpty &&
        fromUserId == currentUserId) {
      return;
    }

    if (payload.containsKey('cameraOff')) {
      final remoteCameraOff = payload['cameraOff'] == true ||
          payload['cameraOff']?.toString() == 'true';

      _safeState(
        state.copyWith(
          isRemoteCameraOff: remoteCameraOff,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );

      return;
    }

    if (!payload.containsKey('isVideoCall') &&
        !payload.containsKey('is_video_call')) {
      return;
    }

    final remoteIsVideoCall = payload['isVideoCall'] == true ||
        payload['is_video_call'] == true ||
        payload['isVideoCall']?.toString() == 'true' ||
        payload['is_video_call']?.toString() == 'true';

    if (!remoteIsVideoCall) {
      await webrtc.disableVideoHard();
      await webrtc.setSpeaker(false);

      _activeVideoUpgradeRequestId = null;
      _pendingVideoUpgradeRequestId = null;
      _pendingVideoUpgradeRequesterId = null;
      _switchingVideo = false;

      _safeState(
        state.copyWith(
          isVideoCall: false,
          isCameraOff: true,
          isRemoteCameraOff: true,
          isSpeakerOn: false,
          isVideoUpgradeRequesting: false,
          hasPendingVideoUpgrade: false,
          isVideoUpgradeRejected: false,
          clearPendingVideoOffer: true,
          clearError: true,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );

      debugPrint('VIDEO MODE SYNC: switched to audio');
      return;
    }

    /*
      ACCEPT FALLBACK PATH

      Normal path:
        call_renegotiate_answer -> _handleRenegotiateAnswer()

      Fallback path:
        call_video_toggle(isVideoCall=true, answer=<same SDP answer>)

      If the requester somehow misses/filters the normal renegotiation-answer
      event, this second event still contains the SDP answer and can finish
      the offer/answer transaction before changing the UI to video.
    */
    final requestId = _payloadVideoRequestId(payload);
    final rawFallbackAnswer = payload['answer'];

    if (state.isVideoUpgradeRequesting) {
      if (rawFallbackAnswer is! Map) {
        debugPrint(
          'VIDEO MODE SYNC WAITING: requester still needs SDP answer',
        );
        return;
      }

      try {
        debugPrint(
          'VIDEO MODE SYNC FALLBACK: applying accepted SDP answer '
          '${requestId.isEmpty ? "legacy/no-id" : requestId}',
        );

        await webrtc.handleRenegotiationAnswer(
          Map<String, dynamic>.from(rawFallbackAnswer),
        );
        await webrtc.setSpeaker(true);
      } catch (e, st) {
        debugPrint('VIDEO MODE SYNC FALLBACK ANSWER ERROR: $e');
        debugPrint(st.toString());

        _switchingVideo = false;

        _safeState(
          state.copyWith(
            isVideoCall: false,
            isCameraOff: false,
            isRemoteCameraOff: true,
            isSpeakerOn: false,
            isVideoUpgradeRequesting: false,
            isVideoUpgradeRejected: false,
            errorMessage: 'Video was accepted but SDP answer could not be applied.',
            localRenderer: webrtc.localRenderer,
            remoteRenderer: webrtc.remoteRenderer,
          ),
        );
        return;
      }
    }

    final resolvedId = requestId.isNotEmpty
        ? requestId
        : (_activeVideoUpgradeRequestId?.trim() ?? '');

    if (resolvedId.isNotEmpty) {
      _lastResolvedVideoUpgradeRequestId = resolvedId;
    }

    _activeVideoUpgradeRequestId = null;
    _pendingVideoUpgradeRequestId = null;
    _pendingVideoUpgradeRequesterId = null;
    _switchingVideo = false;

    _safeState(
      state.copyWith(
        isVideoCall: true,
        isCameraOff: false,
        isRemoteCameraOff: false,
        isSpeakerOn: true,
        isVideoUpgradeRequesting: false,
        isVideoUpgradeRejected: false,
        hasPendingVideoUpgrade: false,
        clearPendingVideoOffer: true,
        clearError: true,
        localRenderer: webrtc.localRenderer,
        remoteRenderer: webrtc.remoteRenderer,
      ),
    );

    debugPrint(
      'VIDEO MODE SYNC: both sides video '
      '${resolvedId.isEmpty ? "legacy/no-id" : resolvedId}',
    );
  }

  Future<void> _handleVideoUpgradeRejected(Map<String, dynamic> data) async {
    if (!_canUpdate || _isFinalStatus(state.status)) return;

    final payload = _payloadFrom(data);
    if (!_matchesActiveEvent(payload)) return;

    // Ignore an echo of the rejection emitted by this same device/user.
    final fromUserId = _payloadFromUser(payload);
    final currentUserId = state.currentUserId?.trim() ?? '';
    if (fromUserId.isNotEmpty &&
        currentUserId.isNotEmpty &&
        fromUserId == currentUserId) {
      debugPrint('OWN VIDEO UPGRADE REJECTION ECHO IGNORED');
      return;
    }

    final incomingRequestId = _payloadVideoRequestId(payload);
    final activeRequestId = _activeVideoUpgradeRequestId?.trim() ?? '';

    // A delayed rejection from request #1 must not reject request #2.
    if (activeRequestId.isNotEmpty &&
        incomingRequestId.isNotEmpty &&
        incomingRequestId != activeRequestId) {
      debugPrint(
        'STALE VIDEO UPGRADE REJECTION IGNORED: '
        'incoming=$incomingRequestId active=$activeRequestId',
      );
      return;
    }

    // If there is no active request anymore, this is a late duplicate.
    if (activeRequestId.isEmpty && !state.isVideoUpgradeRequesting) {
      debugPrint('LATE VIDEO UPGRADE REJECTION IGNORED: no active request');
      return;
    }

    // A declined upgrade carries a normal SDP answer so the requester can
    // leave have-local-offer and return to stable signaling before trying
    // another video request.
    final rawDeclineAnswer = payload['answer'];
    if (rawDeclineAnswer is Map) {
      try {
        await webrtc.handleRenegotiationAnswer(
          Map<String, dynamic>.from(rawDeclineAnswer),
        );
        debugPrint('VIDEO UPGRADE DECLINE ANSWER APPLIED');
      } catch (e, st) {
        debugPrint('VIDEO UPGRADE DECLINE ANSWER ERROR: $e');
        debugPrint(st.toString());
      }
    } else {
      debugPrint(
        'VIDEO UPGRADE DECLINE WARNING: no stabilizing SDP answer received',
      );
    }

    try {
      await webrtc.disableVideoHard();
      await webrtc.setSpeaker(false);
    } catch (e, st) {
      debugPrint('VIDEO UPGRADE REJECT ROLLBACK ERROR: $e');
      debugPrint(st.toString());
    }

    final resolvedRequestId =
        incomingRequestId.isNotEmpty ? incomingRequestId : activeRequestId;

    _activeVideoUpgradeRequestId = null;
    if (resolvedRequestId.isNotEmpty) {
      _lastResolvedVideoUpgradeRequestId = resolvedRequestId;
    }

    _safeState(
      state.copyWith(
        isVideoCall: false,
        isCameraOff: true,
        isRemoteCameraOff: true,
        isSpeakerOn: false,
        isVideoUpgradeRequesting: false,
        isVideoUpgradeRejected: true,
        clearError: true,
        localRenderer: webrtc.localRenderer,
        remoteRenderer: webrtc.remoteRenderer,
      ),
    );

    // Critical for allowing another video request after Decline.
    _switchingVideo = false;

    debugPrint(
      'VIDEO UPGRADE DECLINED: '
      '${resolvedRequestId.isEmpty ? "legacy/no-id" : resolvedRequestId}',
    );
  }

  Future<void> _handleCallReject(Map<String, dynamic> data) async {
    final payload = _payloadFrom(data);

    if (!_matchesActiveEvent(payload, allowAdoptCallId: true)) {
      debugPrint('CALL REJECT IGNORED: it does not belong to the active call');
      return;
    }

    if (!_canUpdate || _isFinalStatus(state.status)) return;

    debugPrint('REMOTE CALL REJECT RECEIVED: $data');

    await _finishCall(
      CallStatus.rejected,
      emitSocket: false,
      disconnectSocket: true,
      updateBackend: false,
    );
  }

  Future<void> _handleCallEnd(Map<String, dynamic> data) async {
    final payload = _payloadFrom(data);

    if (!_matchesActiveEvent(payload, allowAdoptCallId: true)) {
      debugPrint('CALL END IGNORED: it does not belong to the active call');
      return;
    }

    if (!_canUpdate || _isFinalStatus(state.status)) return;

    debugPrint('REMOTE CALL END RECEIVED: $data');

    await _finishCall(
      CallStatus.ended,
      emitSocket: false,
      disconnectSocket: true,
      updateBackend: false,
    );
  }

  Future<void> _handleCallLeave(Map<String, dynamic> data) async {
    final payload = _payloadFrom(data);
    if (!_matchesActiveEvent(payload)) return;
    if (!_canUpdate) return;
    await _finishCall(CallStatus.ended, emitSocket: false, updateBackend: false);
  }

  Future<void> _handleCallBusy(Map<String, dynamic> data) async {
    final payload = _payloadFrom(data);
    if (!_matchesActiveEvent(payload)) return;
    if (!_canUpdate) return;
    await _finishCall(CallStatus.busy, emitSocket: false, updateBackend: false);
  }

  Future<void> _handleCallTimeout(Map<String, dynamic> data) async {
    final payload = _payloadFrom(data);
    if (!_matchesActiveEvent(payload)) return;
    if (!_canUpdate || _isFinalStatus(state.status)) return;

    debugPrint('CALL TIMEOUT RECEIVED: $data');

    await _finishCall(
      CallStatus.timeout,
      emitSocket: false,
      disconnectSocket: true,
      updateBackend: false,
    );
  }

  Future<void> _restartIceAndSendOffer() async {
    if (!_canUpdate) return;
    if (_iceRestarting) return;
    if (_isFinalStatus(state.status)) return;

    final currentUserId = state.currentUserId?.trim() ?? '';
    final receiverId = state.receiverId?.trim() ?? '';
    final conversationId = _conversationId?.trim() ?? '';
    final callId = _callId?.trim() ?? '';

    if (currentUserId.isEmpty ||
        receiverId.isEmpty ||
        conversationId.isEmpty ||
        callId.isEmpty) {
      debugPrint('ICE RESTART SKIPPED: active call identity is incomplete');
      return;
    }

    _iceRestarting = true;

    try {
      // IMPORTANT:
      // Create the ICE-restart offer even if the signaling WebSocket is down.
      // SocketService.emit(queueIfDisconnected: true) will queue the offer,
      // trigger a reconnect, and flush it once signaling is available again.
      final offer = await webrtc.restartIce();

      SocketService.instance.emit(
        CallSocketEvents.callRenegotiateOffer,
        <String, dynamic>{
          'from': currentUserId,
          'from_user': currentUserId,
          'offer': offer.toMap(),
          'requestType': 'ice_restart',
          'request_type': 'ice_restart',
          'call_id': callId,
          'callId': callId,
          'conversation_id': conversationId,
          'conversationId': conversationId,
        },
        targetUser: receiverId,
        conversationId: conversationId,
        queueIfDisconnected: true,
      );

      if (SocketService.instance.isConnected) {
        debugPrint('ICE RESTART OFFER SENT');
      } else {
        debugPrint(
          'ICE RESTART OFFER QUEUED; waiting for signaling reconnect',
        );
      }
    } catch (e, st) {
      debugPrint('ICE RESTART SEND ERROR: $e');
      if (kDebugMode) {
        debugPrint(st.toString());
      }
    } finally {
      // Keep a small guard against restart storms. The WebRTC service also has
      // its own restart cooldown, so both layers remain protected.
      Future.delayed(const Duration(seconds: 4), () {
        _iceRestarting = false;
      });
    }
  }

  Future<void> resendOfferToAcceptedReceiver() async {
    if (!_canUpdate) return;
    if (!state.isCaller) return;
    if (_isFinalStatus(state.status)) return;

    final currentUserId = state.currentUserId;
    final receiverId = state.receiverId;

    if (currentUserId == null || receiverId == null) return;

    try {
      await SocketService.instance.ensureConnected();
      if (!SocketService.instance.isConnected) return;

      final existing = await webrtc.currentLocalDescription();
      final offer = existing != null && existing.type == 'offer'
          ? existing
          : await webrtc.createOffer();

      SocketService.instance.emit(
        CallSocketEvents.callOffer,
        {
          'from': currentUserId,
          'from_user': currentUserId,
          'callerName': _currentUserNameForOffer,
          'caller_name': _currentUserNameForOffer,
          'callerAvatar': _currentUserAvatarForOffer,
          'caller_avatar': _currentUserAvatarForOffer,
          'isVideoCall': state.isVideoCall,
          'is_video_call': state.isVideoCall,
          'offer': offer.toMap(),
          if (_callId != null) 'call_id': _callId,
          if (_callId != null) 'callId': _callId,
          if (_conversationId != null) 'conversation_id': _conversationId,
          if (_conversationId != null) 'conversationId': _conversationId,
          'resend_after_call_ready': true,
        },
        targetUser: receiverId,
        conversationId: _conversationId,
        queueIfDisconnected: true,
      );

      debugPrint('CALL OFFER RESENT MANUALLY');
    } catch (e, st) {
      debugPrint('RESEND OFFER ERROR: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> requestVideoUpgrade() async {
    if (!_canUpdate) return;
    if (state.isVideoCall) return;
    if (_switchingVideo) return;
    if (_isFinalStatus(state.status)) return;

    final currentUserId = state.currentUserId?.trim() ?? '';
    final receiverId = state.receiverId?.trim() ?? '';

    if (currentUserId.isEmpty || receiverId.isEmpty) return;

    // Every click creates a fresh transaction id. Accept/Decline for an older
    // request can therefore never resolve this newer request.
    final videoRequestId = _newVideoUpgradeRequestId(currentUserId);
    _activeVideoUpgradeRequestId = videoRequestId;
    _switchingVideo = true;

    try {
      await webrtc.enableVideo();
      await webrtc.setSpeaker(true);

      final offer = await webrtc.createRenegotiationOffer();

      SocketService.instance.emit(
        CallSocketEvents.callRenegotiateOffer,
        <String, dynamic>{
          'from': currentUserId,
          'from_user': currentUserId,
          'offer': offer.toMap(),
          'requestType': 'video_upgrade',
          'request_type': 'video_upgrade',
          'video_request_id': videoRequestId,
          'videoRequestId': videoRequestId,
          if (_callId != null) 'call_id': _callId,
          if (_callId != null) 'callId': _callId,
          if (_conversationId != null) 'conversation_id': _conversationId,
          if (_conversationId != null) 'conversationId': _conversationId,
        },
        targetUser: receiverId,
        conversationId: _conversationId,
        queueIfDisconnected: true,
      );

      _safeState(
        state.copyWith(
          isCameraOff: false,
          isSpeakerOn: true,
          isVideoUpgradeRequesting: true,
          isVideoUpgradeRejected: false,
          clearError: true,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );

      debugPrint('VIDEO UPGRADE REQUEST SENT: $videoRequestId');
    } catch (e, st) {
      debugPrint('Request video upgrade error: $e');
      debugPrint(st.toString());

      if (_activeVideoUpgradeRequestId == videoRequestId) {
        _activeVideoUpgradeRequestId = null;
      }
      _switchingVideo = false;

      try {
        await webrtc.disableVideoHard();
        await webrtc.setSpeaker(false);
      } catch (_) {}

      _safeState(
        state.copyWith(
          isVideoCall: false,
          isCameraOff: true,
          isRemoteCameraOff: true,
          isSpeakerOn: false,
          isVideoUpgradeRequesting: false,
          isVideoUpgradeRejected: false,
          errorMessage: 'Unable to send video request. Please try again.',
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );
    }
  }

  Future<void> acceptVideoUpgrade() async {
    if (!_canUpdate) return;
    if (!state.hasPendingVideoUpgrade) return;
    if (_isFinalStatus(state.status)) return;

    final currentUserId = state.currentUserId?.trim() ?? '';
    final stateReceiverId = state.receiverId?.trim() ?? '';
    final requestSenderId = _pendingVideoUpgradeRequesterId?.trim() ?? '';
    final replyTargetUserId =
        requestSenderId.isNotEmpty ? requestSenderId : stateReceiverId;
    final pendingOffer = state.pendingVideoOffer;
    final videoRequestId = _pendingVideoUpgradeRequestId;

    if (pendingOffer == null) {
      debugPrint('ACCEPT VIDEO UPGRADE SKIPPED: pending offer is missing');
      return;
    }

    if (currentUserId.isEmpty || replyTargetUserId.isEmpty) {
      debugPrint('ACCEPT VIDEO UPGRADE SKIPPED: reply target is missing');
      return;
    }

    debugPrint(
      'VIDEO UPGRADE ACCEPT REPLY TARGET: '
      '$replyTargetUserId '
      '(requestSender=$requestSenderId, stateReceiver=$stateReceiverId)',
    );

    final offer = Map<String, dynamic>.from(pendingOffer);
    _switchingVideo = true;

    try {
      debugPrint(
        'VIDEO UPGRADE ACCEPT START: ${videoRequestId ?? "legacy/no-id"}',
      );

      // Receiver side must apply the incoming video offer BEFORE attaching
      // its camera to the peer connection. The WebRTC service does that in
      // acceptVideoUpgradeOffer().
      final answer = await webrtc.acceptVideoUpgradeOffer(offer);
      await webrtc.setSpeaker(true);

      SocketService.instance.emit(
        CallSocketEvents.callRenegotiateAnswer,
        <String, dynamic>{
          'from': currentUserId,
          'from_user': currentUserId,
          'answer': answer.toMap(),
          'requestType': 'video_upgrade',
          'request_type': 'video_upgrade',
          if (videoRequestId != null && videoRequestId.isNotEmpty)
            'video_request_id': videoRequestId,
          if (videoRequestId != null && videoRequestId.isNotEmpty)
            'videoRequestId': videoRequestId,
          if (_callId != null) 'call_id': _callId,
          if (_callId != null) 'callId': _callId,
          if (_conversationId != null) 'conversation_id': _conversationId,
          if (_conversationId != null) 'conversationId': _conversationId,
        },
        targetUser: replyTargetUserId,
        conversationId: _conversationId,
        queueIfDisconnected: true,
      );

      // Explicitly synchronize the call mode on the other phone too.
      // The same SDP answer is included as a fallback. Normally the requester
      // processes callRenegotiateAnswer first. If that event is missed, this
      // callVideoToggle event can still apply the answer and then switch UI.
      SocketService.instance.emit(
        CallSocketEvents.callVideoToggle,
        <String, dynamic>{
          'from': currentUserId,
          'from_user': currentUserId,
          'isVideoCall': true,
          'is_video_call': true,
          'answer': answer.toMap(),
          'requestType': 'video_upgrade_accepted',
          'request_type': 'video_upgrade_accepted',
          if (videoRequestId != null && videoRequestId.isNotEmpty)
            'video_request_id': videoRequestId,
          if (videoRequestId != null && videoRequestId.isNotEmpty)
            'videoRequestId': videoRequestId,
          if (_callId != null) 'call_id': _callId,
          if (_callId != null) 'callId': _callId,
          if (_conversationId != null) 'conversation_id': _conversationId,
          if (_conversationId != null) 'conversationId': _conversationId,
        },
        targetUser: replyTargetUserId,
        conversationId: _conversationId,
        queueIfDisconnected: true,
      );

      if (!_canUpdate || _isFinalStatus(state.status)) return;

      if (videoRequestId != null && videoRequestId.isNotEmpty) {
        _lastResolvedVideoUpgradeRequestId = videoRequestId;
      }
      _pendingVideoUpgradeRequestId = null;
      _pendingVideoUpgradeRequesterId = null;

      _safeState(
        state.copyWith(
          isVideoCall: true,
          isCameraOff: false,
          isRemoteCameraOff: false,
          isSpeakerOn: true,
          hasPendingVideoUpgrade: false,
          isVideoUpgradeRequesting: false,
          isVideoUpgradeRejected: false,
          clearPendingVideoOffer: true,
          clearError: true,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );

      debugPrint(
        'VIDEO UPGRADE ACCEPTED: ${videoRequestId ?? "legacy/no-id"}',
      );
    } catch (e, st) {
      debugPrint('ACCEPT VIDEO UPGRADE ERROR: $e');
      debugPrint(st.toString());

      // A technical failure is NOT a decline. Keep the pending request so the
      // user can tap Accept again or explicitly tap Decline.
      try {
        await webrtc.disableVideoHard();
      } catch (_) {}

      try {
        await webrtc.setSpeaker(false);
      } catch (_) {}

      if (_canUpdate && !_isFinalStatus(state.status)) {
        _safeState(
          state.copyWith(
            isVideoCall: false,
            isCameraOff: true,
            isRemoteCameraOff: true,
            isSpeakerOn: false,
            isVideoUpgradeRequesting: false,
            isVideoUpgradeRejected: false,
            errorMessage: 'Unable to enable video. Please try again.',
            localRenderer: webrtc.localRenderer,
            remoteRenderer: webrtc.remoteRenderer,
          ),
        );
      }
    } finally {
      _switchingVideo = false;
    }
  }

  Future<void> rejectVideoUpgrade() async {
    if (!_canUpdate) return;
    if (_isFinalStatus(state.status)) return;

    if (!state.hasPendingVideoUpgrade || state.pendingVideoOffer == null) {
      debugPrint('VIDEO UPGRADE DECLINE IGNORED: no pending request');
      return;
    }

    final currentUserId = state.currentUserId?.trim() ?? '';
    final stateReceiverId = state.receiverId?.trim() ?? '';
    final requestSenderId = _pendingVideoUpgradeRequesterId?.trim() ?? '';
    final replyTargetUserId =
        requestSenderId.isNotEmpty ? requestSenderId : stateReceiverId;
    final videoRequestId = _pendingVideoUpgradeRequestId;
    final pendingOffer = Map<String, dynamic>.from(state.pendingVideoOffer!);

    Map<String, dynamic>? declineAnswer;

    try {
      // Complete WebRTC negotiation even though the UI choice is Decline.
      // This returns both peers to a stable signaling state and allows the
      // next video request to work in the same audio call.
      final answer = await webrtc.rejectVideoUpgradeOffer(pendingOffer);
      declineAnswer = Map<String, dynamic>.from(answer.toMap());
      await webrtc.setSpeaker(false);
    } catch (e, st) {
      debugPrint('VIDEO UPGRADE DECLINE SDP ERROR: $e');
      debugPrint(st.toString());

      // Do not silently clear the request if we could not stabilize the SDP.
      // Keeping it pending lets the user retry Decline/Accept rather than
      // corrupting the peer connection state.
      if (_canUpdate) {
        _safeState(
          state.copyWith(
            errorMessage: 'Unable to decline video request. Please try again.',
          ),
        );
      }
      _switchingVideo = false;
      return;
    }

    if (currentUserId.isNotEmpty && replyTargetUserId.isNotEmpty) {
      debugPrint(
        'VIDEO UPGRADE DECLINE REPLY TARGET: '
        '$replyTargetUserId '
        '(requestSender=$requestSenderId, stateReceiver=$stateReceiverId)',
      );
      SocketService.instance.emit(
        CallSocketEvents.callVideoUpgradeRejected,
        <String, dynamic>{
          'from': currentUserId,
          'from_user': currentUserId,
          'reason': 'declined',
          'requestType': 'video_upgrade',
          'request_type': 'video_upgrade',
          if (declineAnswer != null) 'answer': declineAnswer,
          if (videoRequestId != null && videoRequestId.isNotEmpty)
            'video_request_id': videoRequestId,
          if (videoRequestId != null && videoRequestId.isNotEmpty)
            'videoRequestId': videoRequestId,
          if (_callId != null) 'call_id': _callId,
          if (_callId != null) 'callId': _callId,
          if (_conversationId != null) 'conversation_id': _conversationId,
          if (_conversationId != null) 'conversationId': _conversationId,
        },
        targetUser: replyTargetUserId,
        conversationId: _conversationId,
        queueIfDisconnected: true,
      );
    }

    if (videoRequestId != null && videoRequestId.isNotEmpty) {
      _lastResolvedVideoUpgradeRequestId = videoRequestId;
    }
    _pendingVideoUpgradeRequestId = null;
    _pendingVideoUpgradeRequesterId = null;

    _safeState(
      state.copyWith(
        isVideoCall: false,
        isCameraOff: true,
        isRemoteCameraOff: true,
        isSpeakerOn: false,
        hasPendingVideoUpgrade: false,
        isVideoUpgradeRequesting: false,
        isVideoUpgradeRejected: false,
        clearPendingVideoOffer: true,
        clearError: true,
        localRenderer: webrtc.localRenderer,
        remoteRenderer: webrtc.remoteRenderer,
      ),
    );

    _switchingVideo = false;

    debugPrint(
      'VIDEO UPGRADE DECLINE SENT WITH SDP ANSWER: '
      '${videoRequestId ?? "legacy/no-id"}',
    );
  }

  Future<void> switchToAudioCall() async {
    if (!_canUpdate) return;
    if (!state.isVideoCall && !state.isVideoUpgradeRequesting) return;
    if (_isFinalStatus(state.status)) return;

    final currentUserId = state.currentUserId;
    final receiverId = state.receiverId;

    if (currentUserId == null || receiverId == null) return;

    try {
      await webrtc.disableVideoHard();
      await webrtc.setSpeaker(false);

      SocketService.instance.emit(
        CallSocketEvents.callVideoToggle,
        {
          'from': currentUserId,
          'from_user': currentUserId,
          'isVideoCall': false,
          'is_video_call': false,
          if (_callId != null) 'call_id': _callId,
          if (_callId != null) 'callId': _callId,
          if (_conversationId != null) 'conversation_id': _conversationId,
          if (_conversationId != null) 'conversationId': _conversationId,
        },
        targetUser: receiverId,
        conversationId: _conversationId,
        queueIfDisconnected: true,
      );

      _activeVideoUpgradeRequestId = null;
      _pendingVideoUpgradeRequestId = null;

      _safeState(
        state.copyWith(
          isVideoCall: false,
          isCameraOff: true,
          isRemoteCameraOff: true,
          isSpeakerOn: false,
          isVideoUpgradeRequesting: false,
          isVideoUpgradeRejected: false,
          hasPendingVideoUpgrade: false,
          clearPendingVideoOffer: true,
          clearError: true,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );
    } catch (e, st) {
      debugPrint('Switch to audio error: $e');
      debugPrint(st.toString());
    } finally {
      _switchingVideo = false;
    }
  }

  Future<void> switchToVideoCall() => requestVideoUpgrade();

  void toggleCamera() {
    if (!_canUpdate) return;
    if (!state.isVideoCall) return;

    final currentUserId = state.currentUserId;
    final receiverId = state.receiverId;

    final newCameraOff = !state.isCameraOff;

    webrtc.toggleCamera(!newCameraOff);

    _safeState(
      state.copyWith(
        isCameraOff: newCameraOff,
        localRenderer: webrtc.localRenderer,
        remoteRenderer: webrtc.remoteRenderer,
      ),
    );

    if (currentUserId != null && receiverId != null) {
      SocketService.instance.emit(
        CallSocketEvents.callVideoToggle,
        {
          'from': currentUserId,
          'from_user': currentUserId,
          'cameraOff': newCameraOff,
          if (_callId != null) 'call_id': _callId,
          if (_callId != null) 'callId': _callId,
          if (_conversationId != null) 'conversation_id': _conversationId,
          if (_conversationId != null) 'conversationId': _conversationId,
        },
        targetUser: receiverId,
        conversationId: _conversationId,
        queueIfDisconnected: true,
      );
    }
  }

  void clearVideoUpgradeRejectedFlag() {
    if (!_canUpdate) return;
    _safeState(state.copyWith(isVideoUpgradeRejected: false));
  }

  void _startCallTimeout() {
    _timeoutTimer?.cancel();

    _timeoutTimer = Timer(const Duration(seconds: 30), () async {
      if (!_canUpdate) return;
      if (state.status == CallStatus.connected) return;
      if (_isFinalStatus(state.status)) return;

      final currentUserId = state.currentUserId;
      final receiverId = state.receiverId;

      if (currentUserId != null && receiverId != null) {
        SocketService.instance.emit(
          CallSocketEvents.callTimeout,
          {
            'from': currentUserId,
            'from_user': currentUserId,
            'reason': 'timeout',
            if (_callId != null) 'call_id': _callId,
            if (_callId != null) 'callId': _callId,
            if (_conversationId != null) 'conversation_id': _conversationId,
            if (_conversationId != null) 'conversationId': _conversationId,
          },
          targetUser: receiverId,
          conversationId: _conversationId,
          queueIfDisconnected: true,
        );
      }

      await _finishCall(CallStatus.timeout, emitSocket: false);
    });
  }

  Future<void> setConnected() async {
    if (!_canUpdate) return;
    if (state.status == CallStatus.connected) return;
    if (_isFinalStatus(state.status)) return;

    _timeoutTimer?.cancel();


    try {
      await CallSoundService.instance.stop();
    } catch (_) {}

    final useSpeaker = state.isVideoCall;
    await webrtc.setSpeaker(useSpeaker);

    _safeState(
      state.copyWith(
        status: CallStatus.connected,
        isSpeakerOn: useSpeaker,
      ),
    );

    _startDurationTimer();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_canUpdate) return;
      if (state.status != CallStatus.connected) return;

      _safeState(
        state.copyWith(
          duration: state.duration + const Duration(seconds: 1),
        ),
      );
    });
  }

  void toggleMic() {
    if (!_canUpdate) return;

    final newValue = !state.isMicOff;

    _safeState(state.copyWith(isMicOff: newValue));

    webrtc.toggleMic(!newValue);
  }

  void toggleSpeaker() {
    if (!_canUpdate) return;

    final newValue = !state.isSpeakerOn;

    _safeState(state.copyWith(isSpeakerOn: newValue));

    webrtc.setSpeaker(newValue);
  }

  Future<void> switchCamera() async {
    if (!_canUpdate) return;
    if (!state.isVideoCall) return;
    if (state.isCameraOff) return;

    try {
      await webrtc.switchCamera();
    } catch (e, st) {
      debugPrint('Switch camera error: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> rejectCall() async {
    if (!_canUpdate) return;

    final currentUserId = state.currentUserId;
    final receiverId = state.receiverId;

    if (currentUserId != null &&
        currentUserId.trim().isNotEmpty &&
        receiverId != null &&
        receiverId.trim().isNotEmpty) {
      SocketService.instance.emit(
        CallSocketEvents.callReject,
        {
          'from': currentUserId,
          'from_user': currentUserId,
          'reason': 'rejected',
          if (_callId != null) 'call_id': _callId,
          if (_callId != null) 'callId': _callId,
          if (_conversationId != null) 'conversation_id': _conversationId,
          if (_conversationId != null) 'conversationId': _conversationId,
        },
        targetUser: receiverId,
        conversationId: _conversationId,
        queueIfDisconnected: false,
      );

      // Give the socket a very small time window to send call_reject.
      await Future.delayed(const Duration(milliseconds: 180));
    }

    await _finishCall(
      CallStatus.rejected,
      emitSocket: false,
      disconnectSocket: true,
    );
  }

  String? _backendActionForFinish(
    CallStatus finalStatus,
    CallState beforeFinish,
  ) {
    final wasConnected = beforeFinish.status == CallStatus.connected;

    switch (finalStatus) {
      case CallStatus.rejected:
        return beforeFinish.isCaller ? 'cancel' : 'reject';
      case CallStatus.timeout:
        return beforeFinish.isCaller ? 'cancel' : 'missed';
      case CallStatus.missed:
        return beforeFinish.isCaller ? 'cancel' : 'missed';
      case CallStatus.failed:
        return beforeFinish.isCaller ? 'cancel' : 'leave';
      case CallStatus.ended:
        if (!wasConnected) {
          return beforeFinish.isCaller ? 'cancel' : 'reject';
        }
        return beforeFinish.isCaller ? 'ended' : 'leave';
      case CallStatus.busy:
        // Busy is normally received from the remote side; no local API write.
        return null;
      case CallStatus.connected:
      case CallStatus.calling:
      case CallStatus.ringing:
      case CallStatus.incoming:
      case CallStatus.idle:
        return null;
    }
  }

  Future<void> _updateBackendCallAction(String action) async {
    final callId = _callId?.trim() ?? '';
    if (callId.isEmpty) {
      debugPrint('CALL BACKEND ACTION SKIPPED [$action]: callId is empty');
      return;
    }

    // Django currently declares calls/<int:call_id>/status/.
    // Fail locally instead of sending a UUID and getting a confusing 404.
    if (int.tryParse(callId) == null) {
      debugPrint(
        'CALL BACKEND ACTION SKIPPED [$action]: expected numeric callId, got $callId',
      );
      return;
    }

    try {
      await CallApi.updateCallAction(
        callId: callId,
        action: action,
      );
    } catch (e) {
      debugPrint('CALL BACKEND ACTION ERROR [$action]: $e');
    }
  }

  Future<void> endCall({bool emitSocket = true}) async {
    await _finishCall(CallStatus.ended, emitSocket: emitSocket);
  }

  Future<void> cancelCall() async {
    await _finishCall(CallStatus.ended, emitSocket: true);
  }

  Future<void> _finishCall(
    CallStatus finalStatus, {
    required bool emitSocket,
    bool disconnectSocket = true,
    bool updateBackend = true,
  }) async {
    if (!_canUpdate) return;
    if (_finishing) return;
    if (_isFinalStatus(state.status)) return;

    _finishing = true;

    final oldState = state;
    final backendAction = _backendActionForFinish(finalStatus, oldState);

    if (updateBackend && backendAction != null) {
      await _updateBackendCallAction(backendAction);
    }

    try {
      await CallSoundService.instance.stop();
    } catch (_) {}

    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    if (emitSocket) {
      final currentUserId = oldState.currentUserId;
      final receiverId = oldState.receiverId;

      if (currentUserId != null && receiverId != null) {
        String event = CallSocketEvents.callEnd;

        if (finalStatus == CallStatus.rejected) {
          event = CallSocketEvents.callReject;
        } else if (finalStatus == CallStatus.timeout ||
            finalStatus == CallStatus.missed) {
          event = CallSocketEvents.callTimeout;
        }

        // For a 1-to-1 call, a normal red-button hangup always notifies
        // the other device with call_end. Backend lifecycle semantics stay
        // unchanged: caller -> ended, receiver -> leave.

        SocketService.instance.emit(
          event,
          <String, dynamic>{
            'from': currentUserId,
            'from_user': currentUserId,
            'reason': backendAction ?? finalStatus.name,
            if (_callId != null) 'call_id': _callId,
            if (_callId != null) 'callId': _callId,
            if (_conversationId != null) 'conversation_id': _conversationId,
            if (_conversationId != null) 'conversationId': _conversationId,
          },
          targetUser: receiverId,
          conversationId: _conversationId,
          queueIfDisconnected: false,
        );

        // Give the control frame a small chance to leave the socket before close.
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }

    _safeState(
      oldState.copyWith(
        status: finalStatus,
        clearRenderers: true,
        duration: oldState.duration,
      ),
    );

    await Future.delayed(const Duration(milliseconds: 180));

    try {
      await webrtc.dispose();
      await webrtc.disposeRenderers();
    } catch (e) {
      debugPrint('CALL WEBRTC DISPOSE ERROR: $e');
    }

    _removeSocketEvents();

    if (disconnectSocket) {
      await _disconnectConversationCallSocket();
    }

    try {
      await NotificationService.endAllNativeCalls();
    } catch (e) {
      debugPrint('CALL PROVIDER CALLKIT CLEANUP ERROR: $e');
    }

    try {
      GlobalCallHandler.instance.markCallScreenClosed();
    } catch (e) {
      debugPrint('CALL PROVIDER GLOBAL FLAG CLEANUP ERROR: $e');
    }

    SocketService.instance.clearActiveCallContext(callId: _callId);

    _conversationId = null;
    _callId = null;
    _waitingForOfferAfterCallKitAccept = false;
    _iceRestarting = false;
    _answeringOffer = false;
    _remoteAnswerApplied = false;
    _lastAnsweredOfferFingerprint = null;
    _activeVideoUpgradeRequestId = null;
    _pendingVideoUpgradeRequestId = null;
    _pendingVideoUpgradeRequesterId = null;
    _lastResolvedVideoUpgradeRequestId = null;
    _switchingVideo = false;
    _finishing = false;
  }

  Future<void> _disconnectConversationCallSocket() async {
    try {
      debugPrint('CALL PROVIDER: disconnecting conversation call socket');

      await SocketService.instance.disconnect(
        clearHandlers: false,
        clearQueue: true,
        clearCache: true,
        forgetUrl: true,
      );

      debugPrint('CALL PROVIDER: conversation call socket disconnected');
    } catch (e, st) {
      debugPrint('CALL PROVIDER SOCKET DISCONNECT ERROR: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> resetCall() async {
    try {
      await CallSoundService.instance.stop();
    } catch (_) {}

    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    _finishing = false;
    _switchingVideo = false;
    _waitingForOfferAfterCallKitAccept = false;
    _iceRestarting = false;
    _answeringOffer = false;
    _remoteAnswerApplied = false;
    _lastAnsweredOfferFingerprint = null;
    _activeVideoUpgradeRequestId = null;
    _pendingVideoUpgradeRequestId = null;
    _pendingVideoUpgradeRequesterId = null;
    _lastResolvedVideoUpgradeRequestId = null;
    _conversationId = null;
    _callId = null;

    _removeSocketEvents();

    try {
      await _disconnectConversationCallSocket();
    } catch (_) {}

    try {
      await NotificationService.endAllNativeCalls();
    } catch (_) {}

    try {
      GlobalCallHandler.instance.markCallScreenClosed();
    } catch (_) {}

    _safeState(const CallState());

    await Future.delayed(const Duration(milliseconds: 200));

    try {
      await webrtc.dispose();
      await webrtc.disposeRenderers();
    } catch (_) {}
  }

  bool _isFinalStatus(CallStatus status) {
    return status == CallStatus.ended ||
        status == CallStatus.rejected ||
        status == CallStatus.timeout ||
        status == CallStatus.busy ||
        status == CallStatus.failed ||
        status == CallStatus.missed;
  }

  Future<void> disposeCall() async {
    try {
      await CallSoundService.instance.stop();
    } catch (_) {}

    _disposed = true;

    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    _removeSocketEvents();

    try {
      await _disconnectConversationCallSocket();
    } catch (_) {}

    try {
      await NotificationService.endAllNativeCalls();
    } catch (_) {}

    try {
      GlobalCallHandler.instance.markCallScreenClosed();
    } catch (_) {}

    if (mounted) {
      state = const CallState();
    }

    _conversationId = null;
    _callId = null;
    _waitingForOfferAfterCallKitAccept = false;
    _iceRestarting = false;
    _answeringOffer = false;
    _remoteAnswerApplied = false;
    _lastAnsweredOfferFingerprint = null;
    _activeVideoUpgradeRequestId = null;
    _pendingVideoUpgradeRequestId = null;
    _pendingVideoUpgradeRequesterId = null;
    _lastResolvedVideoUpgradeRequestId = null;
    _finishing = false;
    _switchingVideo = false;

    await Future.delayed(const Duration(milliseconds: 200));

    try {
      await webrtc.dispose();
      await webrtc.disposeRenderers();
    } catch (_) {}
  }

  void _removeSocketEventsOnly() {
    if (!_socketEventsListening) {
      debugPrint('CALL SOCKET EVENTS ALREADY REMOVED - SKIP');
      return;
    }

    final socket = SocketService.instance;

    socket.off(CallSocketEvents.callOffer, _onCallOffer);
    socket.off(CallSocketEvents.callAnswer, _onCallAnswer);
    socket.off(CallSocketEvents.iceCandidate, _onIceCandidate);
    socket.off(CallSocketEvents.callRenegotiateOffer, _onRenegotiateOffer);
    socket.off(CallSocketEvents.callRenegotiateAnswer, _onRenegotiateAnswer);
    socket.off(CallSocketEvents.callVideoToggle, _onVideoToggle);
    socket.off(
      CallSocketEvents.callVideoUpgradeRejected,
      _onVideoUpgradeRejected,
    );
    socket.off(CallSocketEvents.callReject, _onCallReject);
    socket.off(CallSocketEvents.callEnd, _onCallEnd);
    socket.off(CallSocketEvents.callLeave, _onCallLeave);
    socket.off(CallSocketEvents.callBusy, _onCallBusy);
    socket.off(CallSocketEvents.callTimeout, _onCallTimeout);

    _socketEventsListening = false;
  }

  void _removeSocketEvents() {
    _removeSocketEventsOnly();
  }

  @override
  void dispose() {
    Future.microtask(() async {
      try {
        await CallSoundService.instance.stop();
      } catch (_) {}
    });

    _disposed = true;

    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    _removeSocketEvents();

    Future.microtask(() async {
      try {
        await webrtc.dispose();
        await webrtc.disposeRenderers();
      } catch (_) {}
    });

    super.dispose();
  }
}