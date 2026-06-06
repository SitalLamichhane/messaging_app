// core/call/call_provider.dart
// IMPORTANT:
// Add this field in CallState first:
// final bool isRemoteCameraOff;
//
// Default:
// this.isRemoteCameraOff = false,
//
// Add in copyWith:
// bool? isRemoteCameraOff,
//
// Then set:
// isRemoteCameraOff: isRemoteCameraOff ?? this.isRemoteCameraOff,

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:messaging_app/core/call/call_socket_service.dart';
import 'package:messaging_app/core/call/call_state.dart';
import 'package:messaging_app/core/call/webrct_servide.dart';

final callProvider = StateNotifierProvider<CallNotifier, CallState>((ref) {
  final notifier = CallNotifier();

  ref.onDispose(() {
    notifier.disposeCall();
  });

  return notifier;
});

class CallNotifier extends StateNotifier<CallState> {
  CallNotifier() : super(const CallState());

  final WebRTCService webrtc = WebRTCService();

  Timer? _durationTimer;
  Timer? _timeoutTimer;

  bool _disposed = false;
  bool _finishing = false;
  bool _switchingVideo = false;

  String? _conversationId;

  bool get _canUpdate => mounted && !_disposed;

  void _safeState(CallState newState) {
    if (!_canUpdate) return;
    state = newState;
  }

