// core/call/call_socket_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class CallSocketEvents {
  static const String callOffer = 'call_offer';
  static const String callAnswer = 'call_answer';
  static const String iceCandidate = 'ice_candidate';

  static const String callReject = 'call_reject';
  static const String callEnd = 'call_end';
  static const String callLeave = 'call_leave';
  static const String callBusy = 'call_busy';
  static const String callTimeout = 'call_timeout';

  // Audio <-> Video switch
  static const String callRenegotiateOffer = 'call_renegotiate_offer';
  static const String callRenegotiateAnswer = 'call_renegotiate_answer';
  static const String callVideoToggle = 'call_video_toggle';
  static const String callVideoUpgradeRejected =
      'call_video_upgrade_rejected';
}

typedef SocketHandler = FutureOr<void> Function(Map<String, dynamic> data);

class SocketService {
  static final SocketService instance = SocketService._internal();

  SocketService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final Map<String, SocketHandler> _handlers = {};

  bool _connected = false;
  bool _connecting = false;
  String? _url;

  bool get isConnected => _connected;

  Future<void> connect({required String url}) async {
    if (_connecting) return;

    if (_connected && _channel != null && _url == url) {
      debugPrint('CALL WS ALREADY CONNECTED');
      return;
    }

    _connecting = true;

    try {
      if (_channel != null) {
        await disconnect(clearHandlers: false);
      }

      _url = url;
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _connected = true;

      debugPrint('CALL WS CONNECTED: $url');

      _subscription = _channel!.stream.listen(
        (message) async {
          debugPrint('========================');
          debugPrint('CALL WS RAW: $message');

          try {
            final decoded = jsonDecode(message);

            if (decoded is! Map) {
              debugPrint('CALL WS INVALID DATA');
              return;
            }

            final data = Map<String, dynamic>.from(decoded);
            final event = data['event']?.toString();

            debugPrint('CALL WS EVENT: $event');
            debugPrint('CALL WS PAYLOAD: ${data['payload']}');

            if (event == null || event.isEmpty) {
              debugPrint('CALL WS EVENT NULL');
              return;
            }

            final handler = _handlers[event];

            if (handler != null) {
              debugPrint('CALL WS HANDLER FOUND: $event');
              await handler(data);
            } else {
              debugPrint('CALL WS NO HANDLER FOR: $event');
            }
          } catch (e) {
            debugPrint('CALL WS PARSE ERROR: $e');
          }

          debugPrint('========================');
        },
        onError: (error) {
          debugPrint('CALL WS ERROR: $error');
          _connected = false;
        },
        onDone: () {
          debugPrint('CALL WS CLOSED');
          _connected = false;
          _channel = null;
          _subscription = null;
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('CALL WS CONNECT ERROR: $e');
      _connected = false;
      _channel = null;
    } finally {
      _connecting = false;
    }
  }

  void emit(
    String event,
    Map<String, dynamic> payload, {
    String? targetUser,
    String? conversationId,
  }) {
    if (_channel == null || !_connected) {
      debugPrint('CALL WS NOT CONNECTED: $event');
      return;
    }

    final data = {
      'event': event,
      'payload': payload,
      if (targetUser != null) 'target_user': targetUser,
      if (conversationId != null) 'conversation_id': conversationId,
    };

    try {
      final encoded = jsonEncode(data);
      debugPrint('CALL WS SEND: $encoded');
      _channel!.sink.add(encoded);
    } catch (e) {
      debugPrint('CALL WS SEND ERROR: $e');
      _connected = false;
    }
  }

  void on(String event, SocketHandler handler) {
    _handlers[event] = handler;
  }

  void off(String event) {
    _handlers.remove(event);
  }

  void clearHandlers() {
    _handlers.clear();
  }

  Future<void> reconnect() async {
    final url = _url;
    if (url == null || url.trim().isEmpty) return;

    await disconnect(clearHandlers: false);
    await connect(url: url);
  }

  Future<void> disconnect({bool clearHandlers = true}) async {
    try {
      await _subscription?.cancel();
    } catch (_) {}

    _subscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _channel = null;
    _connected = false;
    _connecting = false;

    if (clearHandlers) {
      _handlers.clear();
    }

    debugPrint('CALL WS DISCONNECTED');
  }
}