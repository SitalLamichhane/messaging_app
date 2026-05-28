import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:messaging_app/core/call/call_socket_service.dart';
import 'package:messaging_app/core/call/call_state.dart';
import 'package:messaging_app/core/call/webrct_servide.dart';


final callProvider = StateNotifierProvider<CallNotifier, CallState>((ref) {
  return CallNotifier();
});

class CallNotifier extends StateNotifier<CallState> {
  CallNotifier() : super(const CallState());

  final WebRTCService webrtc = WebRTCService();

  Timer? _durationTimer;
  Timer? _timeoutTimer;
  bool _disposed = false;

  Future<void> startCall({
    required String currentUserId,
    required String receiverId,
    required String name,
    required String avatarUrl,
    required bool isVideoCall,
    required bool isCaller,
    Map? incomingOffer,
  }) async {
    try {
      _disposed = false;

      state = CallState(
        status: isCaller ? CallStatus.calling : CallStatus.ringing,
        currentUserId: currentUserId,
        receiverId: receiverId,
        name: name,
        avatarUrl: avatarUrl,
        isVideoCall: isVideoCall,
        isCaller: isCaller,
        incomingOffer: incomingOffer,
        isCameraOff: !isVideoCall,
      );

      await webrtc.initRenderers();

      await webrtc.createConnection(
        isVideoCall: isVideoCall,
        onIceCandidate: (candidate) {
          SocketService.instance.emit('ice_candidate', {
            'to': receiverId,
            'from': currentUserId,
            'candidate': candidate.toMap(),
          });
        },
        onRemoteStream: () {
          setConnected();
        },
      );

      state = state.copyWith(
        localRenderer: webrtc.localRenderer,
        remoteRenderer: webrtc.remoteRenderer,
      );

      _listenSocketEvents();

      if (isCaller) {
        _startCallTimeout();

        final offer = await webrtc.createOffer();

        SocketService.instance.emit('call_user', {
          'to': receiverId,
          'from': currentUserId,
          'callerName': name,
          'callerAvatar': avatarUrl,
          'isVideoCall': isVideoCall,
          'offer': offer.toMap(),
        });
      } else {
        if (incomingOffer == null) {
          state = state.copyWith(status: CallStatus.failed);
          return;
        }

        await webrtc.setRemoteDescription(incomingOffer);

        final answer = await webrtc.createAnswer();

        SocketService.instance.emit('call_accepted', {
          'to': receiverId,
          'from': currentUserId,
          'answer': answer.toMap(),
        });
      }
    } catch (e) {
      state = state.copyWith(status: CallStatus.failed);
    }
  }

  void _listenSocketEvents() {
    SocketService.instance.off('call_accepted');
    SocketService.instance.off('call_rejected');
    SocketService.instance.off('call_busy');
    SocketService.instance.off('call_timeout');
    SocketService.instance.off('call_ended');
    SocketService.instance.off('ice_candidate');

    SocketService.instance.on('call_accepted', (data) async {
      _timeoutTimer?.cancel();

      if (state.status == CallStatus.ended) return;
      if (data == null || data['answer'] == null) return;

      await webrtc.setRemoteDescription(data['answer']);
    });

    SocketService.instance.on('ice_candidate', (data) async {
      if (state.status == CallStatus.ended) return;
      if (data == null || data['candidate'] == null) return;

      await webrtc.addCandidate(data['candidate']);
    });

    SocketService.instance.on('call_rejected', (_) async {
      await _finishCall(CallStatus.rejected, emitSocket: false);
    });

    SocketService.instance.on('call_busy', (_) async {
      await _finishCall(CallStatus.busy, emitSocket: false);
    });

    SocketService.instance.on('call_timeout', (_) async {
      await _finishCall(CallStatus.timeout, emitSocket: false);
    });

    SocketService.instance.on('call_ended', (_) async {
      await _finishCall(CallStatus.ended, emitSocket: false);
    });
  }

  void _startCallTimeout() {
    _timeoutTimer?.cancel();

    _timeoutTimer = Timer(const Duration(seconds: 30), () async {
      if (state.status == CallStatus.connected ||
          state.status == CallStatus.ended) {
        return;
      }

      SocketService.instance.emit('call_timeout', {
        'to': state.receiverId,
        'from': state.currentUserId,
      });

      await _finishCall(CallStatus.timeout, emitSocket: false);
    });
  }

  void setConnected() {
    if (state.status == CallStatus.connected) return;

    _timeoutTimer?.cancel();

    state = state.copyWith(status: CallStatus.connected);
    _startDurationTimer();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.status != CallStatus.connected) return;

      state = state.copyWith(
        duration: state.duration + const Duration(seconds: 1),
      );
    });
  }

  void toggleMic() {
    final value = !state.isMicOff;

    state = state.copyWith(isMicOff: value);

    webrtc.toggleMic(!value);
  }

  void toggleSpeaker() {
    final value = !state.isSpeakerOn;

    state = state.copyWith(isSpeakerOn: value);

    webrtc.setSpeaker(value);
  }

  void toggleCamera() {
    if (!state.isVideoCall) return;

    final value = !state.isCameraOff;

    state = state.copyWith(isCameraOff: value);

    webrtc.toggleCamera(!value);
  }

  Future<void> switchCamera() async {
    if (!state.isVideoCall || state.isCameraOff) return;

    await webrtc.switchCamera();
  }

  Future<void> endCall({bool emitSocket = true}) async {
    await _finishCall(CallStatus.ended, emitSocket: emitSocket);
  }

  Future<void> _finishCall(
    CallStatus finalStatus, {
    required bool emitSocket,
  }) async {
    if (state.status == CallStatus.ended ||
        state.status == CallStatus.rejected ||
        state.status == CallStatus.timeout ||
        state.status == CallStatus.busy) {
      return;
    }

    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    if (emitSocket) {
      SocketService.instance.emit('call_ended', {
        'to': state.receiverId,
        'from': state.currentUserId,
      });
    }

    await disposeCall();

    state = state.copyWith(status: finalStatus);
  }

  Future<void> disposeCall() async {
    if (_disposed) return;

    _disposed = true;

    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    SocketService.instance.off('call_accepted');
    SocketService.instance.off('call_rejected');
    SocketService.instance.off('call_busy');
    SocketService.instance.off('call_timeout');
    SocketService.instance.off('call_ended');
    SocketService.instance.off('ice_candidate');

    await webrtc.dispose();
  }
}