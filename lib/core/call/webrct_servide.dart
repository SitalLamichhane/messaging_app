import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCRtpSender? _videoSender;

  bool _disposed = true;
  bool _renderersInitialized = false;
  bool _remoteDescriptionSet = false;

  /*
    Preserve mic mute state.
    Speaker/video switching must never force mic enabled.
  */
  bool _micEnabled = true;

  final List<RTCIceCandidate> _pendingCandidates = [];

  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  /*
  ---------------------------------------------------------------------------
  PRODUCTION TURN ENABLED
  ---------------------------------------------------------------------------

  IMPORTANT:
  - This is enabled directly now.
  - Replace IP/username/password if your coturn server uses different values.
  - Your VPS firewall must allow:
      3478/tcp
      3478/udp
      49152-65535/udp
  */

  static const bool useProductionTurn = true;

  static const List<String> productionTurnUrls = <String>[
    'turn:2.25.186.109:3478?transport=udp',
    'turn:2.25.186.109:3478?transport=tcp',
  ];

  static const String productionTurnUsername = 'webrtcuser';

  static const String productionTurnPassword = 'StrongPassword123';

  /*
  ---------------------------------------------------------------------------
  TESTING OPENRELAY DISABLED
  ---------------------------------------------------------------------------

  Do NOT use free OpenRelay for production.
  */
  static const bool useFreeOpenRelayForTesting = false;

  /*
  ---------------------------------------------------------------------------
  AUDIO CALL STABILITY
  ---------------------------------------------------------------------------

  Some Android/flutter_webrtc setups behave badly with pure audio-only SDP.
  So for audio calls we create audio + disabled video track internally.

  UI still behaves like audio call because CallState.isVideoCall remains false.
  */
  static const bool useHiddenDisabledVideoTrackForAudioCall = true;

  Map<String, dynamic> _iceConfig() {
    final stunOnly = <Map<String, dynamic>>[
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ];

    if (useProductionTurn) {
      final hasTurnConfig = productionTurnUrls.isNotEmpty &&
          productionTurnUsername.trim().isNotEmpty &&
          productionTurnPassword.trim().isNotEmpty;

      if (!hasTurnConfig) {
        debugPrint(
          'WEBRTC TURN config enabled but missing. Falling back to STUN-only.',
        );

        return <String, dynamic>{
          'iceServers': stunOnly,
          'sdpSemantics': 'unified-plan',
        };
      }

      return <String, dynamic>{
        'iceServers': [
          ...stunOnly,
          {
            'urls': productionTurnUrls,
            'username': productionTurnUsername,
            'credential': productionTurnPassword,
          },
        ],
        'sdpSemantics': 'unified-plan',
      };
    }

    if (useFreeOpenRelayForTesting) {
      return <String, dynamic>{
        'iceServers': [
          ...stunOnly,
          {
            'urls': [
              'turn:openrelay.metered.ca:80',
              'turn:openrelay.metered.ca:443',
              'turn:openrelay.metered.ca:443?transport=tcp',
            ],
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
        'sdpSemantics': 'unified-plan',
      };
    }

    return <String, dynamic>{
      'iceServers': stunOnly,
      'sdpSemantics': 'unified-plan',
    };
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  Future<void> initRenderers() async {
    _disposed = false;

    if (_renderersInitialized) {
      return;
    }

    localRenderer = RTCVideoRenderer();
    remoteRenderer = RTCVideoRenderer();

    await localRenderer.initialize();
    await remoteRenderer.initialize();

    _renderersInitialized = true;

    debugPrint('WEBRTC RENDERERS INITIALIZED');
  }

  Future<void> createConnection({
    required bool isVideoCall,
    required Function(RTCIceCandidate candidate) onIceCandidate,
    required VoidCallback onRemoteStream,
    Future<void> Function()? onIceRestartNeeded,
  }) async {
    _disposed = false;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _videoSender = null;
    _remoteStream = null;

    /*
      New call starts unmuted.
      After user mutes, toggleMic(false) preserves mute state.
    */
    _micEnabled = true;

    try {
      final config = _iceConfig();

      debugPrint('WEBRTC ICE CONFIG: $config');

      _peerConnection = await createPeerConnection(config);

      final pc = _peerConnection;

      if (pc == null) {
        throw Exception('Peer connection creation failed');
      }

      pc.onIceCandidate = (candidate) {
        if (_disposed) return;

        if (candidate.candidate == null ||
            candidate.candidate.toString().trim().isEmpty) {
          debugPrint('WEBRTC EMPTY ICE CANDIDATE IGNORED');
          return;
        }

        debugPrint(
          'WEBRTC ICE CANDIDATE: ${candidate.candidate} '
          'sdpMid=${candidate.sdpMid} '
          'sdpMLineIndex=${candidate.sdpMLineIndex}',
        );

        onIceCandidate(candidate);
      };

      pc.onTrack = (event) async {
        if (_disposed) return;

        debugPrint('================ WEBRTC ON TRACK ================');
        debugPrint(
          'WEBRTC REMOTE TRACK RECEIVED: '
          'kind=${event.track.kind}, id=${event.track.id}, enabled=${event.track.enabled}',
        );
        debugPrint('WEBRTC REMOTE EVENT STREAMS: ${event.streams.length}');

        /*
          Prefer stream from event.streams when available.
          If not available, create one and manually add the track.
        */
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams.first;
          debugPrint('WEBRTC USING REMOTE STREAM FROM EVENT');
        } else {
          _remoteStream ??= await createLocalMediaStream('remote_stream');

          final alreadyAdded = _remoteStream!
              .getTracks()
              .any((track) => track.id == event.track.id);

          if (!alreadyAdded) {
            await _remoteStream!.addTrack(event.track);
            debugPrint('WEBRTC REMOTE TRACK ADDED: ${event.track.kind}');
          } else {
            debugPrint(
              'WEBRTC REMOTE TRACK ALREADY ADDED: ${event.track.kind}',
            );
          }
        }

        debugPrint(
          'WEBRTC REMOTE AUDIO TRACKS: ${_remoteStream?.getAudioTracks().length ?? 0}',
        );
        debugPrint(
          'WEBRTC REMOTE VIDEO TRACKS: ${_remoteStream?.getVideoTracks().length ?? 0}',
        );

        if (!_disposed && _renderersInitialized) {
          remoteRenderer.srcObject = _remoteStream;
          debugPrint('WEBRTC REMOTE RENDERER ATTACHED');
        }

        await _forceAudioOn();
        onRemoteStream();

        debugPrint('==================================================');
      };

      pc.onAddStream = (stream) async {
        if (_disposed) return;

        debugPrint('================ WEBRTC ON ADD STREAM ================');
        debugPrint(
          'WEBRTC onAddStream: '
          'audio=${stream.getAudioTracks().length}, '
          'video=${stream.getVideoTracks().length}',
        );

        _remoteStream = stream;

        if (!_disposed && _renderersInitialized) {
          remoteRenderer.srcObject = _remoteStream;
          debugPrint('WEBRTC REMOTE RENDERER ATTACHED FROM onAddStream');
        }

        await _forceAudioOn();
        onRemoteStream();

        debugPrint('=======================================================');
      };

     pc.onConnectionState = (state) async {
  debugPrint('WEBRTC CONNECTION STATE: $state');

  if (state ==
      RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {

    debugPrint('WEBRTC DISCONNECTED');

    Future.delayed(const Duration(seconds: 5), () async {
      try {
        await onIceRestartNeeded?.call();
      } catch (e) {
        debugPrint('ICE RESTART CALLBACK ERROR: $e');
      }
    });
  }

  if (state ==
      RTCPeerConnectionState.RTCPeerConnectionStateFailed) {

    debugPrint('WEBRTC FAILED -> REQUEST ICE RESTART SIGNALING');

    try {
      await onIceRestartNeeded?.call();
    } catch (e) {
      debugPrint('ICE RESTART CALLBACK ERROR: $e');
    }
  }
};

      pc.onIceConnectionState = (state) async {
        debugPrint('WEBRTC ICE STATE: $state');

        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          debugPrint('ICE FAILED -> REQUEST ICE RESTART SIGNALING');

          try {
            await onIceRestartNeeded?.call();
          } catch (e) {
            debugPrint('ICE RESTART CALLBACK ERROR: $e');
          }
        }
      };

      pc.onSignalingState = (state) {
        debugPrint('WEBRTC SIGNALING STATE: $state');
      };

      final shouldRequestVideo =
          isVideoCall || useHiddenDisabledVideoTrackForAudioCall;

      final mediaConstraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': shouldRequestVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': isVideoCall ? 640 : 320},
                'height': {'ideal': isVideoCall ? 360 : 240},
                'frameRate': {'ideal': isVideoCall ? 30 : 15},
              }
            : false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );

      final localStream = _localStream;

      if (localStream == null) {
        throw Exception('Local media stream is null');
      }

      debugPrint('================ WEBRTC LOCAL MEDIA ================');
      debugPrint(
        'WEBRTC LOCAL AUDIO TRACKS: ${localStream.getAudioTracks().length}',
      );
      debugPrint(
        'WEBRTC LOCAL VIDEO TRACKS: ${localStream.getVideoTracks().length}',
      );

      for (final track in localStream.getAudioTracks()) {
        track.enabled = _micEnabled;
        debugPrint(
          'WEBRTC LOCAL AUDIO ENABLED: id=${track.id}, enabled=${track.enabled}',
        );
      }

      for (final track in localStream.getVideoTracks()) {
        /*
          Direct video call: camera enabled.
          Audio call hidden video track: disabled immediately.
        */
        track.enabled = isVideoCall;

        debugPrint(
          'WEBRTC LOCAL VIDEO ENABLED: id=${track.id}, enabled=${track.enabled}, isVideoCall=$isVideoCall',
        );
      }

      debugPrint('====================================================');

      if (!_disposed && _renderersInitialized) {
        localRenderer.srcObject = localStream;
      }

      for (final track in localStream.getTracks()) {
        final sender = await pc.addTrack(track, localStream);

        debugPrint(
          'WEBRTC LOCAL TRACK ADDED TO PEER: kind=${track.kind}, id=${track.id}, enabled=${track.enabled}',
        );

        if (track.kind == 'video') {
          _videoSender = sender;
        }
      }

      await _forceAudioOn();
    } catch (e) {
      debugPrint('WebRTC createConnection error: $e');
      await dispose();
      rethrow;
    }
  }

  Future<RTCSessionDescription> createOffer() async {
  final pc = _peerConnection;

  if (pc == null || _disposed) {
    throw Exception('Peer connection is null/disposed');
  }

  final offer = await pc.createOffer({
    'offerToReceiveAudio': true,
    'offerToReceiveVideo': true,
  });

  await pc.setLocalDescription(offer);

  debugPrint('WEBRTC LOCAL OFFER CREATED');
  return offer;
}

  Future<RTCSessionDescription> createAnswer() async {
   final pc = _peerConnection;

  if (pc == null || _disposed) {
    throw Exception('Peer connection is null/disposed');
  }

  final answer = await pc.createAnswer({
    'offerToReceiveAudio': true,
    'offerToReceiveVideo': true,
  });

  await pc.setLocalDescription(answer);

  debugPrint('WEBRTC LOCAL ANSWER CREATED');
  return answer;
}

