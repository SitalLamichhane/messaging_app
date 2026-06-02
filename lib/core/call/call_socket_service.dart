import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SocketService {
  static final SocketService instance = SocketService._internal();
  SocketService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final Map<String, Function(dynamic)> _handlers = {};

  bool _connected = false;
  String? _url;

  bool get isConnected => _connected;

  void connect({required String url}) {
    if (_connected && _channel != null && _url == url) {
      debugPrint('CALL WS ALREADY CONNECTED');
      return;
    }

    if (_channel != null) {
      disconnect(clearHandlers: false);
    }

    _url = url;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _connected = true;

      debugPrint('CALL WS CONNECTED: $url');

      _subscription = _channel!.stream.listen(
        (message) {
          debugPrint('========================');
          debugPrint('CALL WS RAW: $message');

          try {
            final data = jsonDecode(message);

            final event = data['event'];

            debugPrint('CALL WS EVENT: $event');
            debugPrint('CALL WS PAYLOAD: ${data['payload']}');

            if (event == null) {
              debugPrint('CALL WS EVENT NULL');
              return;
            }

            final handler = _handlers[event];

            if (handler != null) {
              debugPrint('CALL WS HANDLER FOUND: $event');
              handler(data);
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
        },
      );
    } catch (e) {
      debugPrint('CALL WS CONNECT ERROR: $e');
      _connected = false;
    }
  }

  void emit(
    String event,
    Map<String, dynamic> payload, {
    String? targetUser,
    String? conversationId,
  }) {
    if (_channel == null || !_connected) {
      debugPrint('CALL WS NOT CONNECTED');
      return;
    }

    final data = {
      'event': event,
      'payload': payload,
      if (targetUser != null) 'target_user': targetUser,
      if (conversationId != null) 'conversation_id': conversationId,
    };

    debugPrint('CALL WS SEND: ${jsonEncode(data)}');
    _channel!.sink.add(jsonEncode(data));
  }

  void on(String event, Function(dynamic) handler) {
    _handlers[event] = handler;
  }

  void off(String event) {
    _handlers.remove(event);
  }

  void reconnect() {
    if (_url == null) return;

    disconnect(clearHandlers: false);
    connect(url: _url!);
  }

  void disconnect({bool clearHandlers = true}) {
    _subscription?.cancel();
    _subscription = null;

    _channel?.sink.close();
    _channel = null;

    if (clearHandlers) {
      _handlers.clear();
    }

    _connected = false;

    debugPrint('CALL WS DISCONNECTED');
  }
}