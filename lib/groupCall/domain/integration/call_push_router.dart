import 'dart:async';

import 'package:flutter/material.dart';

import '../application/group_call_controller.dart';
import '../domain/call_models.dart';
import '../infrastructure/call_push_service.dart';
import '../presentation/screens/incoming_group_call_screen.dart';

class CallPushRouter {
  final GlobalKey<NavigatorState> navigatorKey;
  final CallPushService pushService;
  final GroupCallController Function() controllerFactory;

  StreamSubscription<IncomingCallPayload>? _sub;

  CallPushRouter({
    required this.navigatorKey,
    required this.pushService,
    required this.controllerFactory,
  });

  Future<void> initialize() async {
    await pushService.initialize();

    _sub = pushService.incomingCalls.listen(
      _showIncoming,
    );
  }

  void _showIncoming(IncomingCallPayload payload) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final controller = controllerFactory();

    navigator.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingGroupCallScreen(
          payload: payload,
          controller: controller,
        ),
      ),
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await pushService.dispose();
  }
}
