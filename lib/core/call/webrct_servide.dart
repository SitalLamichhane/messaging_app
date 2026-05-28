import 'dart:ui';

import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  Future<void> initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<void> createConnection({
    required bool isVideoCall,
    required Function(RTCIceCandidate candidate) onIceCandidate,
    required VoidCallback onRemoteStream,
  }) async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    };

    _peerConnection = await createPeerConnection(config);

    final mediaConstraints = {
      'audio': true,
      'video': isVideoCall
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };

    _localStream =
        await navigator.mediaDevices.getUserMedia(mediaConstraints);

    localRenderer.srcObject = _localStream;

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (candidate) {
      onIceCandidate(candidate);
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        onRemoteStream();
      }
    };
  }

  Future<RTCSessionDescription> createOffer() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(Map data) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(
        data['sdp'],
        data['type'],
      ),
    );
  }

  Future<void> addCandidate(Map data) async {
    await _peerConnection!.addCandidate(
      RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      ),
    );
  }

  void toggleMic(bool enabled) {
    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = enabled;
    }
  }

  void toggleCamera(bool enabled) {
    for (final track in _localStream?.getVideoTracks() ?? []) {
      track.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    final videoTracks = _localStream?.getVideoTracks() ?? [];
    if (videoTracks.isEmpty) return;

    await Helper.switchCamera(videoTracks.first);
  }

  Future<void> setSpeaker(bool enabled) async {
    await Helper.setSpeakerphoneOn(enabled);
  }

  Future<void> dispose() async {
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    for (final track in _localStream?.getTracks() ?? []) {
      await track.stop();
    }

    await _localStream?.dispose();
    await _peerConnection?.close();
    await _peerConnection?.dispose();

    await localRenderer.dispose();
    await remoteRenderer.dispose();

    _localStream = null;
    _peerConnection = null;
  }
}