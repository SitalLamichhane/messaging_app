import 'package:flutter/material.dart';
import 'package:hiddenly/group/group_call_invite_screen.dart';
import 'package:hiddenly/group/group_models.dart';

/// Call this from the same global socket/FCM handler you already use for
/// one-to-one calls.
///
/// Expected websocket envelope from backend/events.py:
/// {
///   "event": "group_call_invite",
///   "payload": {"call": {...}}
/// }
class GroupEventRouter {
  GroupEventRouter._();

  static Future<void> handle({
    required BuildContext context,
    required Map<String, dynamic> event,
    required String Function(String conversationId) resolveGroupName,
  }) async {
    final eventName = (event['event'] ?? event['type'] ?? '').toString();
    final payloadRaw = event['payload'];
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : Map<String, dynamic>.from(event);

    if (eventName != 'group_call_invite') return;

    final rawCall = payload['call'];
    if (rawCall is! Map) return;
    final call = GroupCallSessionInfo.fromJson(Map<String, dynamic>.from(rawCall));
    if (!call.isActive) return;

    final groupName = resolveGroupName(call.conversationId);

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GroupCallInviteScreen(
          call: call,
          groupName: groupName.isEmpty ? 'Group call' : groupName,
        ),
      ),
    );
  }
}
