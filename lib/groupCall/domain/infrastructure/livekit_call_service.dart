import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hiddenly/groupCall/domain/call_models.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

class LiveKitMediaService extends ChangeNotifier {
  static bool _initialized = false;

  Room? _room;

  bool _connecting = false;
  bool _connected = false;
  bool _disconnecting = false;
  bool _disposed = false;

  bool _microphoneEnabled = true;
  bool _cameraEnabled = false;
  bool _speakerEnabled = false;

  CameraPosition _cameraPosition = CameraPosition.front;

  String? _error;

  int _connectionGeneration = 0;

  Room? get room => _room;

  bool get connecting => _connecting;
  bool get connected => _connected;

  bool get microphoneEnabled => _microphoneEnabled;
  bool get cameraEnabled => _cameraEnabled;
  bool get speakerEnabled => _speakerEnabled;

  String? get error => _error;

  // ============================================================
  // DEBUG
  // ============================================================

  void _log(String message) {
    debugPrint('[LIVEKIT] $message');
  }

  void _logRoomState({
    String reason = 'STATE',
  }) {
    final room = _room;

    _log('==================================================');
    _log('ROOM STATE: $reason');

    if (room == null) {
      _log('ROOM: NULL');
      _log('==================================================');
      return;
    }

    final local = room.localParticipant;

    _log('LOCAL PARTICIPANT: ${local?.identity ?? "NULL"}');
    _log('LOCAL NAME: ${local?.name ?? ""}');

    if (local != null) {
      _log(
        'LOCAL AUDIO PUBLICATIONS: '
        '${local.audioTrackPublications.length}',
      );

      for (final publication
          in local.audioTrackPublications) {
        _log(
          'LOCAL AUDIO -> '
          'track=${publication.track}',
        );
      }

      _log(
        'LOCAL VIDEO PUBLICATIONS: '
        '${local.videoTrackPublications.length}',
      );

      for (final publication
          in local.videoTrackPublications) {
        _log(
          'LOCAL VIDEO -> '
          'track=${publication.track}',
        );
      }
    }

    _log(
      'REMOTE COUNT: '
      '${room.remoteParticipants.length}',
    );

    for (final participant
        in room.remoteParticipants.values) {
      _log(
        'REMOTE PARTICIPANT: '
        '${participant.identity}',
      );

      _log(
        'REMOTE NAME: '
        '${participant.name}',
      );

      _log(
        'REMOTE SPEAKING: '
        '${participant.isSpeaking}',
      );

      _log(
        'REMOTE AUDIO PUBLICATIONS: '
        '${participant.audioTrackPublications.length}',
      );

      for (final publication
          in participant.audioTrackPublications) {
        _log(
          'REMOTE AUDIO -> '
          'track=${publication.track}',
        );
      }

      _log(
        'REMOTE VIDEO PUBLICATIONS: '
        '${participant.videoTrackPublications.length}',
      );

      for (final publication
          in participant.videoTrackPublications) {
        _log(
          'REMOTE VIDEO -> '
          'track=${publication.track}',
        );
      }
    }

    _log('==================================================');
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ============================================================
  // PARTICIPANTS
  // ============================================================

  List<Participant> get participants {
    final room = _room;

    if (room == null) {
      return <Participant>[];
    }

    final list = <Participant>[];

    final local = room.localParticipant;

    if (local != null) {
      list.add(local);
    }

    list.addAll(
      room.remoteParticipants.values,
    );

    list.sort((a, b) {
      final localIdentity = local?.identity;

      if (a.identity == localIdentity) {
        return -1;
      }

      if (b.identity == localIdentity) {
        return 1;
      }

      if (a.isSpeaking != b.isSpeaking) {
        return a.isSpeaking ? -1 : 1;
      }

      return a.joinedAt.compareTo(
        b.joinedAt,
      );
    });

    return List.unmodifiable(list);
  }

  // ============================================================
  // CONNECT
  // ============================================================

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
      _log(
        'CONNECT IGNORED: '
        'connecting=$_connecting '
        'connected=$_connected '
        'disconnecting=$_disconnecting',
      );

      return;
    }

    final generation =
        ++_connectionGeneration;

    _connecting = true;
    _error = null;

    _safeNotify();

    Room? createdRoom;

    _log(
      '==================================================',
    );

    _log('LIVEKIT CONNECT START');

    _log(
      'SERVER URL: ${credentials.serverUrl}',
    );

    _log(
      'ROOM FROM BACKEND: ${credentials.roomName}',
    );

