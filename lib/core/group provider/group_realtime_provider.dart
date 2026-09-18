import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hiddenly/core/chat/chat_provider.dart';
import 'package:hiddenly/core/group%20provider/group_call_provider.dart';
import 'package:hiddenly/core/group%20provider/group_chat_provider.dart';
import 'package:hiddenly/group/group_models.dart';

/// Routes the authenticated USER-level websocket / FCM events to the correct
/// state owner. This provider does not create a second websocket connection.
/// Feed your existing global socket events into [handleUserEvent].
class GroupRealtimeProvider extends ChangeNotifier {
  GroupRealtimeProvider({
    required ChatProvider chatProvider,
    required GroupChatProvider groupChatProvider,
    required GroupCallProvider groupCallProvider,
  })  : _chatProvider = chatProvider,
        _groupChatProvider = groupChatProvider,
        _groupCallProvider = groupCallProvider;

  ChatProvider _chatProvider;
  GroupChatProvider _groupChatProvider;
  GroupCallProvider _groupCallProvider;

  Timer? _conversationRefreshDebounce;
  Map<String, dynamic>? _lastEvent;

  Map<String, dynamic>? get lastEvent => _lastEvent == null
      ? null
      : Map<String, dynamic>.unmodifiable(_lastEvent!);

  void rebind({
    required ChatProvider chatProvider,
    required GroupChatProvider groupChatProvider,
    required GroupCallProvider groupCallProvider,
  }) {
    _chatProvider = chatProvider;
    _groupChatProvider = groupChatProvider;
    _groupCallProvider = groupCallProvider;
  }

  Future<void> handleUserEvent(Map<String, dynamic> event) async {
    _lastEvent = Map<String, dynamic>.from(event);

    final eventName = (event['event'] ?? event['type'] ?? '').toString();
    final rawPayload = event['payload'];
    final payload = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : Map<String, dynamic>.from(event);

    switch (eventName) {
      case 'group_created':
      case 'group_updated':
      case 'group_members_changed':
        await _groupChatProvider.handleRealtimeEvent(
          eventName: eventName,
          payload: payload,
        );
        _scheduleConversationRefresh();
        break;

      case 'group_call_invite':
        final call = _readCall(payload);
        if (call != null) {
          _groupCallProvider.handleInvite(call);
          await _groupCallProvider.refreshActiveCall(
            call.conversationId,
            notify: false,
          );
        }
        break;

      case 'group_call_updated':
        final call = _readCall(payload);
        if (call != null) {
          _groupCallProvider.handleCallUpdated(call);
        }
        break;
    }

    notifyListeners();
  }

  /// Call this from ChatProvider's normal conversation-socket callback before
  /// or after ChatProvider handles the message. GroupChatProvider only consumes
  /// typing metadata; ChatProvider continues to own actual messages.
  void handleConversationEvent({
    required int conversationId,
    required Map<String, dynamic> event,
  }) {
    _groupChatProvider.handleConversationSocketEvent(
      conversationId: conversationId.toString(),
      event: event,
    );
  }

  GroupCallSessionInfo? _readCall(Map<String, dynamic> payload) {
    final raw = payload['call'];
    if (raw is! Map) return null;
    return GroupCallSessionInfo.fromJson(Map<String, dynamic>.from(raw));
  }

  void _scheduleConversationRefresh() {
    _conversationRefreshDebounce?.cancel();
    _conversationRefreshDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_chatProvider.loadConversations()),
    );
  }

  @override
  void dispose() {
    _conversationRefreshDebounce?.cancel();
    super.dispose();
  }
}
