// core/chat/chat_socket_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/core/config/app_config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ChatSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  bool _connected = false;
  bool _connecting = false;

  int? _conversationId;

  bool get isConnected => _connected;

  Future<void> connect({
    required int conversationId,
    required FutureOr<void> Function(Map<String, dynamic> data) onMessage,
    required void Function(Object error) onError,
    required void Function() onDisconnected,
  }) async {
    if (_connecting) return;

    if (_connected && _conversationId == conversationId && _channel != null) {
      debugPrint('CHAT WS ALREADY CONNECTED');
      return;
    }

    _connecting = true;

    try {
      await disconnect();

      _conversationId = conversationId;

      final token = await ApiClient.storage.read(key: 'access');

      if (token == null || token.trim().isEmpty) {
        throw Exception('Access token missing');
      }

      final baseWsUrl = AppConfig.wsBaseUrl;

      final url =
          '$baseWsUrl/ws/chat/$conversationId/?token=${Uri.encodeComponent(token.trim())}';

      debugPrint('CHAT WS CONNECTING: $url');

      _channel = WebSocketChannel.connect(Uri.parse(url));
      _connected = true;

      _subscription = _channel!.stream.listen(
        (message) async {
          debugPrint('CHAT WS RAW: $message');

          try {
            final decoded = jsonDecode(message.toString());

            if (decoded is! Map) {
              debugPrint('CHAT WS INVALID MESSAGE');
              return;
            }

            await onMessage(Map<String, dynamic>.from(decoded));
          } catch (e) {
            debugPrint('CHAT WS PARSE ERROR: $e');
          }
        },
        onError: (error) {
          debugPrint('CHAT WS ERROR: $error');
          _connected = false;
          onError(error);
        },
        onDone: () {
          debugPrint('CHAT WS CLOSED');
          _connected = false;
          _channel = null;
          _subscription = null;
          onDisconnected();
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('CHAT WS CONNECT ERROR: $e');
      _connected = false;
      _channel = null;
      onError(e);
    } finally {
      _connecting = false;
    }
  }

  void sendTyping({
    required int senderId,
    required bool isTyping,
  }) {
    send({
      'type': 'typing',
      'action': 'typing',
      'sender_id': senderId,
      'is_typing': isTyping,
    });
  }

  void send(Map<String, dynamic> data) {
    if (_channel == null || !_connected) {
      debugPrint('CHAT WS NOT CONNECTED');
      return;
    }

    try {
      final encoded = jsonEncode(data);
      debugPrint('CHAT WS SEND: $encoded');
      _channel!.sink.add(encoded);
    } catch (e) {
      debugPrint('CHAT WS SEND ERROR: $e');
      _connected = false;
    }
  }

  Future<void> disconnect() async {
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
    _conversationId = null;

    debugPrint('CHAT WS DISCONNECTED');
  }
}