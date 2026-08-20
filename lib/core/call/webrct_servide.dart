// lib/core/call/webrct_servide.dart

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef IceCandidateCallback = void Function(RTCIceCandidate candidate);
typedef AsyncCallCallback = Future<void> Function();

/// WebRTC media layer used by [CallNotifier].
///
/// Important design rules:
/// - Audio calls request microphone only. They do not secretly open the camera.
/// - WebSocket signaling is handled outside this class.
/// - ICE candidates received before remote SDP are queued and deduplicated.
/// - Speaker routing never changes microphone mute state.
/// - A temporary network disconnect starts one delayed ICE restart, not many.
class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCRtpSender? _videoSender;

  bool _disposed = true;
  bool _renderersInitialized = false;
  bool _remoteDescriptionSet = false;
  bool _micEnabled = true;
  bool _speakerEnabled = false;
  bool _isVideoSession = false;
  bool _connectedCallbackSent = false;
  bool _restartCallbackRunning = false;

  RTCPeerConnectionState? _connectionState;
  RTCIceConnectionState? _iceConnectionState;

  Timer? _disconnectRecoveryTimer;
  DateTime? _lastRestartRequestAt;

  static const int _maxPendingCandidates = 128;
  static const Duration _disconnectGracePeriod = Duration(seconds: 5);
  static const Duration _restartCooldown = Duration(seconds: 4);

  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];
  final Set<String> _candidateKeys = <String>{};

  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  /// Configure TURN at application startup or by using dart-defines.
  ///
  /// Example:
  /// flutter run \
  ///   --dart-define=TURN_URLS=turn:turn.example.com:3478?transport=udp,turn:turn.example.com:3478?transport=tcp \
  ///   --dart-define=TURN_USERNAME=user \
  ///   --dart-define=TURN_CREDENTIAL=password
  ///
  /// Do not commit long-lived TURN passwords to the source repository.
  static List<String> turnUrls = _readEnvironmentTurnUrls();
  static String turnUsername = const String.fromEnvironment(
    'TURN_USERNAME',
    defaultValue: '',
  );
  static String turnCredential = const String.fromEnvironment(
    'TURN_CREDENTIAL',
    defaultValue: '',
  );

  static List<String> _readEnvironmentTurnUrls() {
    const raw = String.fromEnvironment('TURN_URLS', defaultValue: '');

    return raw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static void configureTurn({
    required List<String> urls,
    required String username,
    required String credential,
  }) {
    turnUrls = urls
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    turnUsername = username.trim();
    turnCredential = credential.trim();
  }

  List<String> _normalizedTurnUrls() {
    return turnUrls.map((raw) {
      final value = raw.trim();

      if (value.startsWith('turn:') || value.startsWith('turns:')) {
        return value;
      }

      return 'turn:$value';
    }).toList(growable: false);
  }

  Map<String, dynamic> _iceConfig() {
    final iceServers = <Map<String, dynamic>>[
      <String, dynamic>{
        'urls': <String>[
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ];

    final urls = _normalizedTurnUrls();
    final hasTurn = urls.isNotEmpty &&
        turnUsername.trim().isNotEmpty &&
        turnCredential.trim().isNotEmpty;

    if (hasTurn) {
      iceServers.add(<String, dynamic>{
        'urls': urls,
        'username': turnUsername.trim(),
        'credential': turnCredential.trim(),
      });
    } else {
      debugPrint(
        'WEBRTC TURN is not configured; calls may fail on restrictive networks.',
      );
    }

    return <String, dynamic>{
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  String _candidateKey(RTCIceCandidate candidate) {
    return <Object?>[
      candidate.candidate,
      candidate.sdpMid,
      candidate.sdpMLineIndex,
    ].join('|');
  }

  Future<void> initRenderers() async {
    _disposed = false;

    if (_renderersInitialized) return;

    localRenderer = RTCVideoRenderer();
    remoteRenderer = RTCVideoRenderer();

    await localRenderer.initialize();
    await remoteRenderer.initialize();

    _renderersInitialized = true;
    debugPrint('WEBRTC RENDERERS INITIALIZED');
  }

  Future<void> createConnection({
    required bool isVideoCall,
    required IceCandidateCallback onIceCandidate,
    required VoidCallback onRemoteStream,
    AsyncCallCallback? onConnectionEstablished,
    VoidCallback? onConnectionLost,
    AsyncCallCallback? onIceRestartNeeded,
  }) async {
    _disposed = false;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _candidateKeys.clear();
    _videoSender = null;
    _remoteStream = null;
    _micEnabled = true;
    _isVideoSession = isVideoCall;
    _speakerEnabled = isVideoCall;
    _connectedCallbackSent = false;
    _restartCallbackRunning = false;
    _connectionState = null;
    _iceConnectionState = null;
    _disconnectRecoveryTimer?.cancel();
    _disconnectRecoveryTimer = null;

    try {
      final pc = await createPeerConnection(_iceConfig());
      _peerConnection = pc;

      pc.onIceCandidate = (candidate) {
        if (_disposed) return;

        final value = candidate.candidate?.trim() ?? '';
        if (value.isEmpty) return;

        onIceCandidate(candidate);
      };

      Future<void> attachRemoteStream(MediaStream stream) async {
        if (_disposed) return;

        _remoteStream = stream;

        if (_renderersInitialized) {
          remoteRenderer.srcObject = stream;
        }

        await _applyAudioRoute();
        onRemoteStream();
      }

      pc.onTrack = (event) async {
        if (_disposed) return;

        if (event.streams.isNotEmpty) {
          await attachRemoteStream(event.streams.first);
          return;
        }

        _remoteStream ??= await createLocalMediaStream('remote_stream');

        final alreadyAdded = _remoteStream!
            .getTracks()
            .any((track) => track.id == event.track.id);

        if (!alreadyAdded) {
          await _remoteStream!.addTrack(event.track);
        }

        await attachRemoteStream(_remoteStream!);
      };

      // Kept for older Android/WebRTC implementations.
      pc.onAddStream = (stream) async {
        if (_disposed) return;
        await attachRemoteStream(stream);
      };

      Future<void> notifyConnected() async {
        _disconnectRecoveryTimer?.cancel();
        _disconnectRecoveryTimer = null;

        if (_connectedCallbackSent || _disposed) return;

        _connectedCallbackSent = true;
        await _applyAudioRoute();
        await onConnectionEstablished?.call();
      }

      Future<void> requestRestart() async {
        if (_disposed || _restartCallbackRunning) return;

        final now = DateTime.now();
        final previous = _lastRestartRequestAt;

        if (previous != null && now.difference(previous) < _restartCooldown) {
          return;
        }

        _lastRestartRequestAt = now;
        _restartCallbackRunning = true;

        try {
          await onIceRestartNeeded?.call();
        } finally {
          _restartCallbackRunning = false;
        }
      }

      void scheduleDisconnectedRecovery() {
        _disconnectRecoveryTimer?.cancel();
        onConnectionLost?.call();

        _disconnectRecoveryTimer = Timer(_disconnectGracePeriod, () async {
          if (_disposed) return;

          final stillDisconnected =
              _connectionState ==
                  RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
              _iceConnectionState ==
                  RTCIceConnectionState.RTCIceConnectionStateDisconnected;

          if (stillDisconnected) {
            await requestRestart();
          }
        });
      }

      pc.onConnectionState = (nextState) async {
        if (_disposed) return;

        _connectionState = nextState;
        debugPrint('WEBRTC CONNECTION STATE: $nextState');

        switch (nextState) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            await notifyConnected();
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            scheduleDisconnectedRecovery();
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            onConnectionLost?.call();
            await requestRestart();
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            _disconnectRecoveryTimer?.cancel();
            onConnectionLost?.call();
            break;
          default:
            break;
        }
      };

      pc.onIceConnectionState = (nextState) async {
        if (_disposed) return;

        _iceConnectionState = nextState;
        debugPrint('WEBRTC ICE STATE: $nextState');

        switch (nextState) {
          case RTCIceConnectionState.RTCIceConnectionStateConnected:
          case RTCIceConnectionState.RTCIceConnectionStateCompleted:
            await notifyConnected();
            break;
          case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
            scheduleDisconnectedRecovery();
            break;
          case RTCIceConnectionState.RTCIceConnectionStateFailed:
            onConnectionLost?.call();
            await requestRestart();
            break;
          case RTCIceConnectionState.RTCIceConnectionStateClosed:
            _disconnectRecoveryTimer?.cancel();
            break;
          default:
            break;
        }
      };

      pc.onSignalingState = (nextState) {
        if (_disposed) return;
        debugPrint('WEBRTC SIGNALING STATE: $nextState');
      };

      final mediaConstraints = <String, dynamic>{
        'audio': <String, dynamic>{
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        // Audio calls must not request the camera.
        'video': isVideoCall
            ? <String, dynamic>{
                'facingMode': 'user',
                'width': <String, dynamic>{'ideal': 640},
                'height': <String, dynamic>{'ideal': 360},
                'frameRate': <String, dynamic>{'ideal': 30},
              }
            : false,
      };

      final localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );
      _localStream = localStream;

      for (final track in localStream.getAudioTracks()) {
        track.enabled = _micEnabled;
      }

      for (final track in localStream.getVideoTracks()) {
        track.enabled = isVideoCall;
      }

      if (_renderersInitialized) {
        localRenderer.srcObject = localStream;
      }

      for (final track in localStream.getTracks()) {
        final sender = await pc.addTrack(track, localStream);

        if (track.kind == 'video') {
          _videoSender = sender;
        }
      }

      await _applyAudioRoute();
    } catch (error, stackTrace) {
      debugPrint('WEBRTC CREATE CONNECTION ERROR: $error');
      if (kDebugMode) debugPrint(stackTrace.toString());
      await dispose();
      rethrow;
    }
  }

  Future<RTCSessionDescription> createOffer() async {
    final pc = _peerConnection;

    if (pc == null || _disposed) {
      throw StateError('Peer connection is null or disposed');
    }

    final offer = await pc.createOffer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _isVideoSession,
    });

    await pc.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    final pc = _peerConnection;

    if (pc == null || _disposed) {
      throw StateError('Peer connection is null or disposed');
    }

    final answer = await pc.createAnswer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _isVideoSession,
    });

    await pc.setLocalDescription(answer);
    return answer;
  }

  Future<RTCSessionDescription?> currentLocalDescription() async {
    final pc = _peerConnection;
    if (pc == null || _disposed) return null;
    return pc.getLocalDescription();
  }

  Future<RTCSessionDescription> restartIce() async {
    final pc = _peerConnection;

    if (pc == null || _disposed) {
      throw StateError('Peer connection is null or disposed');
    }

    final offer = await pc.createOffer(<String, dynamic>{
      'iceRestart': true,
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _isVideoSession,
    });

    await pc.setLocalDescription(offer);
    return offer;
  }

  Future<void> setRemoteDescription(Map<dynamic, dynamic> data) async {
    final pc = _peerConnection;

    if (pc == null || _disposed) {
      throw StateError('Peer connection is null or disposed');
    }

    final sdp = data['sdp']?.toString().trim() ?? '';
    final type = data['type']?.toString().trim() ?? '';

    if (sdp.isEmpty || type.isEmpty) {
      throw ArgumentError('Remote description requires sdp and type');
    }

    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));

    _remoteDescriptionSet = true;
    await _flushPendingCandidates();
  }

  Future<void> addCandidate(Map<dynamic, dynamic> data) async {
    final pc = _peerConnection;

    if (pc == null || _disposed) return;

    final candidateValue = data['candidate']?.toString().trim() ?? '';
    final sdpMid = data['sdpMid']?.toString();
    final sdpMLineIndex = _toInt(data['sdpMLineIndex']);

    if (candidateValue.isEmpty) return;

    final candidate = RTCIceCandidate(
      candidateValue,
      sdpMid,
      sdpMLineIndex,
    );

    final key = _candidateKey(candidate);
    if (!_candidateKeys.add(key)) return;

    if (!_remoteDescriptionSet) {
      if (_pendingCandidates.length >= _maxPendingCandidates) {
        final removed = _pendingCandidates.removeAt(0);
        _candidateKeys.remove(_candidateKey(removed));
      }

      _pendingCandidates.add(candidate);
      return;
    }

    try {
      await pc.addCandidate(candidate);
    } catch (error) {
      debugPrint('WEBRTC ADD ICE ERROR: $error');
    }
  }

  Future<void> enableVideo() async {
    final pc = _peerConnection;
    final localStream = _localStream;

    if (pc == null || localStream == null || _disposed) {
      throw StateError('Peer connection or local stream is unavailable');
    }

    _isVideoSession = true;

    final existingVideoTracks = localStream.getVideoTracks();

    if (existingVideoTracks.isNotEmpty) {
      final videoTrack = existingVideoTracks.first;
      videoTrack.enabled = true;

      final senders = await pc.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video' || identical(sender, _videoSender)) {
          _videoSender = sender;
          break;
        }
      }

      if (_videoSender != null && _videoSender!.track == null) {
        await _videoSender!.replaceTrack(videoTrack);
      }

      if (_renderersInitialized) {
        localRenderer.srcObject = localStream;
      }

      await _applyAudioRoute();
      return;
    }

    final videoOnlyStream = await navigator.mediaDevices.getUserMedia(
      <String, dynamic>{
        'audio': false,
        'video': <String, dynamic>{
          'facingMode': 'user',
          'width': <String, dynamic>{'ideal': 640},
          'height': <String, dynamic>{'ideal': 360},
          'frameRate': <String, dynamic>{'ideal': 30},
        },
      },
    );

    final tracks = videoOnlyStream.getVideoTracks();
    if (tracks.isEmpty) {
      await videoOnlyStream.dispose();
      throw StateError('Camera did not provide a video track');
    }

    final videoTrack = tracks.first;
    videoTrack.enabled = true;
    await localStream.addTrack(videoTrack);

    final senders = await pc.getSenders();
    for (final sender in senders) {
      if (sender.track?.kind == 'video' || identical(sender, _videoSender)) {
        _videoSender = sender;
        break;
      }
    }

    if (_videoSender != null) {
      await _videoSender!.replaceTrack(videoTrack);
    } else {
      _videoSender = await pc.addTrack(videoTrack, localStream);
    }

    if (_renderersInitialized) {
      localRenderer.srcObject = localStream;
    }

    await _applyAudioRoute();
  }

  Future<void> disableVideoHard() async {
    final pc = _peerConnection;
    final localStream = _localStream;

    if (pc == null || localStream == null || _disposed) return;

    _isVideoSession = false;

    try {
      final senders = await pc.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video' || identical(sender, _videoSender)) {
          _videoSender = sender;
          break;
        }
      }

      if (_videoSender != null) {
        await _videoSender!.replaceTrack(null);
      }
    } catch (error) {
      debugPrint('WEBRTC VIDEO SENDER DETACH ERROR: $error');
    }

    final videoTracks = List<MediaStreamTrack>.from(
      localStream.getVideoTracks(),
    );

    for (final track in videoTracks) {
      try {
        track.enabled = false;
        await track.stop();
        await localStream.removeTrack(track);
      } catch (_) {}
    }

    if (_renderersInitialized) {
      localRenderer.srcObject = localStream;
    }

    await _applyAudioRoute();
  }

  Future<RTCSessionDescription> createRenegotiationOffer() async {
    final pc = _peerConnection;

    if (pc == null || _disposed) {
      throw StateError('Peer connection is null or disposed');
    }

    final offer = await pc.createOffer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _isVideoSession,
    });

    await pc.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> handleRenegotiationOffer(
    Map<dynamic, dynamic> data,
  ) async {
    final pc = _peerConnection;

    if (pc == null || _disposed) {
      throw StateError('Peer connection is null or disposed');
    }

    final sdp = data['sdp']?.toString().trim() ?? '';
    final type = data['type']?.toString().trim() ?? '';

    if (sdp.isEmpty || type.isEmpty) {
      throw ArgumentError('Invalid renegotiation offer');
    }

    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    _remoteDescriptionSet = true;
    await _flushPendingCandidates();

    final answer = await pc.createAnswer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _isVideoSession,
    });

    await pc.setLocalDescription(answer);
    return answer;
  }

  Future<void> handleRenegotiationAnswer(
    Map<dynamic, dynamic> data,
  ) async {
    final pc = _peerConnection;

    if (pc == null || _disposed) return;

    final sdp = data['sdp']?.toString().trim() ?? '';
    final type = data['type']?.toString().trim() ?? '';

    if (sdp.isEmpty || type.isEmpty) {
      throw ArgumentError('Invalid renegotiation answer');
    }

    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    _remoteDescriptionSet = true;
    await _flushPendingCandidates();
  }

  Future<void> _flushPendingCandidates() async {
    final pc = _peerConnection;
    if (pc == null || _disposed || !_remoteDescriptionSet) return;

    final candidates = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();

    for (final candidate in candidates) {
      try {
        await pc.addCandidate(candidate);
      } catch (error) {
        debugPrint('WEBRTC PENDING ICE ERROR: $error');
      }
    }
  }

  void toggleMic(bool enabled) {
    _micEnabled = enabled;

    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  void toggleCamera(bool enabled) {
    for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }

    if (_renderersInitialized && !_disposed) {
      localRenderer.srcObject = _localStream;
    }
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  Future<void> setSpeaker(bool enabled) async {
    _speakerEnabled = enabled;
    await _applyAudioRoute();
  }

  Future<void> _applyAudioRoute() async {
    if (_disposed) return;

    try {
      for (final track
          in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        track.enabled = _micEnabled;
      }

      await Helper.setSpeakerphoneOn(_speakerEnabled);
    } catch (error) {
      debugPrint('WEBRTC AUDIO ROUTE ERROR: $error');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _remoteDescriptionSet = false;
    _connectedCallbackSent = false;
    _restartCallbackRunning = false;
    _connectionState = null;
    _iceConnectionState = null;
    _pendingCandidates.clear();
    _candidateKeys.clear();
    _micEnabled = true;
    _speakerEnabled = false;
    _isVideoSession = false;
    _disconnectRecoveryTimer?.cancel();
    _disconnectRecoveryTimer = null;

    final pc = _peerConnection;
    final localStream = _localStream;
    final remoteStream = _remoteStream;

    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
    _videoSender = null;

    try {
      pc?.onIceCandidate = null;
      pc?.onTrack = null;
      pc?.onAddStream = null;
      pc?.onConnectionState = null;
      pc?.onIceConnectionState = null;
      pc?.onSignalingState = null;

      try {
        localRenderer.srcObject = null;
        remoteRenderer.srcObject = null;
      } catch (_) {}

      for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
        try {
          track.enabled = false;
          await track.stop();
        } catch (_) {}
      }

      try {
        await Helper.setSpeakerphoneOn(false);
      } catch (_) {}

      try {
        await pc?.close();
      } catch (_) {}

      try {
        await pc?.dispose();
      } catch (_) {}

      try {
        await localStream?.dispose();
      } catch (_) {}

      try {
        await remoteStream?.dispose();
      } catch (_) {}
    } catch (error) {
      debugPrint('WEBRTC DISPOSE ERROR: $error');
    }
  }

  Future<void> disposeRenderers() async {
    if (!_renderersInitialized) return;

    try {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    } catch (_) {}

    try {
      await localRenderer.dispose();
    } catch (_) {}

    try {
      await remoteRenderer.dispose();
    } catch (_) {}

    _renderersInitialized = false;
  }
}
