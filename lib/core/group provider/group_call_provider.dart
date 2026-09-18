import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hiddenly/group/group_api_service.dart';
import 'package:hiddenly/group/group_models.dart';
import 'package:livekit_client/livekit_client.dart';

/// Global lifecycle of a WhatsApp-style GROUP call.
///
/// Important: this provider owns the LiveKit Room. The call screen only renders
/// it. Therefore popping/minimizing the call screen does not automatically end
/// the call.
enum GroupCallLifecycle {
  idle,
  incoming,
  starting,
  joining,
  connecting,
  connected,
  leaving,
  ended,
  failed,
}

class GroupCallProvider extends ChangeNotifier {
  final Map<String, GroupCallSessionInfo> _activeByConversation =
      <String, GroupCallSessionInfo>{};
  final Map<String, GroupCallSessionInfo> _incomingByCall =
      <String, GroupCallSessionInfo>{};

  GroupCallSessionInfo? _currentCall;
  GroupCallJoinCredentials? _credentials;
  Room? _room;

  GroupCallLifecycle _lifecycle = GroupCallLifecycle.idle;
  String? _error;

  bool _microphoneEnabled = true;
  bool _cameraEnabled = false;
  bool _speakerEnabled = true;
  bool _minimized = false;

  DateTime? _connectedAt;
  Timer? _durationTimer;
  Duration _elapsed = Duration.zero;

  GroupCallSessionInfo? get currentCall => _currentCall;
  Room? get room => _room;
  GroupCallLifecycle get lifecycle => _lifecycle;
  String? get error => _error;

  bool get microphoneEnabled => _microphoneEnabled;
  bool get cameraEnabled => _cameraEnabled;
  bool get speakerEnabled => _speakerEnabled;
  bool get minimized => _minimized;
  Duration get elapsed => _elapsed;

  bool get hasMediaRoom => _room != null;
  bool get inCall => _currentCall != null &&
      (_lifecycle == GroupCallLifecycle.connecting ||
          _lifecycle == GroupCallLifecycle.connected ||
          _lifecycle == GroupCallLifecycle.leaving);

  bool get isBusy =>
      _lifecycle == GroupCallLifecycle.starting ||
      _lifecycle == GroupCallLifecycle.joining ||
      _lifecycle == GroupCallLifecycle.connecting ||
      _lifecycle == GroupCallLifecycle.leaving;

  List<GroupCallSessionInfo> get incomingCalls =>
      List.unmodifiable(_incomingByCall.values);

  GroupCallSessionInfo? get primaryIncomingCall =>
      _incomingByCall.isEmpty ? null : _incomingByCall.values.first;

  GroupCallSessionInfo? activeCallFor(String conversationId) =>
      _activeByConversation[conversationId.trim()];

  List<Participant> get participants {
    final value = _room;
    if (value == null) return const <Participant>[];

    final result = <Participant>[];
    final local = value.localParticipant;
    if (local != null) result.add(local);
    result.addAll(value.remoteParticipants.values);

    result.sort((a, b) {
      if (a.isSpeaking == b.isSpeaking) {
        return participantName(a).compareTo(participantName(b));
      }
      return a.isSpeaking ? -1 : 1;
    });
    return result;
  }

  String participantName(Participant participant) {
    final name = participant.name.trim();
    if (name.isNotEmpty) return name;
    final identity = participant.identity.trim();
    return identity.isEmpty ? 'Participant' : identity;
  }

