import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hiddenly/groupCall/domain/call_models.dart';
import 'package:hiddenly/groupCall/domain/infrastructure/call_api_service.dart';
import 'package:hiddenly/groupCall/domain/infrastructure/livekit_call_service.dart';
import 'package:hiddenly/realtime/realtime_service.dart';

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
  final int conversationId;
  final CallApiService api;
  final ConversationRealtimeService realtime;
  final LiveKitMediaService liveKit;

  GroupCallPhase _phase = GroupCallPhase.idle;

  CallSessionDto? _call;
  CallSessionDto? _activeDiscoveredCall;

  String? _error;

  StreamSubscription<ConversationRealtimeEvent>?
      _realtimeSubscription;

  bool _disposed = false;

  bool _joining = false;
  bool _leaving = false;

  GroupCallController({
    required this.conversationId,
    required this.api,
    required this.realtime,
    LiveKitMediaService? liveKit,
  }) : liveKit =
            liveKit ?? LiveKitMediaService() {
    this.liveKit.addListener(
          _forwardMediaChanges,
        );

    _realtimeSubscription =
        realtime.events.listen(
      _onRealtimeEvent,
      onError: (
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint(
          '[GROUP CALL] realtime error: $error',
        );
      },
    );
  }

  GroupCallPhase get phase => _phase;

  CallSessionDto? get call => _call;

  CallSessionDto? get activeDiscoveredCall =>
      _activeDiscoveredCall;

  String? get error => _error;

  bool get isDisposed => _disposed;

  bool get isBusy =>
      _joining ||
      _leaving ||
      {
        GroupCallPhase.checking,
        GroupCallPhase.starting,
        GroupCallPhase.joining,
        GroupCallPhase.leaving,
      }.contains(_phase);

  bool get connected =>
      !_disposed &&
      _phase == GroupCallPhase.connected &&
      liveKit.connected;

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _forwardMediaChanges() {
    _safeNotify();
  }

  Future<CallSessionDto?> checkActiveCall(
    int requestedConversationId,
  ) async {
    if (_disposed) {
      return null;
    }

    if (requestedConversationId !=
        conversationId) {
      throw ArgumentError(
        'GroupCallController belongs to conversation '
        '$conversationId, not $requestedConversationId.',
      );
    }

    _phase = GroupCallPhase.checking;
    _error = null;
    _safeNotify();

    try {
      final result =
          await api.getActiveGroupCall(
        conversationId,
      );

      if (_disposed) {
        return null;
      }

      _activeDiscoveredCall =
          result.active &&
                  result.call != null &&
                  result.call!.isActive
              ? result.call
              : null;

      if (_call != null &&
          liveKit.connected) {
        _phase = GroupCallPhase.connected;
      } else {
        _phase = GroupCallPhase.idle;
      }

      _safeNotify();

      return _activeDiscoveredCall;
    } catch (e) {
      if (_disposed) {
        return null;
      }

      _error = e.toString();

      if (_call != null &&
          liveKit.connected) {
        _phase = GroupCallPhase.connected;
      } else {
        _phase = GroupCallPhase.idle;
      }

      _safeNotify();

      return null;
    }
  }

  Future<void> startGroupCall({
    required int conversationId,
    required bool video,
  }) async {
    if (_disposed) {
      return;
    }

    if (conversationId !=
        this.conversationId) {
      throw ArgumentError(
        'Wrong conversation for this call controller.',
      );
    }

    if (_joining ||
        _phase == GroupCallPhase.connected) {
      return;
    }

    _phase = GroupCallPhase.starting;
    _error = null;
    _safeNotify();

    try {
      final started =
          await api.startGroupCall(
        conversationId: conversationId,
        isVideo: video,
      );

      if (_disposed) {
        return;
      }

      _call = started;
      _activeDiscoveredCall = started;

      await _joinCurrentCall();
    } on CallApiException catch (e) {
      if (_disposed) {
        return;
      }

      // Existing active group call.
      if (e.statusCode == 409) {
        final active =
            await api.getActiveGroupCall(
          conversationId,
        );

        if (_disposed) {
          return;
        }

        if (active.active &&
            active.call != null &&
            active.call!.isActive) {
          _call = active.call;
          _activeDiscoveredCall =
              active.call;

          await _joinCurrentCall();

          return;
        }
      }

      _phase = GroupCallPhase.error;
      _error = e.message;
      _safeNotify();

      rethrow;
    } catch (e) {
      if (_disposed) {
        return;
      }

      _phase = GroupCallPhase.error;
      _error = e.toString();
      _safeNotify();

      rethrow;
    }
  }

  Future<void> joinExistingCall(
    CallSessionDto call,
  ) async {
    if (_disposed) {
      return;
    }

    if (_joining ||
        connected) {
      return;
    }

    if (call.conversationId !=
        conversationId) {
      throw ArgumentError(
        'Call belongs to another conversation.',
      );
    }

    if (!call.isGroup) {
      throw ArgumentError(
        'Call is not a group call.',
      );
    }

    if (!call.isActive) {
      throw StateError(
        'Group call is no longer active.',
      );
    }

    _call = call;
    _activeDiscoveredCall = call;
    _error = null;

    await _joinCurrentCall();
  }

  Future<void> _joinCurrentCall() async {
    if (_disposed || _joining) {
      return;
    }

    final selectedCall = _call;

    if (selectedCall == null) {
      throw StateError(
        'No call selected.',
      );
    }

    _joining = true;
    _phase = GroupCallPhase.joining;
    _error = null;
    _safeNotify();

    try {
      /*
       * Backend LiveKitTokenView is expected to mark
       * this participant as JOINED.
       *
       * Therefore we don't call "accept" separately.
       */
      final credentials =
          await api.getLiveKitToken(
        selectedCall.callId,
      );

      if (_disposed) {
        return;
      }

      await liveKit.connect(
        credentials: credentials,
        startWithVideo:
            selectedCall.isVideo,
      );

      if (_disposed) {
        await liveKit.disconnect();
        return;
      }

      _call = selectedCall.copyWith(
        status:
            selectedCall.status ==
                    CallSessionStatus.ringing
                ? CallSessionStatus.accepted
                : selectedCall.status,
        roomName: credentials.roomName,
        myParticipantStatus: 'joined',
      );

      _activeDiscoveredCall = _call;

      _phase = GroupCallPhase.connected;
      _error = null;

      _safeNotify();
    } on CallApiException catch (e) {
      if (!_disposed) {
        _phase = GroupCallPhase.error;
        _error = e.message;
        _safeNotify();
      }

      rethrow;
    } catch (e) {
      if (!_disposed) {
        _phase = GroupCallPhase.error;
        _error = e.toString();
        _safeNotify();
      }

      rethrow;
    } finally {
      _joining = false;
    }
  }

  Future<void> declineIncoming(
    CallSessionDto call,
  ) async {
    if (_disposed) {
      return;
    }

    if (call.conversationId !=
        conversationId) {
      return;
    }

    try {
      await api.updateStatus(
        callId: call.callId,
        action: 'reject',
      );
    } finally {
      if (_call?.callId ==
          call.callId) {
        _call = null;
      }

      if (_activeDiscoveredCall?.callId ==
          call.callId) {
        _activeDiscoveredCall = null;
      }

      _error = null;
      _phase = GroupCallPhase.idle;

      _safeNotify();
    }
  }

  /// Group red button means:
  ///
  /// LEAVE THIS PARTICIPANT.
  ///
  /// It must NOT automatically end the entire
  /// group call while other members remain joined.
  Future<void> leave() async {
    if (_disposed || _leaving) {
      return;
    }

    _leaving = true;

    final selectedCall = _call;

    _phase = GroupCallPhase.leaving;
    _error = null;
    _safeNotify();

    Object? requestError;

    try {
      if (selectedCall != null) {
        try {
          await api.updateStatus(
            callId: selectedCall.callId,
            action: 'leave',
          );
        } catch (e) {
          requestError = e;
        }
      }

      await liveKit.disconnect();

      if (_disposed) {
        return;
      }

      _call = null;

      /*
       * Other participants may still be inside.
       * Refresh server state instead of assuming
       * the whole call ended.
       */
      try {
        final active =
            await api.getActiveGroupCall(
          conversationId,
        );

        if (!_disposed) {
          _activeDiscoveredCall =
              active.active &&
                      active.call != null &&
                      active.call!.isActive
                  ? active.call
                  : null;
        }
      } catch (e) {
        debugPrint(
          '[GROUP CALL] active-call refresh '
          'after leave failed: $e',
        );
      }

      if (!_disposed) {
        _phase = GroupCallPhase.idle;
        _safeNotify();
      }

      if (requestError != null) {
        throw requestError;
      }
    } finally {
      _leaving = false;
    }
  }

  void _onRealtimeEvent(
    ConversationRealtimeEvent event,
  ) {
    if (_disposed) {
      return;
    }

    final data = event.data;

    final eventConversationId =
        int.tryParse(
          (data['conversation_id'] ?? '')
              .toString(),
        ) ??
        0;

    if (eventConversationId != 0 &&
        eventConversationId !=
            conversationId) {
      return;
    }

    switch (event.type) {
      case 'incoming_call':
        _handleIncomingRealtime(data);
        break;

      case 'call_status_updated':
        _handleStatusRealtime(data);
        break;

      case 'call_participant_joined':
      case 'call_participant_left':
        unawaited(
          _refreshActiveCallSilently(),
        );
        break;

      default:
        break;
    }
  }

  void _handleIncomingRealtime(
    Map<String, dynamic> data,
  ) {
    try {
      final incoming =
          CallSessionDto.fromJson(data);

      if (!incoming.isGroup ||
          !incoming.isActive ||
          incoming.conversationId !=
              conversationId) {
        return;
      }

      _activeDiscoveredCall =
          incoming;

      _safeNotify();
    } catch (e) {
      debugPrint(
        '[GROUP CALL] incoming realtime '
        'parse error: $e',
      );
    }
  }

  void _handleStatusRealtime(
    Map<String, dynamic> data,
  ) {
    final eventCallId =
        int.tryParse(
          (data['call_id'] ??
                  data['id'] ??
                  '')
              .toString(),
        ) ??
        0;

    final status =
        CallSessionStatus.fromJson(
      data['status'],
    );

    /*
     * Ignore events belonging to another call
     * in the same conversation.
     */
    if (eventCallId > 0) {
      final knownCallId =
          _call?.callId ??
          _activeDiscoveredCall?.callId;

      if (knownCallId != null &&
          knownCallId > 0 &&
          knownCallId != eventCallId) {
        return;
      }
    }

    if (_activeDiscoveredCall != null) {
      _activeDiscoveredCall =
          _activeDiscoveredCall!.copyWith(
        status: status,
      );
    }

    if (_call != null) {
      _call = _call!.copyWith(
        status: status,
      );
    }

    if (status.isTerminal) {
      _activeDiscoveredCall = null;

      if (_call != null ||
          liveKit.connected) {
        unawaited(
          _endMediaLocally(),
        );
      } else {
        _phase = GroupCallPhase.ended;
        _safeNotify();
      }

      return;
    }

    _safeNotify();
  }

  Future<void> _refreshActiveCallSilently() async {
    if (_disposed) {
      return;
    }

    try {
      final result =
          await api.getActiveGroupCall(
        conversationId,
      );

      if (_disposed) {
        return;
      }

      _activeDiscoveredCall =
          result.active &&
                  result.call != null &&
                  result.call!.isActive
              ? result.call
              : null;

      _safeNotify();
    } catch (e) {
      debugPrint(
        '[GROUP CALL] silent active-call '
        'refresh failed: $e',
      );
    }
  }

  Future<void> _endMediaLocally() async {
    try {
      await liveKit.disconnect();
    } catch (_) {}

    if (_disposed) {
      return;
    }

    _call = null;
    _activeDiscoveredCall = null;

    _phase = GroupCallPhase.ended;
    _error = null;

    _safeNotify();
  }

  Future<void> toggleMicrophone() async {
    if (_disposed) return;
    await liveKit.toggleMicrophone();
  }

  Future<void> toggleCamera() async {
    if (_disposed) return;
    await liveKit.toggleCamera();
  }

  Future<void> switchCamera() async {
    if (_disposed) return;
    await liveKit.switchCamera();
  }

  Future<void> toggleSpeaker() async {
    if (_disposed) return;
    await liveKit.toggleSpeaker();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    liveKit.removeListener(
      _forwardMediaChanges,
    );

    final subscription =
        _realtimeSubscription;

    _realtimeSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    liveKit.dispose();

    super.dispose();
  }
}