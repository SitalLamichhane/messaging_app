import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  bool _disposed = true;
  bool _renderersInitialized = false;
  bool _remoteDescriptionSet = false;

  final List<RTCIceCandidate> _pendingCandidates = [];

  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  Future<void> initRenderers() async {
    _disposed = false;

    if (_renderersInitialized) return;

    localRenderer = RTCVideoRenderer();
    remoteRenderer = RTCVideoRenderer();

    await localRenderer.initialize();
    await remoteRenderer.initialize();

    _renderersInitialized = true;
  }

  Future<void> createConnection({
    required bool isVideoCall,
    required Function(RTCIceCandidate candidate) onIceCandidate,
    required VoidCallback onRemoteStream,
  }) async {
    _disposed = false;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();

    try {
      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {
            'urls': 'turn:openrelay.metered.ca:80',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
          {
            'urls': 'turn:openrelay.metered.ca:443',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
          {
            'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
        'sdpSemantics': 'unified-plan',
      };

      _peerConnection = await createPeerConnection(config);

      final mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': isVideoCall
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 360},
                'frameRate': {'ideal': 30},
              }
            : false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      await Helper.setSpeakerphoneOn(isVideoCall);

      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = true;
      }

      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = isVideoCall;
      }

      if (!_disposed && _renderersInitialized) {
        localRenderer.srcObject = _localStream;
      }

      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      _peerConnection!.onIceCandidate = (candidate) {
        if (_disposed) return;
        onIceCandidate(candidate);
      };

      _peerConnection!.onTrack = (event) {
        if (_disposed) return;

        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams.first;

          if (!_disposed && _renderersInitialized) {
            remoteRenderer.srcObject = _remoteStream;
          }

          onRemoteStream();
        }
      };

      _peerConnection!.onConnectionState = (state) {
        debugPrint('WEBRTC CONNECTION STATE: $state');
      };

      _peerConnection!.onIceConnectionState = (state) {
        debugPrint('WEBRTC ICE STATE: $state');
      };
    } catch (e) {
      debugPrint('WebRTC createConnection error: $e');
      await dispose();
      rethrow;
    }
  }

  Future<RTCSessionDescription> createOffer() async {
    if (_peerConnection == null) {
      throw Exception('Peer connection is null');
    }

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });

    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    if (_peerConnection == null) {
      throw Exception('Peer connection is null');
    }

    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });

    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(Map data) async {
    if (_peerConnection == null) return;
    if (_disposed) return;

    final sdp = data['sdp'];
    final type = data['type'];

    if (sdp == null || type == null) return;

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, type),
    );

    _remoteDescriptionSet = true;
    await _flushPendingCandidates();
  }

  Future<void> addCandidate(Map data) async {
    if (_peerConnection == null) return;
    if (_disposed) return;

    final candidateValue = data['candidate'];
    final sdpMid = data['sdpMid'];
    final sdpMLineIndex = data['sdpMLineIndex'];

    if (candidateValue == null) return;

    final candidate = RTCIceCandidate(
      candidateValue,
      sdpMid,
      sdpMLineIndex,
    );

    if (!_remoteDescriptionSet) {
      _pendingCandidates.add(candidate);
      return;
    }

    try {
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      debugPrint('ICE add error: $e');
    }
  }

  Future<void> enableVideo() async {
    if (_peerConnection == null) {
      throw Exception('Peer connection is null');
    }

    if (_localStream == null) {
      throw Exception('Local stream is null');
    }

    final existingVideoTracks = _localStream!.getVideoTracks();

    if (existingVideoTracks.isNotEmpty) {
      for (final track in existingVideoTracks) {
        track.enabled = true;
      }

      if (_renderersInitialized && !_disposed) {
        localRenderer.srcObject = _localStream;
      }

      await Helper.setSpeakerphoneOn(true);
      return;
    }

    final videoStream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 360},
        'frameRate': {'ideal': 30},
      },
    });

    final videoTrack = videoStream.getVideoTracks().first;

    await _localStream!.addTrack(videoTrack);

    final senders = await _peerConnection!.getSenders();

    RTCRtpSender? videoSender;
    for (final sender in senders) {
      if (sender.track?.kind == 'video') {
        videoSender = sender;
        break;
      }
    }

    if (videoSender != null) {
      await videoSender.replaceTrack(videoTrack);
    } else {
      await _peerConnection!.addTrack(videoTrack, _localStream!);
    }

    if (_renderersInitialized && !_disposed) {
      localRenderer.srcObject = _localStream;
    }

    await Helper.setSpeakerphoneOn(true);
  }

  Future<void> disableVideo() async {
    if (_localStream == null) return;

    for (final track in _localStream!.getVideoTracks()) {
      track.enabled = false;
    }

    if (_renderersInitialized && !_disposed) {
      localRenderer.srcObject = _localStream;
    }
  }

  Future<RTCSessionDescription> createRenegotiationOffer() async {
    if (_peerConnection == null) {
      throw Exception('Peer connection is null');
    }

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });

    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> handleRenegotiationOffer(Map data) async {
    if (_peerConnection == null) {
      throw Exception('Peer connection is null');
    }

    if (_disposed) {
      throw Exception('WebRTC already disposed');
    }

    final sdp = data['sdp'];
    final type = data['type'];

    if (sdp == null || type == null) {
      throw Exception('Invalid renegotiation offer');
    }

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, type),
    );

    _remoteDescriptionSet = true;
    await _flushPendingCandidates();

    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });

    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  Future<void> handleRenegotiationAnswer(Map data) async {
    if (_peerConnection == null) return;
    if (_disposed) return;

    final sdp = data['sdp'];
    final type = data['type'];

    if (sdp == null || type == null) return;

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, type),
    );

    _remoteDescriptionSet = true;
    await _flushPendingCandidates();
  }

  Future<void> _flushPendingCandidates() async {
    if (_peerConnection == null) return;

    for (final candidate in List<RTCIceCandidate>.from(_pendingCandidates)) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        debugPrint('Pending ICE add error: $e');
      }
    }

    _pendingCandidates.clear();
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
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;

    await Helper.switchCamera(tracks.first);
  }

  Future<void> setSpeaker(bool enabled) async {
    try {
      await Helper.setSpeakerphoneOn(enabled);
    } catch (e) {
      debugPrint('Set speaker error: $e');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();

    try {
      _peerConnection?.onIceCandidate = null;
      _peerConnection?.onTrack = null;
      _peerConnection?.onConnectionState = null;
      _peerConnection?.onIceConnectionState = null;

      try {
        localRenderer.srcObject = null;
      } catch (_) {}

      try {
        remoteRenderer.srcObject = null;
      } catch (_) {}

      for (final track in _localStream?.getTracks() ?? []) {
        try {
          await track.stop();
        } catch (_) {}
      }

      for (final track in _remoteStream?.getTracks() ?? []) {
        try {
          await track.stop();
        } catch (_) {}
      }

      try {
        await Helper.setSpeakerphoneOn(false);
      } catch (_) {}

      try {
        await _peerConnection?.close();
      } catch (_) {}

      try {
        await _peerConnection?.dispose();
      } catch (_) {}

      try {
        await _localStream?.dispose();
      } catch (_) {}

      try {
        await _remoteStream?.dispose();
      } catch (_) {}
    } catch (e) {
      debugPrint('WebRTC dispose error: $e');
    } finally {
      _localStream = null;
      _remoteStream = null;
      _peerConnection = null;
    }
  }

  Future<void> disposeRenderers() async {
    try {
      if (_renderersInitialized) {
        try {
          localRenderer.srcObject = null;
        } catch (_) {}

        try {
          remoteRenderer.srcObject = null;
        } catch (_) {}

        try {
          await localRenderer.dispose();
        } catch (_) {}

        try {
          await remoteRenderer.dispose();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Renderer dispose error: $e');
    } finally {
      _renderersInitialized = false;
    }
  }
}