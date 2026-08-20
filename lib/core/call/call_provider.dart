// lib/core/call/call_provider.dart

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hiddenly/core/call/call_api.dart';
import 'package:hiddenly/core/call/call_socket_service.dart';
import 'package:hiddenly/core/call/call_sound_service.dart';
import 'package:hiddenly/core/call/call_state.dart';
import 'package:hiddenly/core/call/global_call_handler.dart';
import 'package:hiddenly/core/call/call_notification.dart';
import 'package:hiddenly/core/call/webrct_servide.dart';

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

  String _generateCallId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();

    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
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
    try {
      _disposed = false;
      _finishing = false;
      _switchingVideo = false;
      _waitingForOfferAfterCallKitAccept = false;
      _iceRestarting = false;

      final normalizedConversationId = conversationId?.trim() ?? '';
      if (normalizedConversationId.isEmpty) {
        throw ArgumentError('conversationId is required for a call');
      }

      _conversationId = normalizedConversationId;

      final normalizedCallId = callId?.trim() ?? '';
      _callId = normalizedCallId.isNotEmpty
          ? normalizedCallId
          : (isCaller ? _generateCallId() : null);

      _currentUserNameForOffer = currentUserName.trim();
      _currentUserAvatarForOffer = currentUserAvatar.trim();
      _answeringOffer = false;
      _remoteAnswerApplied = false;
      _lastAnsweredOfferFingerprint = null;

      SocketService.instance.setActiveCallContext(
        callId: _callId,
        conversationId: _conversationId,
      );

      await SocketService.instance.ensureConnected();
      if (!SocketService.instance.isConnected) {
        throw StateError('Call signaling socket is not connected');
      }

      debugPrint('CALL PROVIDER CALL ID: $_callId');

      _durationTimer?.cancel();
      _timeoutTimer?.cancel();

      _removeSocketEvents();

      _safeState(const CallState());

      await webrtc.dispose();
      await Future.delayed(const Duration(milliseconds: 250));
      await webrtc.disposeRenderers();

      if (!_canUpdate) return;

      final remoteName = _cleanName(name);
      final remoteAvatar = _cleanAvatar(avatarUrl);

      assert(
        remoteName != currentUserName.trim(),
        'CallState.name must be the OTHER user name, not current user name.',
      );

      _safeState(
        CallState(
          status: isCaller ? CallStatus.calling : CallStatus.ringing,
          currentUserId: currentUserId,
          receiverId: receiverId,
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

      try {
        if (isCaller) {
          await CallSoundService.instance.playOutgoingTone();
        } else {
          await CallSoundService.instance.stop();
        }
      } catch (e) {
        debugPrint('Call sound start error: $e');
      }

      _listenSocketEvents();

      await webrtc.initRenderers();

      await webrtc.createConnection(
        isVideoCall: isVideoCall,
        onIceCandidate: (candidate) {
          if (!_canUpdate || _isFinalStatus(state.status)) return;

          SocketService.instance.emit(
            CallSocketEvents.iceCandidate,
            {
              'from': currentUserId,
              'candidate': candidate.toMap(),
              if (_callId != null) 'call_id': _callId,
              if (_callId != null) 'callId': _callId,
              if (_conversationId != null) 'conversation_id': _conversationId,
              if (_conversationId != null) 'conversationId': _conversationId,
            },
            targetUser: receiverId,
            conversationId: _conversationId,
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
        _startCallTimeout();

        final offer = await webrtc.createOffer();

        SocketService.instance.emit(
          CallSocketEvents.callOffer,
          {
            'from': currentUserId,
            'from_user': currentUserId,
            'callerName': currentUserName.trim(),
            'caller_name': currentUserName.trim(),
            'callerAvatar': currentUserAvatar.trim(),
            'caller_avatar': currentUserAvatar.trim(),
            'isVideoCall': isVideoCall,
            'is_video_call': isVideoCall,
            'offer': offer.toMap(),
            if (_callId != null) 'call_id': _callId,
            if (_callId != null) 'callId': _callId,
            if (_conversationId != null) 'conversation_id': _conversationId,
            if (_conversationId != null) 'conversationId': _conversationId,
          },
          targetUser: receiverId,
          conversationId: _conversationId,
          queueIfDisconnected: true,
        );

        return;
      }

      /*
        Receiver side:

        Normal foreground receiver:
        - incomingOffer is available immediately.
        - We set remote description and send answer.

        Background/killed CallKit receiver:
        - User accepts native call first.
        - There may be no offer yet.
        - CallWaitingScreen sends call_ready.
        - SocketService resends cached call_offer once.
        - Receiver receives call_offer and answers in _handleCallOffer().
      */
      if (incomingOffer == null) {
        _waitingForOfferAfterCallKitAccept = true;
        debugPrint('RECEIVER STARTED WITHOUT OFFER. WAITING FOR CALL_OFFER...');
        return;
      }

      await _answerIncomingOffer(
        offer: incomingOffer,
        currentUserId: currentUserId,
        receiverId: receiverId,
      );
    } catch (e, st) {
      debugPrint('Start call error: $e');
      debugPrint(st.toString());

      if (_canUpdate) {
        await _finishCall(CallStatus.failed, emitSocket: false);
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

    final rawOffer = payload['offer'];

    Map<String, dynamic>? offer;

    if (rawOffer is Map<String, dynamic>) {
      offer = Map<String, dynamic>.from(rawOffer);
    } else if (rawOffer is Map) {
      offer = Map<String, dynamic>.from(rawOffer);
    } else {
      final type = payload['type']?.toString() ?? '';
      final sdp = payload['sdp']?.toString() ?? '';

      if (type.trim().isNotEmpty && sdp.trim().isNotEmpty) {
        offer = {
          'type': type,
          'sdp': sdp,
        };
      }
    }

    if (offer == null) {
      debugPrint('CALL OFFER MISSING SDP: $payload');
      return;
    }

    final offerType = offer['type']?.toString() ?? '';
    final offerSdp = offer['sdp']?.toString() ?? '';

    if (offerType.trim().isEmpty || offerSdp.trim().isEmpty) {
      debugPrint('CALL OFFER INVALID SDP: $offer');
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
    final offerType = offer['type']?.toString().trim() ?? '';
    final offerSdp = offer['sdp']?.toString().trim() ?? '';

    if (offerType.isEmpty || offerSdp.isEmpty) {
      debugPrint('ANSWER INCOMING OFFER ERROR: invalid offer');
      return;
    }

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
      await webrtc.setRemoteDescription(offer);
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

      _safeState(
        state.copyWith(
          incomingOffer: offer,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );

      debugPrint('CALL ANSWER SENT');
    } catch (e, st) {
      debugPrint('ANSWER INCOMING OFFER ERROR: $e');
      debugPrint(st.toString());
      await _finishCall(CallStatus.failed, emitSocket: false);
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

    _safeState(
      state.copyWith(
        hasPendingVideoUpgrade: true,
        pendingVideoOffer: Map<String, dynamic>.from(rawOffer),
        isVideoUpgradeRequesting: false,
        isVideoUpgradeRejected: false,
      ),
    );
  }

  Future<void> _handleRenegotiateAnswer(Map<String, dynamic> data) async {
    if (!_canUpdate || _isFinalStatus(state.status)) return;

    final rawPayload = data['payload'];
    if (rawPayload is! Map) return;

    final payload = Map<String, dynamic>.from(rawPayload);
    if (!_matchesActiveEvent(payload)) return;
    final rawAnswer = payload['answer'];

    if (rawAnswer is! Map) return;

    final requestType = payload['requestType']?.toString() ??
        payload['request_type']?.toString() ??
        '';

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

      _safeState(
        state.copyWith(
          isVideoCall: true,
          isCameraOff: false,
          isRemoteCameraOff: false,
          isSpeakerOn: true,
          isVideoUpgradeRequesting: false,
          isVideoUpgradeRejected: false,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );
    } catch (e, st) {
      debugPrint('Renegotiation answer error: $e');
      debugPrint(st.toString());

      if (requestType == 'ice_restart') {
        return;
      }

      await webrtc.disableVideoHard();

      _safeState(
        state.copyWith(
          isVideoCall: false,
          isCameraOff: true,
          isRemoteCameraOff: true,
          isSpeakerOn: false,
          isVideoUpgradeRequesting: false,
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

    final fromUserId = payload['from']?.toString();

    if (fromUserId != null &&
        state.currentUserId != null &&
        fromUserId == state.currentUserId.toString()) {
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

    if (payload.containsKey('isVideoCall') ||
        payload.containsKey('is_video_call')) {
      final remoteIsVideoCall = payload['isVideoCall'] == true ||
          payload['is_video_call'] == true ||
          payload['isVideoCall']?.toString() == 'true' ||
          payload['is_video_call']?.toString() == 'true';

      if (!remoteIsVideoCall) {
        await webrtc.disableVideoHard();
        await webrtc.setSpeaker(false);
      }

      _safeState(
        state.copyWith(
          isVideoCall: remoteIsVideoCall,
          isCameraOff: !remoteIsVideoCall,
          isRemoteCameraOff: !remoteIsVideoCall,
          isSpeakerOn: remoteIsVideoCall ? state.isSpeakerOn : false,
          isVideoUpgradeRequesting: false,
          hasPendingVideoUpgrade: false,
          clearPendingVideoOffer: true,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );
    }
  }

  Future<void> _handleVideoUpgradeRejected(Map<String, dynamic> data) async {
    if (!_canUpdate || _isFinalStatus(state.status)) return;

    final payload = _payloadFrom(data);
    if (!_matchesActiveEvent(payload)) return;

    await webrtc.disableVideoHard();
    await webrtc.setSpeaker(false);

    _safeState(
      state.copyWith(
        isVideoCall: false,
        isCameraOff: true,
        isRemoteCameraOff: true,
        isSpeakerOn: false,
        isVideoUpgradeRequesting: false,
        isVideoUpgradeRejected: true,
        localRenderer: webrtc.localRenderer,
        remoteRenderer: webrtc.remoteRenderer,
      ),
    );

    _switchingVideo = false;
  }

  Future<void> _handleCallReject(Map<String, dynamic> data) async {
    final payload = _payloadFrom(data);
    if (!_matchesActiveEvent(payload)) return;
    if (!_canUpdate || _isFinalStatus(state.status)) return;

    debugPrint('CALL REJECT RECEIVED: $data');

    await _finishCall(
      CallStatus.rejected,
      emitSocket: false,
      disconnectSocket: true,
    );
  }

  Future<void> _handleCallEnd(Map<String, dynamic> data) async {
    final payload = _payloadFrom(data);
    if (!_matchesActiveEvent(payload)) return;
    if (!_canUpdate || _isFinalStatus(state.status)) return;

    debugPrint('CALL END RECEIVED: $data');

    await _finishCall(
      CallStatus.ended,
      emitSocket: false,
      disconnectSocket: true,
    );
  }

  Future<void> _handleCallLeave(Map<String, dynamic> data) async {
    final payload = _payloadFrom(data);
    if (!_matchesActiveEvent(payload)) return;
    if (!_canUpdate) return;
    await _finishCall(CallStatus.ended, emitSocket: false);
  }

  Future<void> _handleCallBusy(Map<String, dynamic> data) async {
    final payload = _payloadFrom(data);
    if (!_matchesActiveEvent(payload)) return;
    if (!_canUpdate) return;
    await _finishCall(CallStatus.busy, emitSocket: false);
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
    );
  }

  Future<void> _restartIceAndSendOffer() async {
    if (!_canUpdate) return;
    if (_iceRestarting) return;
    if (_isFinalStatus(state.status)) return;

    final currentUserId = state.currentUserId;
    final receiverId = state.receiverId;

    if (currentUserId == null || receiverId == null) return;

    _iceRestarting = true;

    try {
      await SocketService.instance.ensureConnected();
      if (!SocketService.instance.isConnected) return;

      final offer = await webrtc.restartIce();

      SocketService.instance.emit(
        CallSocketEvents.callRenegotiateOffer,
        {
          'from': currentUserId,
          'from_user': currentUserId,
          'offer': offer.toMap(),
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

      debugPrint('ICE RESTART OFFER SENT');
    } catch (e, st) {
      debugPrint('ICE RESTART SEND ERROR: $e');
      debugPrint(st.toString());
    } finally {
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

    final currentUserId = state.currentUserId;
    final receiverId = state.receiverId;

    if (currentUserId == null || receiverId == null) return;

    _switchingVideo = true;

    try {
      await webrtc.enableVideo();
      await webrtc.setSpeaker(true);

      final offer = await webrtc.createRenegotiationOffer();

      SocketService.instance.emit(
        CallSocketEvents.callRenegotiateOffer,
        {
          'from': currentUserId,
          'from_user': currentUserId,
          'offer': offer.toMap(),
          'requestType': 'video_upgrade',
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
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );
    } catch (e, st) {
      debugPrint('Request video upgrade error: $e');
      debugPrint(st.toString());

      _switchingVideo = false;

      await webrtc.disableVideoHard();
      await webrtc.setSpeaker(false);

      _safeState(
        state.copyWith(
          isVideoCall: false,
          isCameraOff: true,
          isRemoteCameraOff: true,
          isSpeakerOn: false,
          isVideoUpgradeRequesting: false,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );
    }
  }

  Future<void> acceptVideoUpgrade() async {
    if (!_canUpdate) return;
    if (!state.hasPendingVideoUpgrade) return;
    if (state.pendingVideoOffer == null) return;
    if (_isFinalStatus(state.status)) return;

    final currentUserId = state.currentUserId;
    final receiverId = state.receiverId;

    if (currentUserId == null || receiverId == null) return;

    _switchingVideo = true;

    try {
      await webrtc.enableVideo();
      await webrtc.setSpeaker(true);

      final answer = await webrtc.handleRenegotiationOffer(
        state.pendingVideoOffer!,
      );

      SocketService.instance.emit(
        CallSocketEvents.callRenegotiateAnswer,
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
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );
    } catch (e, st) {
      debugPrint('Accept video upgrade error: $e');
      debugPrint(st.toString());
      await rejectVideoUpgrade();
    } finally {
      _switchingVideo = false;
    }
  }

  Future<void> rejectVideoUpgrade() async {
    if (!_canUpdate) return;

    final currentUserId = state.currentUserId;
    final receiverId = state.receiverId;

    if (currentUserId != null && receiverId != null) {
      SocketService.instance.emit(
        CallSocketEvents.callVideoUpgradeRejected,
        {
          'from': currentUserId,
          'from_user': currentUserId,
          'reason': 'declined',
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

    _safeState(
      state.copyWith(
        hasPendingVideoUpgrade: false,
        clearPendingVideoOffer: true,
      ),
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

      _safeState(
        state.copyWith(
          isVideoCall: false,
          isCameraOff: true,
          isRemoteCameraOff: true,
          isSpeakerOn: false,
          isVideoUpgradeRequesting: false,
          hasPendingVideoUpgrade: false,
          clearPendingVideoOffer: true,
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

    await _updateBackendCallStatus('accept');

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

  String _backendStatusFor(CallStatus status) {
    switch (status) {
      case CallStatus.rejected:
        return 'rejected';
      case CallStatus.busy:
        return 'busy';
      case CallStatus.timeout:
      case CallStatus.missed:
        return 'missed';
      case CallStatus.failed:
        return 'failed';
      case CallStatus.ended:
      case CallStatus.connected:
      default:
        return 'ended';
    }
  }

  Future<void> _updateBackendCallStatus(String status) async {
    final callId = _callId;

    if (callId == null || callId.trim().isEmpty) return;

    try {
      await CallApi.updateCallStatus(
        callId: callId,
        status: status,
      );
    } catch (e) {
      debugPrint('CALL BACKEND STATUS UPDATE ERROR [$status]: $e');
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
  }) async {
    if (!_canUpdate) return;
    if (_finishing) return;
    if (_isFinalStatus(state.status)) return;

    _finishing = true;

    final backendStatus = _backendStatusFor(finalStatus);
    await _updateBackendCallStatus(backendStatus);

    try {
      await CallSoundService.instance.stop();
    } catch (_) {}

    final oldState = state;

    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    if (emitSocket) {
      final currentUserId = oldState.currentUserId;
      final receiverId = oldState.receiverId;

      if (currentUserId != null && receiverId != null) {
        SocketService.instance.emit(
          CallSocketEvents.callEnd,
          {
            'from': currentUserId,
            'from_user': currentUserId,
            if (_callId != null) 'call_id': _callId,
            if (_callId != null) 'callId': _callId,
            if (_conversationId != null) 'conversation_id': _conversationId,
            if (_conversationId != null) 'conversationId': _conversationId,
          },
          targetUser: receiverId,
          conversationId: _conversationId,
          queueIfDisconnected: false,
        );
      }
    }

    _safeState(
      oldState.copyWith(
        status: finalStatus,
        clearRenderers: true,
        duration: oldState.duration,
      ),
    );

    await Future.delayed(const Duration(milliseconds: 250));

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