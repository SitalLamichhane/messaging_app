import 'dart:async';

import 'package:hiddenly/groupCall/domain/application/group_call_controller.dart';
import 'package:hiddenly/realtime/realtime_service.dart';

class IncomingGroupCallBundle {
  final ConversationRealtimeService realtime;
  final GroupCallController controller;

  bool _disposed = false;

  IncomingGroupCallBundle({
    required this.realtime,
    required this.controller,
  });

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    controller.dispose();

    await realtime.dispose();
  }
}