  VideoTrack? videoTrackFor(Participant participant) {
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      if (!publication.muted && track is VideoTrack) return track;
    }
    return null;
  }

  bool participantMicrophoneEnabled(Participant participant) {
    for (final publication in participant.audioTrackPublications) {
      if (!publication.muted) return true;
    }
    return false;
  }

  Future<GroupCallSessionInfo?> refreshActiveCall(
    String conversationId, {
    bool notify = true,
  }) async {
    final id = conversationId.trim();
    if (id.isEmpty) return null;

    try {
      final call = await GroupApiService.getActiveCall(id);
      if (call == null || !call.isActive) {
        _activeByConversation.remove(id);
      } else {
        _activeByConversation[id] = call;
      }
      if (notify) notifyListeners();
      return call;
    } catch (e) {
      _error = e.toString();
      if (notify) notifyListeners();
      return _activeByConversation[id];
    }
  }

  Future<bool> startCall({
    required String conversationId,
    required bool video,
  }) async {
    if (isBusy || inCall) return false;

    _lifecycle = GroupCallLifecycle.starting;
    _error = null;
    _minimized = false;
    notifyListeners();

    try {
      final credentials = await GroupApiService.startCall(
        conversationId: conversationId,
        video: video,
      );
      _activeByConversation[credentials.call.conversationId] = credentials.call;
      _incomingByCall.remove(credentials.call.callId);
      await _connectCredentials(credentials);
      return _lifecycle == GroupCallLifecycle.connected;
    } catch (e, st) {
      debugPrint('GROUP CALL START PROVIDER ERROR: $e');
      debugPrintStack(stackTrace: st);
      _error = e.toString();
      _lifecycle = GroupCallLifecycle.failed;
      notifyListeners();
      return false;
    }
  }

  Future<bool> joinCall(String callId) async {
    final id = callId.trim();
    if (id.isEmpty || isBusy || inCall) return false;

    _lifecycle = GroupCallLifecycle.joining;
    _error = null;
    _minimized = false;
    notifyListeners();

    try {
      final credentials = await GroupApiService.joinCall(id);
      _activeByConversation[credentials.call.conversationId] = credentials.call;
      _incomingByCall.remove(credentials.call.callId);
      await _connectCredentials(credentials);
      return _lifecycle == GroupCallLifecycle.connected;
    } catch (e, st) {
      debugPrint('GROUP CALL JOIN PROVIDER ERROR: $e');
      debugPrintStack(stackTrace: st);
      _error = e.toString();
      _lifecycle = GroupCallLifecycle.failed;
      notifyListeners();
      return false;
    }
  }

  Future<void> _connectCredentials(GroupCallJoinCredentials value) async {
    await _disposeRoomOnly();

    _credentials = value;
    _currentCall = value.call;
    _microphoneEnabled = true;
    _cameraEnabled = value.call.isVideo;
    _speakerEnabled = true;
    _lifecycle = GroupCallLifecycle.connecting;
    _error = null;
    notifyListeners();

    final nextRoom = Room();
    nextRoom.addListener(_onRoomChanged);
    _room = nextRoom;

    try {
      await nextRoom.connect(value.url.trim(), value.token.trim());

      final local = nextRoom.localParticipant;
      if (local == null) {
        throw StateError('LiveKit local participant was not created.');
      }

      await local.setMicrophoneEnabled(true);

      if (_cameraEnabled) {
        try {
          await local.setCameraEnabled(true);
        } catch (e) {
          debugPrint('GROUP CALL CAMERA START ERROR: $e');
          _cameraEnabled = false;
        }
      }

      if (!kIsWeb) {
        try {
          await nextRoom.setSpeakerOn(_speakerEnabled);
        } catch (e) {
          debugPrint('GROUP CALL SPEAKER START ERROR: $e');
        }
      } else if (!nextRoom.canPlaybackAudio) {
        try {
          await nextRoom.startAudio();
        } catch (e) {
          debugPrint('GROUP CALL WEB AUDIO ERROR: $e');
        }
      }

      _connectedAt = DateTime.now();
      _elapsed = Duration.zero;
      _startDurationTicker();
      _lifecycle = GroupCallLifecycle.connected;
      notifyListeners();
    } catch (_) {
      await _disposeRoomOnly();
      rethrow;
    }
  }

  void _startDurationTicker() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = _connectedAt;
      if (started == null) return;
      _elapsed = DateTime.now().difference(started);
      notifyListeners();
    });
  }

  Future<void> toggleMicrophone() async {
    final local = _room?.localParticipant;
    if (local == null) return;

    final next = !_microphoneEnabled;
    try {
      await local.setMicrophoneEnabled(next);
      _microphoneEnabled = next;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> toggleCamera() async {
    final local = _room?.localParticipant;
    if (local == null) return;

    final next = !_cameraEnabled;
    try {
      await local.setCameraEnabled(next);
      _cameraEnabled = next;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> toggleSpeaker() async {
    final value = _room;
    if (value == null) return;

    if (kIsWeb) {
      try {
        await value.startAudio();
      } catch (e) {
        _error = e.toString();
        notifyListeners();
      }
      return;
    }

    final next = !_speakerEnabled;
    try {
      await value.setSpeakerOn(next);
      _speakerEnabled = next;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> switchCamera() async {
    final local = _room?.localParticipant;
    if (local == null || !_cameraEnabled) return;

    for (final publication in local.videoTrackPublications) {
      final track = publication.track;
      if (track is! LocalVideoTrack) continue;

      try {
        final options = track.currentOptions;
        if (options is! CameraCaptureOptions) return;

        final nextPosition = options.cameraPosition == CameraPosition.front
            ? CameraPosition.back
            : CameraPosition.front;
        await track.setCameraPosition(nextPosition);
      } catch (e) {
        _error = e.toString();
        notifyListeners();
      }
      return;
    }
  }

  Future<void> declineCall(String callId) async {
    final id = callId.trim();
    if (id.isEmpty) return;

    try {
      await GroupApiService.declineCall(id);
    } catch (e) {
      _error = e.toString();
    }

    _incomingByCall.remove(id);
    if (_incomingByCall.isEmpty && !inCall) {
      _lifecycle = GroupCallLifecycle.idle;
    }
    notifyListeners();
  }

  Future<bool> ringMembers(List<String> userIds) async {
    final call = _currentCall;
    if (call == null || userIds.isEmpty) return false;

    try {
      await GroupApiService.ringMembers(
        callId: call.callId,
        userIds: userIds,
      );
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> leaveCurrentCall() async {
    final call = _currentCall;
    if (call == null) {
      await _disposeRoomOnly();
      _resetCurrentCall();
      return;
    }

    if (_lifecycle == GroupCallLifecycle.leaving) return;
    _lifecycle = GroupCallLifecycle.leaving;
    notifyListeners();

    // Disconnect media immediately. Backend failure must not keep microphone or
    // camera alive on the user's device.
    await _disposeRoomOnly();

    try {
      await GroupApiService.leaveCall(call.callId);
    } catch (e) {
      debugPrint('GROUP CALL LEAVE API ERROR: $e');
      _error = e.toString();
    }

    await refreshActiveCall(call.conversationId, notify: false);
    _resetCurrentCall();
    notifyListeners();
  }

  /// Used when UI goes back to chat but the call should stay connected.
  void setMinimized(bool value) {
    if (!inCall) value = false;
    if (_minimized == value) return;
    _minimized = value;
    notifyListeners();
  }

  Future<void> reconnectCurrentCall() async {
    final call = _currentCall;
    if (call == null || inCall) return;
    await joinCall(call.callId);
  }

  void handleInvite(GroupCallSessionInfo call) {
    if (!call.isActive) return;

    _activeByConversation[call.conversationId] = call;

    // Never ring the current call back at the local user.
    if (_currentCall?.callId == call.callId) {
      notifyListeners();
      return;
    }

    _incomingByCall[call.callId] = call;
    if (!inCall) _lifecycle = GroupCallLifecycle.incoming;
    notifyListeners();
  }

  void handleCallUpdated(GroupCallSessionInfo call) {
    if (call.isActive) {
      _activeByConversation[call.conversationId] = call;
    } else {
      _activeByConversation.remove(call.conversationId);
      _incomingByCall.remove(call.callId);
    }

    if (_currentCall?.callId == call.callId) {
      _currentCall = call;
      if (!call.isActive) {
        unawaited(_disposeRoomOnly());
        _resetCurrentCall();
        _lifecycle = GroupCallLifecycle.ended;
      }
    }

    notifyListeners();
  }

  void removeIncoming(String callId) {
    if (_incomingByCall.remove(callId.trim()) != null) {
      if (_incomingByCall.isEmpty && !inCall) {
        _lifecycle = GroupCallLifecycle.idle;
      }
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    if (_lifecycle == GroupCallLifecycle.failed && _currentCall == null) {
      _lifecycle = _incomingByCall.isEmpty
          ? GroupCallLifecycle.idle
          : GroupCallLifecycle.incoming;
    }
    notifyListeners();
  }

  void _onRoomChanged() {
    notifyListeners();
  }

  Future<void> _disposeRoomOnly() async {
    final value = _room;
    _room = null;

    if (value != null) {
      value.removeListener(_onRoomChanged);
      try {
        await value.disconnect();
      } catch (_) {}
      try {
        await value.dispose();
      } catch (_) {}
    }
  }

  void _resetCurrentCall() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _connectedAt = null;
    _elapsed = Duration.zero;
    _credentials = null;
    _currentCall = null;
    _microphoneEnabled = true;
    _cameraEnabled = false;
    _speakerEnabled = true;
    _minimized = false;
    _lifecycle = _incomingByCall.isEmpty
        ? GroupCallLifecycle.idle
        : GroupCallLifecycle.incoming;
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    final value = _room;
    _room = null;
    if (value != null) {
      value.removeListener(_onRoomChanged);
      unawaited(() async {
        try {
          await value.disconnect();
        } catch (_) {}
        try {
          await value.dispose();
        } catch (_) {}
      }());
    }
    super.dispose();
  }
}
