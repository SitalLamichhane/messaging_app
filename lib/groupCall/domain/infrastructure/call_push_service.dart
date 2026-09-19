import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../domain/call_models.dart';

/// Register this in main():
///
/// FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
///
/// IMPORTANT:
/// This background callback cannot navigate or paint a Flutter screen.
/// Reuse your existing one-to-one native incoming-call/CallKit layer for
/// a true ringing screen while the app is backgrounded/killed.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp();

  // Your existing native/full-screen call notification handler can inspect:
  // message.data['type'] == 'incoming_call'
  //
  // Do not try to use Navigator from this isolate.
}

class CallPushService {
  final _incoming =
      StreamController<IncomingCallPayload>.broadcast();

  Stream<IncomingCallPayload> get incomingCalls =>
      _incoming.stream;

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  Future<void> initialize() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    _foregroundSub = FirebaseMessaging.onMessage.listen(
      _handle,
    );

    _openedSub =
        FirebaseMessaging.onMessageOpenedApp.listen(_handle);

    final initial =
        await FirebaseMessaging.instance.getInitialMessage();

    if (initial != null) {
      _handle(initial);
    }
  }

  void _handle(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);

    if ((data['type'] ?? '').toString() != 'incoming_call') {
      return;
    }

    // Your backend serializes is_group_call.
    final isGroup = data['is_group_call'] == true ||
        data['is_group_call']?.toString().toLowerCase() ==
            'true';

    if (!isGroup) return;

    _incoming.add(
      IncomingCallPayload.fromMap(data),
    );
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    await _incoming.close();
  }
}
