import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hiddenly/groupCall/domain/call_models.dart';
import 'package:hiddenly/groupCall/domain/infrastructure/call_push_service.dart';
import 'package:hiddenly/groupCall/domain/integration/incoming_group_call_bundle.dart';
import 'package:hiddenly/groupCall/domain/presentation/screens/incoming_group_call_screen.dart';

class CallPushRouter {
  final GlobalKey<NavigatorState>
      navigatorKey;

  final CallPushService pushService;

  final Future<IncomingGroupCallBundle>
          Function(int conversationId)
      controllerFactory;

  StreamSubscription<IncomingCallPayload>?
      _sub;

  IncomingGroupCallBundle? _activeBundle;

  int? _displayedCallId;

  bool _initialized = false;
  bool _disposed = false;

  CallPushRouter({
    required this.navigatorKey,
    required this.pushService,
    required this.controllerFactory,
  });

  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }

    _initialized = true;

    await pushService.initialize();

    _sub =
        pushService.incomingCalls.listen(
      _showIncoming,
      onError: (
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint(
          '[GROUP CALL PUSH ROUTER] '
          'stream error: $error',
        );

        debugPrint(
          stackTrace.toString(),
        );
      },
    );

    debugPrint(
      '[GROUP CALL PUSH ROUTER] initialized',
    );
  }

  Future<void> _showIncoming(
    IncomingCallPayload payload,
  ) async {
    if (_disposed) {
      return;
    }

    if (!payload.isGroupCall ||
        !payload.isValid) {
      return;
    }

    if (_displayedCallId ==
        payload.callId) {
      debugPrint(
        '[GROUP CALL PUSH ROUTER] '
        'duplicate screen ignored '
        '${payload.callId}',
      );

      return;
    }

    /*
     * Don't stack multiple incoming group-call
     * screens over each other.
     */
    if (_activeBundle != null) {
      debugPrint(
        '[GROUP CALL PUSH ROUTER] '
        'another group call UI is active',
      );

      return;
    }

    NavigatorState? navigator;

    for (int attempt = 0;
        attempt < 20;
        attempt++) {
      navigator =
          navigatorKey.currentState;

      if (navigator != null &&
          navigator.mounted) {
        break;
      }

      await Future<void>.delayed(
        const Duration(
          milliseconds: 100,
        ),
      );
    }

    if (_disposed) {
      return;
    }

    if (navigator == null ||
        !navigator.mounted) {
      debugPrint(
        '[GROUP CALL PUSH ROUTER] '
        'navigator not ready',
      );

      return;
    }

    IncomingGroupCallBundle? bundle;

    try {
      bundle =
          await controllerFactory(
        payload.conversationId,
      );

      if (_disposed) {
        await bundle.dispose();
        return;
      }

      _activeBundle = bundle;
      _displayedCallId =
          payload.callId;

      /*
       * Connect the conversation websocket so
       * this controller receives status changes
       * even though ConversationChatScreen
       * isn't currently open.
       */
      await bundle.realtime.connect(
        payload.conversationId,
      );

      if (_disposed) {
        return;
      }

      await navigator.push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) {
            return IncomingGroupCallScreen(
              payload: payload,
              controller:
                  bundle!.controller,
            );
          },
        ),
      );
    } catch (e, stackTrace) {
      debugPrint(
        '[GROUP CALL PUSH ROUTER] '
        'open error: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );
    } finally {
      if (bundle != null) {
        await bundle.dispose();
      }

      if (identical(
        _activeBundle,
        bundle,
      )) {
        _activeBundle = null;
      }

      if (_displayedCallId ==
          payload.callId) {
        _displayedCallId = null;
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _initialized = false;

    await _sub?.cancel();
    _sub = null;

    final bundle =
        _activeBundle;

    _activeBundle = null;
    _displayedCallId = null;

    if (bundle != null) {
      await bundle.dispose();
    }

    await pushService.dispose();
  }
}