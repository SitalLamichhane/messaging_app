import 'dart:async';

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
  bool _socketListening = false;
  bool _finishing = false;

  bool get _canUpdate => mounted && !_disposed;

  void _safeState(CallState newState) {
    if (!_canUpdate) return;

    try {
      state = newState;
    } catch (_) {}
  }

  Future<void> startCall({
    required String currentUserId,
    required String receiverId,
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

      _durationTimer?.cancel();
      _timeoutTimer?.cancel();

      await _disposeWebRTCOnly();
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
          duration: Duration.zero,
        ),
      );

      _listenSocketEvents();

      await webrtc.initRenderers();
      if (!_canUpdate) return;

      await webrtc.createConnection(
        isVideoCall: isVideoCall,
        onIceCandidate: (candidate) {
          if (!_canUpdate) return;
          if (_isFinalStatus(state.status)) return;

          SocketService.instance.emit(
            'ice_candidate',
            {
              'from': currentUserId,
              'candidate': candidate.toMap(),
            },
            targetUser: receiverId,
          );
        },
        onRemoteStream: () {
          if (!_canUpdate) return;
          if (_isFinalStatus(state.status)) return;

          _safeState(
            state.copyWith(
              localRenderer: webrtc.localRenderer,
              remoteRenderer: webrtc.remoteRenderer,
            ),
          );

          setConnected();
        },
      );

      if (!_canUpdate) return;

      _safeState(
        state.copyWith(
          localRenderer: webrtc.localRenderer,
          remoteRenderer: webrtc.remoteRenderer,
        ),
      );

      if (isCaller) {
        _startCallTimeout();

        final offer = await webrtc.createOffer();
        if (!_canUpdate) return;
        if (_isFinalStatus(state.status)) return;

        SocketService.instance.emit(
          'call_offer',
          {
            'from': currentUserId,
            'callerName': name,
            'callerAvatar': avatarUrl,
            'isVideoCall': isVideoCall,
            'offer': offer.toMap(),
          },
          targetUser: receiverId,
        );
      } else {
        if (incomingOffer == null) {
          await _finishCall(CallStatus.failed, emitSocket: false);
          return;
        }

        await webrtc.setRemoteDescription(incomingOffer);
        if (!_canUpdate) return;
        if (_isFinalStatus(state.status)) return;

        final answer = await webrtc.createAnswer();
        if (!_canUpdate) return;
        if (_isFinalStatus(state.status)) return;

        SocketService.instance.emit(
          'call_answer',
          {
            'from': currentUserId,
            'answer': answer.toMap(),
          },
          targetUser: receiverId,
        );
      }
    } catch (e) {
      if (_canUpdate) {
        await _finishCall(CallStatus.failed, emitSocket: false);
      }
    }
  }

  void _listenSocketEvents() {
    if (_socketListening) return;

    _socketListening = true;
    _removeSocketEventsOnly();

    SocketService.instance.on('call_answer', (data) async {
      if (!_canUpdate) return;
      if (_isFinalStatus(state.status)) return;

      _timeoutTimer?.cancel();

      final payload = data['payload'];
      if (payload == null || payload['answer'] == null) return;

      try {
        await webrtc.setRemoteDescription(payload['answer']);

        if (!_canUpdate) return;
        if (_isFinalStatus(state.status)) return;

        _safeState(
          state.copyWith(
            localRenderer: webrtc.localRenderer,
            remoteRenderer: webrtc.remoteRenderer,
          ),
        );

        setConnected();
      } catch (_) {
        await _finishCall(CallStatus.failed, emitSocket: false);
      }
    });

    SocketService.instance.on('ice_candidate', (data) async {
      if (!_canUpdate) return;
      if (_isFinalStatus(state.status)) return;

      final payload = data['payload'];
      if (payload == null || payload['candidate'] == null) return;

      try {
        await webrtc.addCandidate(payload['candidate']);
      } catch (_) {}
    });

    SocketService.instance.on('call_reject', (_) async {
      if (!_canUpdate) return;
      await _finishCall(CallStatus.rejected, emitSocket: false);
    });

    SocketService.instance.on('call_end', (_) async {
      if (!_canUpdate) return;
      await _finishCall(CallStatus.ended, emitSocket: false);
    });

    SocketService.instance.on('call_leave', (_) async {
      if (!_canUpdate) return;
      await _finishCall(CallStatus.ended, emitSocket: false);
    });

    SocketService.instance.on('call_busy', (_) async {
      if (!_canUpdate) return;
      await _finishCall(CallStatus.busy, emitSocket: false);
    });

    SocketService.instance.on('call_timeout', (_) async {
      if (!_canUpdate) return;
      await _finishCall(CallStatus.timeout, emitSocket: false);
    });
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
          'call_timeout',
          {
            'from': currentUserId,
            'reason': 'timeout',
          },
          targetUser: receiverId,
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

  webrtc.setSpeaker(true);

  _safeState(
    state.copyWith(
      status: CallStatus.connected,
      isSpeakerOn: true,
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

  void toggleCamera() {
    if (!_canUpdate) return;
    if (!state.isVideoCall) return;

    final newValue = !state.isCameraOff;
    _safeState(state.copyWith(isCameraOff: newValue));

    webrtc.toggleCamera(!newValue);
  }

  Future<void> switchCamera() async {
    if (!_canUpdate) return;
    if (!state.isVideoCall) return;
    if (state.isCameraOff) return;

    try {
      await webrtc.switchCamera();
    } catch (_) {}
  }

  Future<void> rejectCall() async {
    if (!_canUpdate) return;

    final currentUserId = state.currentUserId;
    final receiverId = state.receiverId;

    if (currentUserId != null && receiverId != null) {
      SocketService.instance.emit(
        'call_reject',
        {
          'from': currentUserId,
        },
        targetUser: receiverId,
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
          'call_end',
          {
            'from': currentUserId,
          },
          targetUser: receiverId,
        );
      }
    }

    await _disposeWebRTCOnly();
    await webrtc.disposeRenderers();

    if (_canUpdate) {
      _safeState(
        oldState.copyWith(
          status: finalStatus,
          localRenderer: null,
          remoteRenderer: null,
          duration: oldState.duration,
        ),
      );
    }

    _finishing = false;
  }

  Future<void> resetCall() async {
    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    _finishing = false;

    await _disposeWebRTCOnly();
    await webrtc.disposeRenderers();

    if (_canUpdate) {
      _safeState(const CallState());
    }
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

    try {
      await webrtc.dispose();
      await webrtc.disposeRenderers();
    } catch (e) {
      print('WebRTC dispose error: $e');
    }

    if (mounted) {
      state = const CallState();
    }
  }

  Future<void> _disposeWebRTCOnly() async {
    try {
      await webrtc.dispose();
    } catch (_) {}
  }

  void _removeSocketEventsOnly() {
    SocketService.instance.off('call_answer');
    SocketService.instance.off('call_reject');
    SocketService.instance.off('call_end');
    SocketService.instance.off('call_leave');
    SocketService.instance.off('ice_candidate');
    SocketService.instance.off('call_busy');
    SocketService.instance.off('call_timeout');
  }

  void _removeSocketEvents() {
    _socketListening = false;
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