Future<RTCSessionDescription> restartIce() async {
  final pc = _peerConnection;

  if (pc == null || _disposed) {
    throw Exception('Peer connection is null/disposed');
  }

  final offer = await pc.createOffer({
    'iceRestart': true,
    'offerToReceiveAudio': true,
    'offerToReceiveVideo': true,
  });

  await pc.setLocalDescription(offer);

  debugPrint('WEBRTC ICE RESTART OFFER CREATED');

  return offer;
}

  Future<void> setRemoteDescription(Map data) async {
    final pc = _peerConnection;

    if (pc == null || _disposed) return;

    final sdp = data['sdp'];
    final type = data['type'];

    if (sdp == null || type == null) {
      debugPrint('WEBRTC SET REMOTE DESCRIPTION FAILED: missing sdp/type');
      return;
    }

    debugPrint('WEBRTC SET REMOTE DESCRIPTION: $type');

    await pc.setRemoteDescription(
      RTCSessionDescription(
        sdp.toString(),
        type.toString(),
      ),
    );

    _remoteDescriptionSet = true;
    await _flushPendingCandidates();
  }

  Future<void> addCandidate(Map data) async {
    final pc = _peerConnection;

    if (pc == null || _disposed) return;

    final candidateValue = data['candidate'];
    final sdpMid = data['sdpMid'];
    final sdpMLineIndex = _toInt(data['sdpMLineIndex']);

    if (candidateValue == null || candidateValue.toString().trim().isEmpty) {
      debugPrint('WEBRTC ADD ICE FAILED: candidate missing');
      return;
    }

    final candidate = RTCIceCandidate(
      candidateValue.toString(),
      sdpMid?.toString(),
      sdpMLineIndex,
    );

    if (!_remoteDescriptionSet) {
      _pendingCandidates.add(candidate);
      debugPrint('WEBRTC ICE QUEUED');
      return;
    }

    try {
      await pc.addCandidate(candidate);
      debugPrint('WEBRTC ICE ADDED');
    } catch (e) {
      debugPrint('ICE add error: $e');
    }
  }

  Future<void> enableVideo() async {
    final pc = _peerConnection;

    if (pc == null || _disposed) {
      throw Exception('Peer connection is null/disposed');
    }

    final localStream = _localStream;

    if (localStream == null) {
      throw Exception('Local stream is null');
    }

    final existingVideoTracks = localStream.getVideoTracks();

    if (existingVideoTracks.isNotEmpty) {
      final videoTrack = existingVideoTracks.first;
      videoTrack.enabled = true;

      final senders = await pc.getSenders();

      for (final sender in senders) {
        if (sender.track?.kind == 'video' || _videoSender == sender) {
          _videoSender = sender;
          break;
        }
      }

      if (_videoSender != null && _videoSender!.track == null) {
        await _videoSender!.replaceTrack(videoTrack);
      }

      if (_renderersInitialized && !_disposed) {
        localRenderer.srcObject = localStream;
      }

      await _forceAudioOn();
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

    final videoTracks = videoStream.getVideoTracks();

    if (videoTracks.isEmpty) {
      await videoStream.dispose();
      throw Exception('No video track from camera');
    }

    final videoTrack = videoTracks.first;
    videoTrack.enabled = true;

    await localStream.addTrack(videoTrack);

    final senders = await pc.getSenders();

    for (final sender in senders) {
      if (sender.track?.kind == 'video' || _videoSender == sender) {
        _videoSender = sender;
        break;
      }
    }

    if (_videoSender != null) {
      await _videoSender!.replaceTrack(videoTrack);
    } else {
      _videoSender = await pc.addTrack(videoTrack, localStream);
    }

    if (_renderersInitialized && !_disposed) {
      localRenderer.srcObject = localStream;
    }

    await _forceAudioOn();
  }

  /*
    Use this only for whole video-call -> audio-call switch.
    Do NOT use this for normal camera on/off inside video call.
    Normal camera off must use toggleCamera(false), not disableVideoHard().
  */
  Future<void> disableVideoHard() async {
    final pc = _peerConnection;
    final localStream = _localStream;

    if (pc == null || localStream == null || _disposed) return;

    final videoTracks = List<MediaStreamTrack>.from(
      localStream.getVideoTracks(),
    );

    try {
      final senders = await pc.getSenders();

      for (final sender in senders) {
        if (sender.track?.kind == 'video' || _videoSender == sender) {
          _videoSender = sender;
          break;
        }
      }

      if (_videoSender != null) {
        await _videoSender!.replaceTrack(null);
      }
    } catch (e) {
      debugPrint('Video sender detach error: $e');
    }

    for (final track in videoTracks) {
      try {
        track.enabled = false;
        await track.stop();
        await localStream.removeTrack(track);
      } catch (_) {}
    }

    if (_renderersInitialized && !_disposed) {
      localRenderer.srcObject = localStream;
    }

    await _forceAudioOn();
  }

  Future<RTCSessionDescription> createRenegotiationOffer() async {
    final pc = _peerConnection;

    if (pc == null || _disposed) {
      throw Exception('Peer connection is null/disposed');
    }

    final offer = await pc.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });

    await pc.setLocalDescription(offer);

    debugPrint('WEBRTC RENEGOTIATION OFFER CREATED');
    return offer;
  }

  Future<RTCSessionDescription> handleRenegotiationOffer(Map data) async {
    final pc = _peerConnection;

    if (pc == null || _disposed) {
      throw Exception('Peer connection is null/disposed');
    }

    final sdp = data['sdp'];
    final type = data['type'];

    if (sdp == null || type == null) {
      throw Exception('Invalid renegotiation offer');
    }

    await pc.setRemoteDescription(
      RTCSessionDescription(
        sdp.toString(),
        type.toString(),
      ),
    );

    _remoteDescriptionSet = true;
    await _flushPendingCandidates();

    final answer = await pc.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });

    await pc.setLocalDescription(answer);

    debugPrint('WEBRTC RENEGOTIATION ANSWER CREATED');
    return answer;
  }

  Future<void> handleRenegotiationAnswer(Map data) async {
    final pc = _peerConnection;

    if (pc == null || _disposed) return;

    final sdp = data['sdp'];
    final type = data['type'];

    if (sdp == null || type == null) {
      debugPrint('WEBRTC RENEGOTIATION ANSWER INVALID');
      return;
    }

    await pc.setRemoteDescription(
      RTCSessionDescription(
        sdp.toString(),
        type.toString(),
      ),
    );

    _remoteDescriptionSet = true;
    await _flushPendingCandidates();

    debugPrint('WEBRTC RENEGOTIATION ANSWER SET');
  }

  Future<void> _flushPendingCandidates() async {
    final pc = _peerConnection;

    if (pc == null || _disposed) return;

    for (final candidate in List<RTCIceCandidate>.from(_pendingCandidates)) {
      try {
        await pc.addCandidate(candidate);
        debugPrint('WEBRTC PENDING ICE ADDED');
      } catch (e) {
        debugPrint('Pending ICE add error: $e');
      }
    }

    _pendingCandidates.clear();
  }

  void toggleMic(bool enabled) {
    _micEnabled = enabled;

    final audioTracks = _localStream?.getAudioTracks() ?? [];

    for (final track in audioTracks) {
      track.enabled = _micEnabled;
      debugPrint(
        'WEBRTC MIC TOGGLE: micEnabled=$_micEnabled, track=${track.id}, actual=${track.enabled}',
      );
    }
  }

  /*
    Messenger/WhatsApp style camera off/on:
    - Only disables/enables local video track.
    - Does NOT stop the track.
    - Does NOT remove track.
    - Does NOT replace sender track with null.
  */
  void toggleCamera(bool enabled) {
    final videoTracks = _localStream?.getVideoTracks() ?? [];

    for (final track in videoTracks) {
      track.enabled = enabled;
      debugPrint('WEBRTC CAMERA TOGGLE: enabled=$enabled, track=${track.id}');
    }

    if (_renderersInitialized && !_disposed) {
      localRenderer.srcObject = _localStream;
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

      /*
        Speaker controls remote audio output only.
        It must never unmute local microphone.
      */
      for (final track in _localStream?.getAudioTracks() ?? []) {
        track.enabled = _micEnabled;
        debugPrint(
          'WEBRTC SPEAKER SET: speaker=$enabled, micPreserved=$_micEnabled, track=${track.id}, actual=${track.enabled}',
        );
      }
    } catch (e) {
      debugPrint('Set speaker error: $e');
    }
  }

  Future<void> _forceAudioOn() async {
    try {
      /*
        Called after remote stream/video switch.
        Do not force mic true here.
      */
      for (final track in _localStream?.getAudioTracks() ?? []) {
        track.enabled = _micEnabled;
        debugPrint(
          'WEBRTC AUDIO TRACK PRESERVED: micEnabled=$_micEnabled, track=${track.id}, actual=${track.enabled}',
        );
      }

      await Helper.setSpeakerphoneOn(true);

      debugPrint('WEBRTC AUDIO ROUTE FORCED ON, MIC PRESERVED=$_micEnabled');
    } catch (e) {
      debugPrint('Force audio route error: $e');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _micEnabled = true;

    try {
      _peerConnection?.onIceCandidate = null;
      _peerConnection?.onTrack = null;
      _peerConnection?.onAddStream = null;
      _peerConnection?.onConnectionState = null;
      _peerConnection?.onIceConnectionState = null;
      _peerConnection?.onSignalingState = null;

      try {
        localRenderer.srcObject = null;
        remoteRenderer.srcObject = null;
      } catch (_) {}

      for (final track in _localStream?.getTracks() ?? []) {
        try {
          track.enabled = false;
          await track.stop();
        } catch (_) {}
      }

      /*
        Remote tracks are owned by the remote peer. Stopping can sometimes
        cause renderer/object errors on Android. So only detach renderer and
        dispose stream safely below.
      */

      try {
        final senders = await _peerConnection?.getSenders();

        for (final sender in senders ?? []) {
          try {
            await sender.track?.stop();
          } catch (_) {}
        }
      } catch (_) {}

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
      _videoSender = null;
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