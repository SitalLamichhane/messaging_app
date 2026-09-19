import 'dart:async';

import 'package:flutter/foundation.dart';
import '../infrastructure/call_api_service.dart';
import '../infrastructure/call_socket_service.dart';
import '../infrastructure/livekit_call_service.dart';

enum GroupCallPhase {
  idle,
  checking,
  starting,
  joining,
  connected,
  leaving,
  ended,
  error,
}

class GroupCallController extends ChangeNotifier {
  final CallApiService api;
  final CallSocketService socket;
  final LiveKitCallService liveKit;

  GroupCallPhase _phase = GroupCallPhase.idle;
  CallSessionDto? _call;
  CallSessionDto? _activeDiscoveredCall;
  String? _error;
  StreamSubscription<CallSocketEvent>? _socketSub;
  bool _disposed = false;

  GroupCallController({
    required this.api,
    required this.socket,
    required this.liveKit,
  }) {
    liveKit.addListener(_forwardLiveKitChanges);
  }

  GroupCallPhase get phase => _phase;
  CallSessionDto? get call => _call;
  CallSessionDto? get activeDiscoveredCall =>
      _activeDiscoveredCall;
  String? get error => _error;

  bool get isBusy => {
        GroupCallPhase.checking,
        GroupCallPhase.starting,
        GroupCallPhase.joining,
        GroupCallPhase.leaving,
      }.contains(_phase);

  bool get connected =>
      _phase == GroupCallPhase.connected &&
      liveKit.connected;

  void _forwardLiveKitChanges() {
    if (!_disposed) notifyListeners();
  }

  Future<CallSessionDto?> checkActiveCall(
    int conversationId,
  ) async {
    _phase = GroupCallPhase.checking;
    _error = null;
    notifyListeners();

    try {
      final result =
          await api.getActiveGroupCall(conversationId);

      _activeDiscoveredCall =
          result.active ? result.call : null;

      _phase = GroupCallPhase.idle;
      notifyListeners();
      return _activeDiscoveredCall;
    } on CallApiException catch (e) {
      // If you have not added ActiveGroupCallView yet,
      // a 404 here simply means the banner cannot be discovered.
      _error = e.message;
      _phase = GroupCallPhase.idle;
      notifyListeners();
      return null;
    } catch (e) {
      _error = e.toString();
      _phase = GroupCallPhase.idle;
      notifyListeners();
      return null;
    }
  }