    _log(
      'START WITH VIDEO: $startWithVideo',
    );

    _log(
      'GENERATION: $generation',
    );

    _log(
      '==================================================',
    );

    try {
      // ----------------------------------------------------------
      // INITIALIZE LIVEKIT
      // ----------------------------------------------------------

      if (!_initialized) {
        _log('Initializing LiveKit client...');

        await LiveKitClient.initialize();

        _initialized = true;

        _log('LiveKit client initialized.');
      }

      if (!_isGenerationValid(
        generation,
      )) {
        _log(
          'Connect cancelled after initialization.',
        );

        return;
      }

      // ----------------------------------------------------------
      // PERMISSIONS
      // ----------------------------------------------------------

      _log('Requesting permissions...');

      await _requestPermissions(
        camera: startWithVideo,
      );

      _log('Permissions granted.');

      if (!_isGenerationValid(
        generation,
      )) {
        _log(
          'Connect cancelled after permissions.',
        );

        return;
      }

      // ----------------------------------------------------------
      // CREATE ROOM
      // ----------------------------------------------------------

      _log('Creating LiveKit room...');

      createdRoom = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      createdRoom.addListener(
        _onRoomChanged,
      );

      _room = createdRoom;

      _log('Room object created.');

      // ----------------------------------------------------------
      // PREPARE CONNECTION
      // ----------------------------------------------------------

      _log('Preparing LiveKit connection...');

      await createdRoom.prepareConnection(
        credentials.serverUrl,
        credentials.participantToken,
      );

      _log(
        'LiveKit prepareConnection completed.',
      );

      if (!_isGenerationValid(
        generation,
      )) {
        _log(
          'Connect cancelled after prepareConnection.',
        );

        await _disposeSpecificRoom(
          createdRoom,
        );

        return;
      }

      // ----------------------------------------------------------
      // CONNECT
      // ----------------------------------------------------------

      _log(
        'Connecting to LiveKit room...',
      );

      await createdRoom.connect(
        credentials.serverUrl,
        credentials.participantToken,
      );

      _log(
        '==================================================',
      );

      _log('LIVEKIT CONNECTED');

      _log(
        'ROOM NAME FROM BACKEND: '
        '${credentials.roomName}',
      );

      _log(
        'LOCAL IDENTITY: '
        '${createdRoom.localParticipant?.identity}',
      );

      _log(
        'LOCAL NAME: '
        '${createdRoom.localParticipant?.name}',
      );

      _log(
        'REMOTE COUNT IMMEDIATELY AFTER CONNECT: '
        '${createdRoom.remoteParticipants.length}',
      );

      for (final participant
          in createdRoom.remoteParticipants.values) {
        _log(
          'REMOTE PARTICIPANT AFTER CONNECT: '
          '${participant.identity}',
        );
      }

      _log(
        '==================================================',
      );

      if (!_isGenerationValid(
        generation,
      )) {
        _log(
          'Connect cancelled after room connection.',
        );

        await _disposeSpecificRoom(
          createdRoom,
        );

        return;
      }

      // ----------------------------------------------------------
      // LOCAL PARTICIPANT
      // ----------------------------------------------------------

      final local =
          createdRoom.localParticipant;

      if (local == null) {
        throw StateError(
          'LiveKit connected but local participant is null.',
        );
      }

      _log(
        'Local participant available: '
        '${local.identity}',
      );

      // ----------------------------------------------------------
      // MICROPHONE
      // ----------------------------------------------------------

      _log(
        'Enabling local microphone...',
      );

      await local.setMicrophoneEnabled(
        true,
      );

      _log(
        'LOCAL MICROPHONE ENABLED',
      );

      _log(
        'LOCAL AUDIO PUBLICATIONS: '
        '${local.audioTrackPublications.length}',
      );

      for (final publication
          in local.audioTrackPublications) {
        _log(
          'LOCAL AUDIO TRACK: '
          '${publication.track}',
        );
      }

      if (!_isGenerationValid(
        generation,
      )) {
        _log(
          'Connect cancelled after microphone.',
        );

        await _disposeSpecificRoom(
          createdRoom,
        );

        return;
      }

      _microphoneEnabled = true;

      // ----------------------------------------------------------
      // CAMERA
      // ----------------------------------------------------------

      if (startWithVideo) {
        _log(
          'Enabling local camera...',
        );

        await local.setCameraEnabled(
          true,
          cameraCaptureOptions:
              CameraCaptureOptions(
            cameraPosition:
                _cameraPosition,
          ),
        );

        _cameraEnabled = true;

        _log(
          'LOCAL CAMERA ENABLED',
        );

        _log(
          'LOCAL VIDEO PUBLICATIONS: '
          '${local.videoTrackPublications.length}',
        );

        for (final publication
            in local.videoTrackPublications) {
          _log(
            'LOCAL VIDEO TRACK: '
            '${publication.track}',
          );
        }

        _log(
          'Enabling speaker for video call...',
        );

        await _setSpeakerInternal(
          true,
        );
      } else {
        _cameraEnabled = false;

        _log(
          'Audio call - camera disabled.',
        );

        await _setSpeakerInternal(
          false,
        );
      }

      if (!_isGenerationValid(
        generation,
      )) {
        _log(
          'Connect cancelled after camera setup.',
        );

        await _disposeSpecificRoom(
          createdRoom,
        );

        return;
      }

      // ----------------------------------------------------------
      // FINISHED
      // ----------------------------------------------------------

      _connected = true;
      _error = null;

      _log(
        '==================================================',
      );

      _log('LIVEKIT MEDIA READY');

      _log(
        'CONNECTED: $_connected',
      );

      _log(
        'MICROPHONE: $_microphoneEnabled',
      );

      _log(
        'CAMERA: $_cameraEnabled',
      );

      _log(
        'SPEAKER: $_speakerEnabled',
      );

      _log(
        'REMOTE COUNT: '
        '${createdRoom.remoteParticipants.length}',
      );

      _log(
        '==================================================',
      );

      _logRoomState(
        reason: 'CONNECT COMPLETE',
      );

      _safeNotify();
    } catch (e, stackTrace) {
      _log(
        '==================================================',
      );

      _log('LIVEKIT CONNECT ERROR');

      _log('ERROR: $e');

      _log(
        'STACK TRACE: $stackTrace',
      );

      _log(
        '==================================================',
      );

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

  // ============================================================
  // PERMISSIONS
  // ============================================================

  Future<void> _requestPermissions({
    required bool camera,
  }) async {
    _log(
      'Requesting microphone permission...',
    );

    final microphone =
        await Permission.microphone.request();

    _log(
      'Microphone permission: '
      '$microphone',
    );

    if (!microphone.isGranted) {
      throw StateError(
        'Microphone permission was denied.',
      );
    }

    if (camera) {
      _log(
        'Requesting camera permission...',
      );

      final cameraPermission =
          await Permission.camera.request();

      _log(
        'Camera permission: '
        '$cameraPermission',
      );

      if (!cameraPermission.isGranted) {
        throw StateError(
          'Camera permission was denied.',
        );
      }
    }
  }

  // ============================================================
  // ROOM CHANGES
  // ============================================================

  void _onRoomChanged() {
    if (_disposed) {
      return;
    }

    _logRoomState(
      reason: 'ROOM CHANGED',
    );

    _safeNotify();
  }

  // ============================================================
  // MICROPHONE
  // ============================================================

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
      _log(
        'Setting microphone: $next',
      );

      await local.setMicrophoneEnabled(
        next,
      );

      if (_disposed ||
          !identical(_room, room)) {
        return;
      }

      _microphoneEnabled = next;

      _log(
        'Microphone enabled: '
        '$_microphoneEnabled',
      );

      _logRoomState(
        reason: 'MICROPHONE TOGGLED',
      );

      _safeNotify();
    } catch (e) {
      _error = e.toString();

      _log(
        'Microphone toggle error: $e',
      );

      _safeNotify();

      rethrow;
    }
  }

  // ============================================================
  // CAMERA
  // ============================================================

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

      _log(
        'Setting camera: $next',
      );

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

      _log(
        'Camera enabled: '
        '$_cameraEnabled',
      );

      _logRoomState(
        reason: 'CAMERA TOGGLED',
      );

      _safeNotify();
    } catch (e) {
      _error = e.toString();

      _log(
        'Camera toggle error: $e',
      );

      _safeNotify();

      rethrow;
    }
  }

  // ============================================================
  // SWITCH CAMERA
  // ============================================================

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
        _log(
          'Switching camera: '
          '$_cameraPosition -> $nextPosition',
        );

        await track.setCameraPosition(
          nextPosition,
        );

        if (_disposed ||
            !identical(_room, room)) {
          return;
        }

        _cameraPosition =
            nextPosition;

        _log(
          'Camera switched successfully.',
        );

        _safeNotify();
      } catch (e) {
        _error = e.toString();

        _log(
          'Camera switch error: $e',
        );

        _safeNotify();

        rethrow;
      }

      return;
    }

    _log(
      'switchCamera(): '
      'No LocalVideoTrack found.',
    );
  }

  // ============================================================
  // SPEAKER
  // ============================================================

  Future<void> setSpeaker(
    bool enabled,
  ) async {
    if (_disposed) return;

    try {
      _log(
        'Setting speaker: $enabled',
      );

      await _setSpeakerInternal(
        enabled,
      );

      if (_disposed) return;

      _speakerEnabled = enabled;

      _log(
        'Speaker enabled: '
        '$_speakerEnabled',
      );

      _safeNotify();
    } catch (e) {
      _error = e.toString();

      _log(
        'Speaker error: $e',
      );

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

  // ============================================================
  // VIDEO TRACK
  // ============================================================

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

  // ============================================================
  // DISPLAY NAME
  // ============================================================

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
              (decoded['full_name'] ?? '')
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

  // ============================================================
  // AVATAR
  // ============================================================

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

  // ============================================================
  // DISCONNECT
  // ============================================================

  Future<void> disconnect() async {
    if (_disposed ||
        _disconnecting) {
      return;
    }

    _log(
      '==================================================',
    );

    _log('LIVEKIT DISCONNECT REQUESTED');

    _logRoomState(
      reason: 'BEFORE DISCONNECT',
    );

    _disconnecting = true;

    // Invalidates an in-progress connect().
    _connectionGeneration++;

    try {
      await _disposeRoom();
    } finally {
      _disconnecting = false;

      _log(
        'LIVEKIT DISCONNECTED',
      );

      _log(
        '==================================================',
      );

      _safeNotify();
    }
  }

  // ============================================================
  // DISPOSE SPECIFIC ROOM
  // ============================================================

  Future<void> _disposeSpecificRoom(
    Room room,
  ) async {
    _log(
      'Disposing specific LiveKit room...',
    );

    room.removeListener(
      _onRoomChanged,
    );

    if (identical(_room, room)) {
      _room = null;
    }

    try {
      await room.disconnect();

      _log(
        'Specific room disconnected.',
      );
    } catch (e) {
      _log(
        'Specific room disconnect error: $e',
      );
    }

    try {
      await room.dispose();

      _log(
        'Specific room disposed.',
      );
    } catch (e) {
      _log(
        'Specific room dispose error: $e',
      );
    }

    if (_room == null) {
      _resetMediaState();
    }
  }

  // ============================================================
  // DISPOSE CURRENT ROOM
  // ============================================================

  Future<void> _disposeRoom() async {
    final room = _room;

    _room = null;

    if (room != null) {
      room.removeListener(
        _onRoomChanged,
      );

      try {
        await room.disconnect();

        _log(
          'Room disconnected.',
        );
      } catch (e) {
        _log(
          'Room disconnect error: $e',
        );
      }

      try {
        await room.dispose();

        _log(
          'Room disposed.',
        );
      } catch (e) {
        _log(
          'Room dispose error: $e',
        );
      }
    }

    _resetMediaState();
  }

  // ============================================================
  // RESET
  // ============================================================

  void _resetMediaState() {
    _connected = false;
    _connecting = false;

    _cameraEnabled = false;
    _microphoneEnabled = true;
    _speakerEnabled = false;

    _cameraPosition =
        CameraPosition.front;
  }

  // ============================================================
  // DISPOSE SERVICE
  // ============================================================

  @override
  void dispose() {
    if (_disposed) return;

    _log(
      '==================================================',
    );

    _log(
      'LiveKitMediaService.dispose() CALLED',
    );

    _logRoomState(
      reason: 'SERVICE DISPOSE',
    );

    _disposed = true;

    _connectionGeneration++;

    final room = _room;

    _room = null;

    if (room != null) {
      room.removeListener(
        _onRoomChanged,
      );

      unawaited(
        room.disconnect().catchError(
          (Object error) {
            _log(
              'Dispose disconnect error: '
              '$error',
            );
          },
        ),
      );

      unawaited(
        room.dispose().then<void>(
          (_) {
            _log(
              'Room disposed from '
              'service dispose().',
            );
          },
        ).catchError(
          (Object error) {
            _log(
              'Dispose room error: '
              '$error',
            );
          },
        ),
      );
    }

    _log(
      'LiveKitMediaService disposed.',
    );

    _log(
      '==================================================',
    );

    super.dispose();
  }
}