  Future<void> startCall({
    required String currentUserId,
    required String receiverId,
    required String currentUserName,
    required String currentUserAvatar,
    required String name,
    required String avatarUrl,
    required bool isVideoCall,
    required bool isCaller,
    String? conversationId,
    Map<String, dynamic>? incomingOffer,
  }) async {
    try {
      _disposed = false;
      _finishing = false;
      _switchingVideo = false;
      _conversationId = conversationId;

      _durationTimer?.cancel();
      _timeoutTimer?.cancel();
      _removeSocketEvents();

      _safeState(const CallState());

      await webrtc.dispose();
      await Future.delayed(const Duration(milliseconds: 250));
      await webrtc.disposeRenderers();

      if (!_canUpdate) return;

      _safeState(
        CallState(
          status: isCaller ? CallStatus.calling : CallStatus.ringing,
          currentUserId: currentUserId,
          receiverId: receiverId,
          name: name,
          avatarUrl: avatarUrl,
          isVideoCall: isVideoCall,
          isCaller: isCaller,
          incomingOffer: incomingOffer,
          isCameraOff: !isVideoCall,
          isRemoteCameraOff: !isVideoCall,
          duration: Duration.zero,
        ),
      );

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
            },
            targetUser: receiverId,
            conversationId: _conversationId,
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

          setConnected();
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
            'callerName': currentUserName,
            'callerAvatar': currentUserAvatar,
            'isVideoCall': isVideoCall,
            'offer': offer.toMap(),
          },
          targetUser: receiverId,
          conversationId: _conversationId,
        );
      } else {
        if (incomingOffer == null) {
          await _finishCall(CallStatus.failed, emitSocket: false);
          return;
        }

        await webrtc.setRemoteDescription(incomingOffer);

        final answer = await webrtc.createAnswer();

        SocketService.instance.emit(
          CallSocketEvents.callAnswer,
          {
            'from': currentUserId,
            'answer': answer.toMap(),
          },
          targetUser: receiverId,
          conversationId: _conversationId,
        );
      }
    } catch (e) {
      debugPrint('Start call error: $e');

      if (_canUpdate) {
        await _finishCall(CallStatus.failed, emitSocket: false);
      }
    }
  }

  void _listenSocketEvents() {
    _removeSocketEventsOnly();

    SocketService.instance.on(CallSocketEvents.callAnswer, (data) async {
      if (!_canUpdate || _isFinalStatus(state.status)) return;

      _timeoutTimer?.cancel();

      final payload = data['payload'];
      if (payload == null || payload['answer'] == null) return;

      try {
        await webrtc.setRemoteDescription(payload['answer']);

        _safeState(
          state.copyWith(
            localRenderer: webrtc.localRenderer,
            remoteRenderer: webrtc.remoteRenderer,
          ),
        );

        setConnected();
      } catch (e) {
        debugPrint('Call answer error: $e');
        await _finishCall(CallStatus.failed, emitSocket: false);
      }
    });

    SocketService.instance.on(CallSocketEvents.iceCandidate, (data) async {
      if (!_canUpdate || _isFinalStatus(state.status)) return;

      final payload = data['payload'];
      if (payload == null || payload['candidate'] == null) return;

      try {
        await webrtc.addCandidate(payload['candidate']);
      } catch (e) {
        debugPrint('ICE error: $e');
      }
    });

    // Audio -> Video request received.
    // Receiver does NOT auto-request again. It only shows dialog.
    SocketService.instance.on(CallSocketEvents.callRenegotiateOffer, (data) async {
      if (!_canUpdate || _isFinalStatus(state.status)) return;

      final payload = data['payload'];
      if (payload == null || payload['offer'] == null) return;

      _safeState(
        state.copyWith(
          hasPendingVideoUpgrade: true,
          pendingVideoOffer: Map<String, dynamic>.from(payload['offer']),
          isVideoUpgradeRequesting: false,
          isVideoUpgradeRejected: false,
        ),
      );
    });

    // Video request accepted by receiver.
    SocketService.instance.on(CallSocketEvents.callRenegotiateAnswer, (data) async {
      if (!_canUpdate || _isFinalStatus(state.status)) return;

      final payload = data['payload'];
      if (payload == null || payload['answer'] == null) return;

      try {
        await webrtc.handleRenegotiationAnswer(payload['answer']);

        _safeState(
          state.copyWith(
            isVideoCall: true,
            isCameraOff: false,
            isRemoteCameraOff: false,
            isVideoUpgradeRequesting: false,
            isVideoUpgradeRejected: false,
            localRenderer: webrtc.localRenderer,
            remoteRenderer: webrtc.remoteRenderer,
          ),
        );
      } catch (e) {
        debugPrint('Renegotiation answer error: $e');

        await webrtc.disableVideoHard();

        _safeState(
          state.copyWith(
            isVideoCall: false,
            isCameraOff: true,
            isRemoteCameraOff: true,
            isVideoUpgradeRequesting: false,
            localRenderer: webrtc.localRenderer,
            remoteRenderer: webrtc.remoteRenderer,
          ),
        );
      } finally {
        _switchingVideo = false;
      }
    });

    // Same as Messenger:
    // cameraOff true  = remote video off, show avatar / video off UI
    // cameraOff false = remote video on, show video
    // isVideoCall false = remote switched whole call back to audio
    SocketService.instance.on(CallSocketEvents.callVideoToggle, (data) async {
      if (!_canUpdate || _isFinalStatus(state.status)) return;

      final payload = data['payload'];
      if (payload == null) return;

      final hasCameraOff = payload.containsKey('cameraOff');
      final hasVideoCall = payload.containsKey('isVideoCall');

      if (hasCameraOff) {
        final remoteCameraOff = payload['cameraOff'] == true;

        _safeState(
          state.copyWith(
            isVideoCall: true,
            isRemoteCameraOff: remoteCameraOff,
            localRenderer: webrtc.localRenderer,
            remoteRenderer: webrtc.remoteRenderer,
          ),
        );

        return;
      }

      if (hasVideoCall) {
        final remoteIsVideoCall = payload['isVideoCall'] == true;

        _safeState(
          state.copyWith(
            isVideoCall: remoteIsVideoCall,
            isRemoteCameraOff: !remoteIsVideoCall,
            isVideoUpgradeRequesting: false,
            hasPendingVideoUpgrade: false,
            clearPendingVideoOffer: true,
            localRenderer: webrtc.localRenderer,
            remoteRenderer: webrtc.remoteRenderer,
          ),
        );
      }
    });

    SocketService.instance.on(CallSocketEvents.callVideoUpgradeRejected, (_) async {
      if (!_canUpdate || _isFinalStatus(state.status)) return;

      await webrtc.disableVideoHard();

      _safeState(
        state.copyWith(
          isVideoCall: false,
          isCameraOff: true,
          isRemoteCameraOff: true,
          isVideoUpgradeRequesting: false,
          isVideoUpgradeRejected: true,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );

      _switchingVideo = false;
    });

    SocketService.instance.on(CallSocketEvents.callReject, (_) async {
      if (!_canUpdate) return;
      await _finishCall(CallStatus.rejected, emitSocket: false);
    });

    SocketService.instance.on(CallSocketEvents.callEnd, (_) async {
      if (!_canUpdate) return;
      await _finishCall(CallStatus.ended, emitSocket: false);
    });

    SocketService.instance.on(CallSocketEvents.callLeave, (_) async {
      if (!_canUpdate) return;
      await _finishCall(CallStatus.ended, emitSocket: false);
    });

    SocketService.instance.on(CallSocketEvents.callBusy, (_) async {
      if (!_canUpdate) return;
      await _finishCall(CallStatus.busy, emitSocket: false);
    });

    SocketService.instance.on(CallSocketEvents.callTimeout, (_) async {
      if (!_canUpdate) return;
      await _finishCall(CallStatus.timeout, emitSocket: false);
    });
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

      final offer = await webrtc.createRenegotiationOffer();

      SocketService.instance.emit(
        CallSocketEvents.callRenegotiateOffer,
        {
          'from': currentUserId,
          'offer': offer.toMap(),
          'requestType': 'video_upgrade',
        },
        targetUser: receiverId,
        conversationId: _conversationId,
      );

      _safeState(
        state.copyWith(
          isVideoUpgradeRequesting: true,
          isVideoUpgradeRejected: false,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );
    } catch (e) {
      debugPrint('Request video upgrade error: $e');

      _switchingVideo = false;

      await webrtc.disableVideoHard();

      _safeState(
        state.copyWith(
          isVideoCall: false,
          isCameraOff: true,
          isRemoteCameraOff: true,
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

      final answer = await webrtc.handleRenegotiationOffer(
        state.pendingVideoOffer!,
      );

      SocketService.instance.emit(
        CallSocketEvents.callRenegotiateAnswer,
        {
          'from': currentUserId,
          'answer': answer.toMap(),
        },
        targetUser: receiverId,
        conversationId: _conversationId,
      );

      _safeState(
        state.copyWith(
          isVideoCall: true,
          isCameraOff: false,
          isRemoteCameraOff: false,
          hasPendingVideoUpgrade: false,
          isVideoUpgradeRequesting: false,
          isVideoUpgradeRejected: false,
          clearPendingVideoOffer: true,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );
    } catch (e) {
      debugPrint('Accept video upgrade error: $e');
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
          'reason': 'declined',
        },
        targetUser: receiverId,
        conversationId: _conversationId,
      );
    }

    _safeState(
      state.copyWith(
        hasPendingVideoUpgrade: false,
        clearPendingVideoOffer: true,
      ),
    );
  }

  // Video call -> Audio call
  Future<void> switchToAudioCall() async {
    if (!_canUpdate) return;
    if (!state.isVideoCall && !state.isVideoUpgradeRequesting) return;
    if (_isFinalStatus(state.status)) return;

    final currentUserId = state.currentUserId;
    final receiverId = state.receiverId;

    if (currentUserId == null || receiverId == null) return;

    try {
      await webrtc.disableVideoHard();

      SocketService.instance.emit(
        CallSocketEvents.callVideoToggle,
        {
          'from': currentUserId,
          'isVideoCall': false,
        },
        targetUser: receiverId,
        conversationId: _conversationId,
      );

      _safeState(
        state.copyWith(
          isVideoCall: false,
          isCameraOff: true,
          isRemoteCameraOff: true,
          isVideoUpgradeRequesting: false,
          hasPendingVideoUpgrade: false,
          clearPendingVideoOffer: true,
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );

      _switchingVideo = false;
    } catch (e) {
      debugPrint('Switch to audio error: $e');
    }
  }

  Future<void> switchToVideoCall() => requestVideoUpgrade();

  // Camera on/off inside video call.
  // This is the part you need for Messenger-like "video off" on receiver.
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
          'cameraOff': newCameraOff,
          'isVideoCall': true,
        },
        targetUser: receiverId,
        conversationId: _conversationId,
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
            'reason': 'timeout',
          },
          targetUser: receiverId,
          conversationId: _conversationId,
        );
      }

      await _finishCall(CallStatus.timeout, emitSocket: false);
    });
  }

  void setConnected() {
    if (!_canUpdate) return;
    if (state.status == CallStatus.connected) return;
    if (_isFinalStatus(state.status)) return;

    _timeoutTimer?.cancel();

    webrtc.setSpeaker(state.isVideoCall);

    _safeState(
      state.copyWith(
        status: CallStatus.connected,
        isSpeakerOn: state.isVideoCall,
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
    } catch (e) {
      debugPrint('Switch camera error: $e');
    }
  }

  Future<void> rejectCall() async {
    if (!_canUpdate) return;

    final currentUserId = state.currentUserId;
    final receiverId = state.receiverId;

    if (currentUserId != null && receiverId != null) {
      SocketService.instance.emit(
        CallSocketEvents.callReject,
        {'from': currentUserId},
        targetUser: receiverId,
        conversationId: _conversationId,
      );
    }

    await _finishCall(CallStatus.rejected, emitSocket: false);
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
  }) async {
    if (!_canUpdate) return;
    if (_finishing) return;
    if (_isFinalStatus(state.status)) return;

    _finishing = true;

    final oldState = state;

    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    if (emitSocket) {
      final currentUserId = oldState.currentUserId;
      final receiverId = oldState.receiverId;

      if (currentUserId != null && receiverId != null) {
        SocketService.instance.emit(
          CallSocketEvents.callEnd,
          {'from': currentUserId},
          targetUser: receiverId,
          conversationId: _conversationId,
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

    await webrtc.dispose();
    await webrtc.disposeRenderers();

    _removeSocketEvents();

    _conversationId = null;
    _switchingVideo = false;
    _finishing = false;
  }

  Future<void> resetCall() async {
    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    _finishing = false;
    _switchingVideo = false;
    _conversationId = null;

    _removeSocketEvents();

    _safeState(const CallState());

    await Future.delayed(const Duration(milliseconds: 200));

    await webrtc.dispose();
    await webrtc.disposeRenderers();
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
    _disposed = true;

    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    _removeSocketEvents();

    if (mounted) {
      state = const CallState();
    }

    await Future.delayed(const Duration(milliseconds: 200));

    try {
      await webrtc.dispose();
      await webrtc.disposeRenderers();
    } catch (_) {}
  }

  void _removeSocketEventsOnly() {
    SocketService.instance.off(CallSocketEvents.callAnswer);
    SocketService.instance.off(CallSocketEvents.callReject);
    SocketService.instance.off(CallSocketEvents.callEnd);
    SocketService.instance.off(CallSocketEvents.callLeave);
    SocketService.instance.off(CallSocketEvents.iceCandidate);
    SocketService.instance.off(CallSocketEvents.callBusy);
    SocketService.instance.off(CallSocketEvents.callTimeout);
    SocketService.instance.off(CallSocketEvents.callRenegotiateOffer);
    SocketService.instance.off(CallSocketEvents.callRenegotiateAnswer);
    SocketService.instance.off(CallSocketEvents.callVideoToggle);
    SocketService.instance.off(CallSocketEvents.callVideoUpgradeRejected);
  }

  void _removeSocketEvents() {
    _removeSocketEventsOnly();
  }

  @override
  void dispose() {
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