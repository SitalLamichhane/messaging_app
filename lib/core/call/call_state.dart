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
  final bool isRemoteCameraOff;
  final bool isVideoCall;
  final bool isCaller;

  final bool hasPendingVideoUpgrade;
  final bool isVideoUpgradeRequesting;
  final bool isVideoUpgradeRejected;

  final String? currentUserId;
  final String? receiverId;
  final String? name;
  final String? avatarUrl;

  final Map<String, dynamic>? incomingOffer;
  final Map<String, dynamic>? pendingVideoOffer;

  final Duration duration;

  final RTCVideoRenderer? localRenderer;
  final RTCVideoRenderer? remoteRenderer;

  const CallState({
    this.status = CallStatus.idle,
    this.isMicOff = false,
    this.isSpeakerOn = false,
    this.isCameraOff = false,
    this.isRemoteCameraOff = false,
    this.isVideoCall = false,
    this.isCaller = false,
    this.hasPendingVideoUpgrade = false,
    this.isVideoUpgradeRequesting = false,
    this.isVideoUpgradeRejected = false,
    this.currentUserId,
    this.receiverId,
    this.name,
    this.avatarUrl,
    this.incomingOffer,
    this.pendingVideoOffer,
    this.duration = Duration.zero,
    this.localRenderer,
    this.remoteRenderer,
  });

  CallState copyWith({
    CallStatus? status,
    bool? isMicOff,
    bool? isSpeakerOn,
    bool? isCameraOff,
    bool? isRemoteCameraOff,
    bool? isVideoCall,
    bool? isCaller,
    bool? hasPendingVideoUpgrade,
    bool? isVideoUpgradeRequesting,
    bool? isVideoUpgradeRejected,
    String? currentUserId,
    String? receiverId,
    String? name,
    String? avatarUrl,
    Map<String, dynamic>? incomingOffer,
    Map<String, dynamic>? pendingVideoOffer,
    bool clearPendingVideoOffer = false,
    Duration? duration,
    RTCVideoRenderer? localRenderer,
    RTCVideoRenderer? remoteRenderer,
    bool clearRenderers = false,
  }) {
    return CallState(
      status: status ?? this.status,
      isMicOff: isMicOff ?? this.isMicOff,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      isRemoteCameraOff:
          isRemoteCameraOff ?? this.isRemoteCameraOff,
      isVideoCall: isVideoCall ?? this.isVideoCall,
      isCaller: isCaller ?? this.isCaller,
      hasPendingVideoUpgrade:
          hasPendingVideoUpgrade ?? this.hasPendingVideoUpgrade,
      isVideoUpgradeRequesting:
          isVideoUpgradeRequesting ?? this.isVideoUpgradeRequesting,
      isVideoUpgradeRejected:
          isVideoUpgradeRejected ?? this.isVideoUpgradeRejected,
      currentUserId: currentUserId ?? this.currentUserId,
      receiverId: receiverId ?? this.receiverId,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      incomingOffer: incomingOffer ?? this.incomingOffer,
      pendingVideoOffer: clearPendingVideoOffer
          ? null
          : pendingVideoOffer ?? this.pendingVideoOffer,
      duration: duration ?? this.duration,
      localRenderer: clearRenderers
          ? null
          : localRenderer ?? this.localRenderer,
      remoteRenderer: clearRenderers
          ? null
          : remoteRenderer ?? this.remoteRenderer,
    );
  }
}// This file defines the CallState class, which represents the state of a call in a Flutter application using WebRTC. It includes various properties to track the call status, media settings, user information, and offers. The copyWith method allows for creating a new instance of CallState with updated values while keeping the existing ones unchanged.  