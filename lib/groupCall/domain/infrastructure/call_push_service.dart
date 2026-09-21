import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddenly/groupCall/domain/call_models.dart';

class CallPushService {
  final StreamController<IncomingCallPayload> _incoming =
      StreamController<IncomingCallPayload>.broadcast();

  final Map<int, DateTime> _recentCalls = <int, DateTime>{};

  static const Duration _duplicateWindow =
      Duration(seconds: 5);

  Stream<IncomingCallPayload> get incomingCalls =>
      _incoming.stream;

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  bool _initialized = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }

    _initialized = true;

    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      await _foregroundSub?.cancel();
      await _openedSub?.cancel();

      _foregroundSub =
          FirebaseMessaging.onMessage.listen(
        _handle,
        onError: (
          Object error,
          StackTrace stackTrace,
        ) {
          debugPrint(
            '[GROUP CALL PUSH] foreground error: $error',
          );
          debugPrint(stackTrace.toString());
        },
      );

      _openedSub =
          FirebaseMessaging.onMessageOpenedApp.listen(
        _handle,
        onError: (
          Object error,
          StackTrace stackTrace,
        ) {
          debugPrint(
            '[GROUP CALL PUSH] opened-app error: $error',
          );
          debugPrint(stackTrace.toString());
        },
      );

      final initial =
          await FirebaseMessaging.instance.getInitialMessage();

      if (initial != null) {
        _handle(initial);
      }

      debugPrint(
        '[GROUP CALL PUSH] initialized',
      );
    } catch (e, stackTrace) {
      _initialized = false;

      debugPrint(
        '[GROUP CALL PUSH] initialization error: $e',
      );
      debugPrint(stackTrace.toString());

      rethrow;
    }
  }

  bool _isDuplicate(int callId) {
    final now = DateTime.now();

    _recentCalls.removeWhere(
      (_, time) =>
          now.difference(time) >
          _duplicateWindow,
    );

    final previous = _recentCalls[callId];

    if (previous != null &&
        now.difference(previous) <=
            _duplicateWindow) {
      return true;
    }

    _recentCalls[callId] = now;

    return false;
  }

  void _handle(RemoteMessage message) {
    if (_disposed) {
      return;
    }

    try {
      final data =
          Map<String, dynamic>.from(
        message.data,
      );

      final type =
          (data['type'] ?? '')
              .toString()
              .trim()
              .toLowerCase();

      if (type != 'incoming_call') {
        return;
      }

      final payload =
          IncomingCallPayload.fromMap(data);

      // IMPORTANT:
      // Private calls continue through the existing
      // NotificationService + CallKit architecture.
      if (!payload.isGroupCall) {
        return;
      }

      if (!payload.isValid) {
        debugPrint(
          '[GROUP CALL PUSH] invalid payload: $data',
        );
        return;
      }

      if (_isDuplicate(payload.callId)) {
        debugPrint(
          '[GROUP CALL PUSH] duplicate ignored '
          'callId=${payload.callId}',
        );
        return;
      }

      debugPrint(
        '[GROUP CALL PUSH] incoming group call '
        'callId=${payload.callId} '
        'conversationId=${payload.conversationId}',
      );

      if (!_incoming.isClosed) {
        _incoming.add(payload);
      }
    } catch (e, stackTrace) {
      debugPrint(
        '[GROUP CALL PUSH] payload error: $e',
      );
      debugPrint(stackTrace.toString());
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _initialized = false;

    await _foregroundSub?.cancel();
    await _openedSub?.cancel();

    _foregroundSub = null;
    _openedSub = null;

    _recentCalls.clear();

    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}