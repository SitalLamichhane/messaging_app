import 'package:flutter_webrtc/flutter_webrtc.dart';

enum CallStatus {
  idle,
  calling,
  ringing,
  connected,
  ended,
  failed,
  rejected,
  busy,
  missed,
  timeout,
}

class CallState {
  final CallStatus status;
  final bool isMicOff;
  final bool isSpeakerOn;
  final bool isCameraOff;
  final bool isVideoCall;
  final bool isCaller;

  final String? currentUserId;
  final String? receiverId;
  final String? name;
  final String? avatarUrl;
  final Map? incomingOffer;

  final Duration duration;

  final RTCVideoRenderer? localRenderer;
  final RTCVideoRenderer? remoteRenderer;

  const CallState({
    this.status = CallStatus.idle,
    this.isMicOff = false,
    this.isSpeakerOn = false,
    this.isCameraOff = false,
    this.isVideoCall = false,
    this.isCaller = true,
    this.currentUserId,
    this.receiverId,
    this.name,
    this.avatarUrl,
    this.incomingOffer,
    this.duration = Duration.zero,
    this.localRenderer,
    this.remoteRenderer,
  });

  CallState copyWith({
    CallStatus? status,
    bool? isMicOff,
    bool? isSpeakerOn,
    bool? isCameraOff,
    bool? isVideoCall,
    bool? isCaller,
    String? currentUserId,
    String? receiverId,
    String? name,
    String? avatarUrl,
    Map? incomingOffer,
    Duration? duration,
    RTCVideoRenderer? localRenderer,
    RTCVideoRenderer? remoteRenderer,
  }) {
    return CallState(
      status: status ?? this.status,
      isMicOff: isMicOff ?? this.isMicOff,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      isVideoCall: isVideoCall ?? this.isVideoCall,
      isCaller: isCaller ?? this.isCaller,
      currentUserId: currentUserId ?? this.currentUserId,
      receiverId: receiverId ?? this.receiverId,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      incomingOffer: incomingOffer ?? this.incomingOffer,
      duration: duration ?? this.duration,
      localRenderer: localRenderer ?? this.localRenderer,
      remoteRenderer: remoteRenderer ?? this.remoteRenderer,
    );
  }
}