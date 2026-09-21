import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hiddenly/groupCall/domain/call_models.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

class LiveKitMediaService
    extends ChangeNotifier {
  static bool _initialized = false;

  Room? _room;

  bool _connecting = false;
  bool _connected = false;
  bool _disconnecting = false;
  bool _disposed = false;

  bool _microphoneEnabled = true;
  bool _cameraEnabled = false;
  bool _speakerEnabled = false;

  CameraPosition _cameraPosition =
      CameraPosition.front;

  String? _error;

  int _connectionGeneration = 0;

  Room? get room => _room;

  bool get connecting => _connecting;
  bool get connected => _connected;

  bool get microphoneEnabled =>
      _microphoneEnabled;

  bool get cameraEnabled =>
      _cameraEnabled;

  bool get speakerEnabled =>
      _speakerEnabled;

  String? get error => _error;

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  List<Participant> get participants {
    final room = _room;

    if (room == null) {
      return <Participant>[];
    }

    final list =
        <Participant>[];

    final local =
        room.localParticipant;

    if (local != null) {
      list.add(local);
    }

    list.addAll(
      room.remoteParticipants.values,
    );

    list.sort((a, b) {
      final localIdentity =
          local?.identity;

      if (a.identity ==
          localIdentity) {
        return -1;
      }

      if (b.identity ==
          localIdentity) {
        return 1;
      }

      if (a.isSpeaking !=
          b.isSpeaking) {
        return a.isSpeaking
            ? -1
            : 1;
      }

      return a.joinedAt.compareTo(
        b.joinedAt,
      );
    });

    return List.unmodifiable(list);
  }

  Future<void> connect({
    required LiveKitCredentials credentials,
    required bool startWithVideo,
  }) async {
    if (_disposed) {
      throw StateError(
        'LiveKitMediaService has been disposed.',
      );
    }

    if (_connecting ||
        _connected ||
        _disconnecting) {
      return;
    }

    final generation =
        ++_connectionGeneration;

    _connecting = true;
    _error = null;
    _safeNotify();

    Room? createdRoom;

    try {
      if (!_initialized) {
        await LiveKitClient.initialize();
        _initialized = true;
      }

      if (!_isGenerationValid(
        generation,
      )) {
        return;
      }

      await _requestPermissions(
        camera: startWithVideo,
      );

      if (!_isGenerationValid(
        generation,
      )) {
        return;
      }

      createdRoom = Room(
        roomOptions:
            const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      createdRoom.addListener(
        _onRoomChanged,
      );

      _room = createdRoom;

      await createdRoom.prepareConnection(
        credentials.serverUrl,
        credentials.participantToken,
      );

      if (!_isGenerationValid(
        generation,
      )) {
        await _disposeSpecificRoom(
          createdRoom,
        );
        return;
      }

      await createdRoom.connect(
        credentials.serverUrl,
        credentials.participantToken,
      );

      if (!_isGenerationValid(
        generation,
      )) {
        await _disposeSpecificRoom(
          createdRoom,
        );
        return;
      }

      final local =
          createdRoom.localParticipant;

      await local?.setMicrophoneEnabled(
        true,
      );

      if (!_isGenerationValid(
        generation,
      )) {
        await _disposeSpecificRoom(
          createdRoom,
        );
        return;
      }

      _microphoneEnabled = true;

      if (startWithVideo) {
        await local?.setCameraEnabled(
          true,
          cameraCaptureOptions:
              CameraCaptureOptions(
            cameraPosition:
                _cameraPosition,
          ),
        );

        _cameraEnabled = true;

        await _setSpeakerInternal(
          true,
        );
      } else {
        _cameraEnabled = false;

        await _setSpeakerInternal(
          false,
        );
      }

      if (!_isGenerationValid(
        generation,
      )) {
        await _disposeSpecificRoom(
          createdRoom,
        );
        return;
      }

      _connected = true;
      _error = null;
    } catch (e) {
      if (!_disposed) {
        _error = e.toString();
      }

      if (createdRoom != null) {
        await _disposeSpecificRoom(
          createdRoom,
        );
      } else {
        await _disposeRoom();
      }

      rethrow;
    } finally {
      if (!_disposed &&
          generation ==
              _connectionGeneration) {
        _connecting = false;
        _safeNotify();
      }
    }
  }

  bool _isGenerationValid(
    int generation,
  ) {
    return !_disposed &&
        generation ==
            _connectionGeneration;
  }

  Future<void> _requestPermissions({
    required bool camera,
  }) async {
    final microphone =
        await Permission.microphone
            .request();

    if (!microphone.isGranted) {
      throw StateError(
        'Microphone permission was denied.',
      );
    }

    if (camera) {
      final cameraPermission =
          await Permission.camera
              .request();

      if (!cameraPermission.isGranted) {
        throw StateError(
          'Camera permission was denied.',
        );
      }
    }
  }

  void _onRoomChanged() {
    _safeNotify();
  }

  Future<void> toggleMicrophone() async {
    if (_disposed ||
        !_connected) {
      return;
    }

    final room = _room;

    if (room == null) return;

    final local =
        room.localParticipant;

    if (local == null) return;

    final next =
        !_microphoneEnabled;

    try {
      await local.setMicrophoneEnabled(
        next,
      );

      if (_disposed ||
          !identical(_room, room)) {
        return;
      }

      _microphoneEnabled = next;
      _safeNotify();
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      rethrow;
    }
  }

  Future<void> toggleCamera() async {
    if (_disposed ||
        !_connected) {
      return;
    }

    final room = _room;

    if (room == null) return;

    final local =
        room.localParticipant;

    if (local == null) return;

    final next =
        !_cameraEnabled;

    try {
      if (next) {
        final permission =
            await Permission.camera
                .request();

        if (!permission.isGranted) {
          throw StateError(
            'Camera permission was denied.',
          );
        }
      }

      await local.setCameraEnabled(
        next,
        cameraCaptureOptions:
            CameraCaptureOptions(
          cameraPosition:
              _cameraPosition,
        ),
      );

      if (_disposed ||
          !identical(_room, room)) {
        return;
      }

      _cameraEnabled = next;
      _safeNotify();
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      rethrow;
    }
  }

  Future<void> switchCamera() async {
    if (_disposed ||
        !_connected ||
        !_cameraEnabled) {
      return;
    }

    final room = _room;

    if (room == null) return;

    final publications =
        room.localParticipant
            ?.videoTrackPublications;

    if (publications == null) {
      return;
    }

    for (final publication
        in publications) {
      final track =
          publication.track;

      if (track is! LocalVideoTrack) {
        continue;
      }

      final nextPosition =
          _cameraPosition.switched();

      try {
        await track.setCameraPosition(
          nextPosition,
        );

        if (_disposed ||
            !identical(_room, room)) {
          return;
        }

        _cameraPosition =
            nextPosition;

        _safeNotify();
      } catch (e) {
        _error = e.toString();
        _safeNotify();
        rethrow;
      }

      return;
    }
  }

  Future<void> setSpeaker(
    bool enabled,
  ) async {
    if (_disposed) return;

    try {
      await _setSpeakerInternal(
        enabled,
      );

      if (_disposed) return;

      _speakerEnabled = enabled;
      _safeNotify();
    } catch (e) {
      _error = e.toString();
      _safeNotify();
      rethrow;
    }
  }

  Future<void> _setSpeakerInternal(
    bool enabled,
  ) async {
    await AudioManager.instance
        .setSpeakerOutputPreferred(
      enabled,
      force: false,
    );

    _speakerEnabled = enabled;
  }

  Future<void> toggleSpeaker() async {
    await setSpeaker(
      !_speakerEnabled,
    );
  }

  VideoTrack? videoTrackFor(
    Participant participant,
  ) {
    for (final publication
        in participant
            .videoTrackPublications) {
      final track =
          publication.track;

      if (track is VideoTrack) {
        return track;
      }
    }

    return null;
  }

  String displayNameFor(
    Participant participant,
  ) {
    final name =
        participant.name.trim();

    if (name.isNotEmpty) {
      return name;
    }

    final metadata =
        participant.metadata;

    if (metadata != null &&
        metadata.trim().isNotEmpty) {
      try {
        final decoded =
            jsonDecode(metadata);

        if (decoded is Map) {
          final value =
              (decoded['full_name'] ??
                      '')
                  .toString()
                  .trim();

          if (value.isNotEmpty) {
            return value;
          }
        }
      } catch (_) {}
    }

    return participant.identity;
  }

  String avatarFor(
    Participant participant,
  ) {
    final metadata =
        participant.metadata;

    if (metadata == null ||
        metadata.trim().isEmpty) {
      return '';
    }

    try {
      final decoded =
          jsonDecode(metadata);

      if (decoded is Map) {
        return (decoded[
                    'profile_picture'] ??
                '')
            .toString()
            .trim();
      }
    } catch (_) {}

    return '';
  }

  Future<void> disconnect() async {
    if (_disposed ||
        _disconnecting) {
      return;
    }

    _disconnecting = true;

    // Invalidates an in-progress connect().
    _connectionGeneration++;

    try {
      await _disposeRoom();
    } finally {
      _disconnecting = false;
      _safeNotify();
    }
  }

  Future<void> _disposeSpecificRoom(
    Room room,
  ) async {
    room.removeListener(
      _onRoomChanged,
    );

    if (identical(_room, room)) {
      _room = null;
    }

    try {
      await room.disconnect();
    } catch (_) {}

    try {
      await room.dispose();
    } catch (_) {}

    if (_room == null) {
      _resetMediaState();
    }
  }

  Future<void> _disposeRoom() async {
    final room = _room;

    _room = null;

    if (room != null) {
      room.removeListener(
        _onRoomChanged,
      );

      try {
        await room.disconnect();
      } catch (_) {}

      try {
        await room.dispose();
      } catch (_) {}
    }

    _resetMediaState();
  }

  void _resetMediaState() {
    _connected = false;
    _connecting = false;

    _cameraEnabled = false;
    _microphoneEnabled = true;
    _speakerEnabled = false;

    _cameraPosition =
        CameraPosition.front;
  }

  @override
  void dispose() {
    if (_disposed) return;

    _disposed = true;
    _connectionGeneration++;

    final room = _room;
    _room = null;

    if (room != null) {
      room.removeListener(
        _onRoomChanged,
      );

      unawaited(
        room.disconnect(),
      );

      unawaited(
        room.dispose().then<void>(
          (_) {},
        ),
      );
    }

    super.dispose();
  }
}