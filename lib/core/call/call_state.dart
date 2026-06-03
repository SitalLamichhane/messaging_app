import 'package:flutter_webrtc/flutter_webrtc.dart';

enum CallStatus {
  idle,
  incoming,
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

  final Map<String, dynamic>? incomingOffer;

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

  static const Object _noChange = Object();

  CallState copyWith({
    CallStatus? status,
    bool? isMicOff,
    bool? isSpeakerOn,
    bool? isCameraOff,
    bool? isVideoCall,
    bool? isCaller,
    Object? currentUserId = _noChange,
    Object? receiverId = _noChange,
    Object? name = _noChange,
    Object? avatarUrl = _noChange,
    Object? incomingOffer = _noChange,
    Duration? duration,
    Object? localRenderer = _noChange,
    Object? remoteRenderer = _noChange,
  }) {
    return CallState(
      status: status ?? this.status,
      isMicOff: isMicOff ?? this.isMicOff,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      isVideoCall: isVideoCall ?? this.isVideoCall,
      isCaller: isCaller ?? this.isCaller,
      currentUserId: currentUserId == _noChange
          ? this.currentUserId
          : currentUserId as String?,
      receiverId: receiverId == _noChange
          ? this.receiverId
          : receiverId as String?,
      name: name == _noChange ? this.name : name as String?,
      avatarUrl: avatarUrl == _noChange ? this.avatarUrl : avatarUrl as String?,
      incomingOffer: incomingOffer == _noChange
          ? this.incomingOffer
          : incomingOffer as Map<String, dynamic>?,
      duration: duration ?? this.duration,
      localRenderer: localRenderer == _noChange
          ? this.localRenderer
          : localRenderer as RTCVideoRenderer?,
      remoteRenderer: remoteRenderer == _noChange
          ? this.remoteRenderer
          : remoteRenderer as RTCVideoRenderer?,
    );
  }

  bool get isInCall =>
      status == CallStatus.calling ||
      status == CallStatus.ringing ||
      status == CallStatus.connected ||
      status == CallStatus.incoming;
}