  /// Starts a brand-new group call.
  ///
  /// If backend returns 409 because the group already has an active call,
  /// we discover that call and JOIN it rather than creating a second room.
  Future<void> startGroupCall({
    required int conversationId,
    required bool video,
  }) async {
    _phase = GroupCallPhase.starting;
    _error = null;
    notifyListeners();

    try {
      final started = await api.startGroupCall(
        conversationId: conversationId,
        isVideo: video,
      );

      _call = started;
      await _joinCurrentCall();
    } on CallApiException catch (e) {
      if (e.statusCode == 409) {
        final active =
            await api.getActiveGroupCall(conversationId);

        if (active.active && active.call != null) {
          _call = active.call;
          await _joinCurrentCall();
          return;
        }
      }

      _phase = GroupCallPhase.error;
      _error = e.message;
      notifyListeners();
      rethrow;
    } catch (e) {
      _phase = GroupCallPhase.error;
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Join/rejoin an existing ongoing call.
  ///
  /// Backend requirement:
  /// group participants in LEFT / DECLINED / MISSED state must be allowed
  /// to receive a fresh LiveKit token while the CallSession is still active.
  Future<void> joinExistingCall(
    CallSessionDto call,
  ) async {
    _call = call;
    _error = null;
    await _joinCurrentCall();
  }

  Future<void> _joinCurrentCall() async {
    final call = _call;
    if (call == null) {
      throw StateError('No call selected.');
    }

    _phase = GroupCallPhase.joining;
    notifyListeners();

    try {
      await socket.connect(call.conversationId);

      await _socketSub?.cancel();
      _socketSub = socket.events.listen(
        _onSocketEvent,
      );

      // Do NOT separately call action=accept for a group join.
      // LiveKitTokenView already marks the participant JOINED in your backend.
      final credentials =
          await api.getLiveKitToken(call.callId);

      await liveKit.connect(
        credentials: credentials,
        enableCameraInitially: call.isVideo,
      );

      _call = call.copyWith(
        status: call.status ==
                CallSessionStatus.ringing
            ? CallSessionStatus.accepted
            : call.status,
        roomName: credentials.roomName,
      );

      _activeDiscoveredCall = _call;
      _phase = GroupCallPhase.connected;
      _error = null;
      notifyListeners();
    } on CallApiException catch (e) {
      _phase = GroupCallPhase.error;
      _error = e.message;
      notifyListeners();
      rethrow;
    } catch (e) {
      _phase = GroupCallPhase.error;
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Incoming "decline".
  ///
  /// With the backend rejoin fix, the member may still join later while
  /// the same group CallSession remains active.
  Future<void> declineIncoming(
    CallSessionDto incoming,
  ) async {
    _call = incoming;

    try {
      await api.updateStatus(
        callId: incoming.callId,
        action: 'reject',
      );
    } finally {
      _phase = GroupCallPhase.ended;
      notifyListeners();
    }
  }

  /// The red button in a GROUP CALL must ALWAYS use "leave".
  ///
  /// Never send "ended" from this button. The backend should end the
  /// CallSession only when nobody remains JOINED.
  Future<void> leave() async {
    final call = _call;
    if (call == null) return;

    _phase = GroupCallPhase.leaving;
    notifyListeners();

    Object? apiError;

    try {
      await api.updateStatus(
        callId: call.callId,
        action: 'leave',
      );
    } catch (e) {
      apiError = e;
    }

    await liveKit.disconnect();
    await _socketSub?.cancel();
    _socketSub = null;
    await socket.disconnect();

    _phase = GroupCallPhase.ended;
    _activeDiscoveredCall = null;
    notifyListeners();

    if (apiError != null) {
      // If the app loses network here, LiveKit webhook on the backend should
      // be the final authority and mark the participant LEFT.
      throw apiError;
    }
  }

  Future<void> _terminateLocally() async {
    await liveKit.disconnect();
    await _socketSub?.cancel();
    _socketSub = null;
    await socket.disconnect();

    _phase = GroupCallPhase.ended;
    _activeDiscoveredCall = null;
    notifyListeners();
  }

  void _onSocketEvent(CallSocketEvent event) {
    final data = event.data;

    final incomingConversationId =
        int.tryParse(
          (data['conversation_id'] ?? '').toString(),
        ) ??
        0;

    if (_call != null &&
        incomingConversationId != 0 &&
        incomingConversationId !=
            _call!.conversationId) {
      return;
    }

    if (event.type == 'call_status_updated') {
      final status =
          CallSessionStatus.fromJson(data['status']);

      if (_call != null) {
        _call = _call!.copyWith(status: status);
      }

      if (status.isTerminal) {
        _terminateLocally();
        return;
      }
    }

    if (event.type == 'call_participant_joined') {
      // LiveKit itself is the source of truth for who is actually in the room.
      // Room ChangeNotifier will rebuild participant tiles automatically.
      notifyListeners();
      return;
    }

    if (event.type == 'incoming_call') {
      // Useful when the call started while this group chat was already open.
      try {
        final incoming = CallSessionDto.fromJson(data);
        if (incoming.isGroup &&
            incoming.status.isActive) {
          _activeDiscoveredCall = incoming;
          notifyListeners();
        }
      } catch (_) {}
    }
  }

  Future<void> toggleMicrophone() =>
      liveKit.toggleMicrophone();

  Future<void> toggleCamera() =>
      liveKit.toggleCamera();

  Future<void> switchCamera() =>
      liveKit.switchCamera();

  Future<void> toggleSpeaker() =>
      liveKit.toggleSpeaker();

  @override
  void dispose() {
    _disposed = true;
    liveKit.removeListener(_forwardLiveKitChanges);
    _socketSub?.cancel();
    liveKit.dispose();
    socket.dispose();
    super.dispose();
  }
}
