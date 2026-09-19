import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';


class LiveKitCallService extends ChangeNotifier {
  static bool _sdkInitialized = false;

  Room? _room;
  bool _connecting = false;
  bool _connected = false;
  bool _microphoneEnabled = true;
  bool _cameraEnabled = false;
  bool _speakerEnabled = false;
  CameraPosition _cameraPosition = CameraPosition.front;
  String? _error;

  Room? get room => _room;
  bool get connecting => _connecting;
  bool get connected => _connected;
  bool get microphoneEnabled => _microphoneEnabled;
  bool get cameraEnabled => _cameraEnabled;
  bool get speakerEnabled => _speakerEnabled;
  String? get error => _error;

  List<Participant> get participants {
    final room = _room;
    if (room == null) return const [];

    final result = <Participant>[
      ?room.localParticipant,
      ...room.remoteParticipants.values,
    ];

    result.sort((a, b) {
      if (a.identity == room.localParticipant?.identity) return -1;
      if (b.identity == room.localParticipant?.identity) return 1;

      if (a.isSpeaking != b.isSpeaking) {
        return a.isSpeaking ? -1 : 1;
      }

      return a.joinedAt.compareTo(b.joinedAt);
    });

    return result;
  }

  Future<void> connect({
    required LiveKitCredentials credentials,
    required bool enableCameraInitially,
  }) async {
    if (_connected || _connecting) return;

    _connecting = true;
    _error = null;
    notifyListeners();

    try {
      if (!_sdkInitialized) {
        await LiveKitClient.initialize();
        _sdkInitialized = true;
      }

      await _requestPermissions(
        camera: enableCameraInitially,
      );

      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      room.addListener(_onRoomChanged);
      _room = room;

      await room.prepareConnection(
        credentials.serverUrl,
        credentials.participantToken,
      );

      await room.connect(
        credentials.serverUrl,
        credentials.participantToken,
      );

      _connected = true;

      // Publish microphone for both audio and video calls.
      await room.localParticipant.setMicrophoneEnabled(true);
      _microphoneEnabled = true;

      if (enableCameraInitially) {
        await room.localParticipant?.setCameraEnabled(
          true,
          cameraCaptureOptions: CameraCaptureOptions(
            cameraPosition: _cameraPosition,
          ),
        );
        _cameraEnabled = true;
        await setSpeaker(true);
      } else {
        _cameraEnabled = false;
        await setSpeaker(false);
      }
    } catch (e) {
      _error = e.toString();
      await _disposeRoom();
      rethrow;
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> _requestPermissions({
    required bool camera,
  }) async {
    final mic = await Permission.microphone.request();

    if (!mic.isGranted) {
      throw StateError('Microphone permission was not granted.');
    }

    if (camera) {
      final cam = await Permission.camera.request();

      if (!cam.isGranted) {
        throw StateError('Camera permission was not granted.');
      }
    }
  }

  void _onRoomChanged() {
    final room = _room;
    if (room == null) return;

    // Room is a ChangeNotifier. It updates when participant membership,
    // tracks, active speakers, etc. change.
    notifyListeners();
  }

  Future<void> toggleMicrophone() async {
    final room = _room;
    if (room == null) return;

    final next = !_microphoneEnabled;
    await room.localParticipant?.setMicrophoneEnabled(next);
    _microphoneEnabled = next;
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    final room = _room;
    if (room == null) return;

    final next = !_cameraEnabled;

    if (next) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        throw StateError('Camera permission was not granted.');
      }
    }

    await room.localParticipant?.setCameraEnabled(
      next,
      cameraCaptureOptions: CameraCaptureOptions(
        cameraPosition: _cameraPosition,
      ),
    );

    _cameraEnabled = next;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final room = _room;
    if (room == null || !_cameraEnabled) return;

    for (final publication
        in room.localParticipant.videoTrackPublications) {
      final track = publication.track;
      if (track is LocalVideoTrack) {
        final options = track.currentOptions;

        if (options is CameraCaptureOptions) {
          _cameraPosition =
              options.cameraPosition.switched();
        } else {
          _cameraPosition = _cameraPosition.switched();
        }

        await track.setCameraPosition(_cameraPosition);
        notifyListeners();
        return;
      }
    }
  }

  Future<void> setSpeaker(bool enabled) async {
    await AudioManager.instance.setSpeakerOutputPreferred(
      enabled,
      force: false,
    );

    _speakerEnabled = enabled;
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    await setSpeaker(!_speakerEnabled);
  }

  VideoTrack? videoTrackFor(Participant participant) {
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      if (track is VideoTrack) {
        return track;
      }
    }
    return null;
  }

  String avatarFor(Participant participant) {
    final metadata = participant.metadata;
    if (metadata == null || metadata.isEmpty) return '';

    try {
      final json = jsonDecode(metadata);
      if (json is Map) {
        return (json['profile_picture'] ?? '').toString();
      }
    } catch (_) {}

    return '';
  }

  String displayNameFor(Participant participant) {
    if (participant.name.trim().isNotEmpty) {
      return participant.name.trim();
    }

    final metadata = participant.metadata;
    if (metadata != null && metadata.isNotEmpty) {
      try {
        final json = jsonDecode(metadata);
        if (json is Map) {
          final fullName = (json['full_name'] ?? '').toString();
          if (fullName.trim().isNotEmpty) return fullName.trim();
        }
      } catch (_) {}
    }

    return participant.identity;
  }

  Future<void> disconnect() async {
    await _disposeRoom();
    _connected = false;
    _connecting = false;
    notifyListeners();
  }

  Future<void> _disposeRoom() async {
    final room = _room;
    _room = null;

    if (room != null) {
      room.removeListener(_onRoomChanged);

      try {
        await room.disconnect();
      } catch (_) {}

      try {
        await room.dispose();
      } catch (_) {}
    }

    _connected = false;
    _cameraEnabled = false;
    _microphoneEnabled = true;
  }

  @override
  void dispose() {
    final room = _room;
    if (room != null) {
      room.removeListener(_onRoomChanged);
      room.disconnect();
      room.dispose();
    }
    _room = null;
    super.dispose();
  }
}
