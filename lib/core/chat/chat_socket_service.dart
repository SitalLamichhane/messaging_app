// lib/core/chat/chat_socket_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ChatSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  bool isConnected = false;
  int? _connectedConversationId;

  Future<void> connect({
    required int conversationId,
    required void Function(Map<String, dynamic> data) onMessage,
    void Function()? onConnected,
    void Function()? onDisconnected,
    void Function(Object error)? onError,
  }) async {
    if (isConnected && _connectedConversationId == conversationId) {
      debugPrint('SOCKET ALREADY CONNECTED TO: $conversationId');
      return;
    }

    disconnect();

    try {
      final token = await ApiClient.storage.read(key: 'access');

      if (token == null || token.trim().isEmpty) {
        debugPrint('SOCKET ERROR: No access token found');
        return;
      }

      final uri = Uri.parse(
        'ws://192.168.1.112:8000/ws/chat/$conversationId/?token=${Uri.encodeComponent(token.trim())}',
      );

      debugPrint('SOCKET CONNECTING: $uri');

      _channel = WebSocketChannel.connect(uri);
      _connectedConversationId = conversationId;
      isConnected = true;

      _subscription = _channel!.stream.listen(
        (event) {
          debugPrint('SOCKET RECEIVED: $event');

          try {
            final decoded = jsonDecode(event.toString());

            if (decoded is Map) {
              onMessage(Map<String, dynamic>.from(decoded));
            }
          } catch (e) {
            debugPrint('SOCKET JSON DECODE ERROR: $e');
          }
        },
        onError: (error) {
          debugPrint('SOCKET ERROR: $error');
          _markDisconnected();
          onError?.call(error);
        },
        onDone: () {
          debugPrint('SOCKET DISCONNECTED');
          _markDisconnected();
          onDisconnected?.call();
        },
        cancelOnError: true,
      );

      onConnected?.call();
    } catch (e) {
      debugPrint('SOCKET CONNECTION FAILED: $e');
      _markDisconnected();
      onError?.call(e);
    }
  }

  void sendTyping({
    required int senderId,
    required bool isTyping,
  }) {
    if (!_canSend) return;

    _channel!.sink.add(
      jsonEncode({
        'type': 'typing',
        'action': 'typing',
        'sender_id': senderId,
        'is_typing': isTyping,
      }),
    );
  }

  void sendSeen({
    required int senderId,
    required String messageId,
  }) {
    if (messageId.trim().isEmpty) return;
    if (!_canSend) return;

    _channel!.sink.add(
      jsonEncode({
        'type': 'seen',
        'action': 'seen',
        'sender_id': senderId,
        'message_id': messageId,
      }),
    );
  }

  bool get _canSend => _channel != null && isConnected;

  void _markDisconnected() {
    isConnected = false;
    _connectedConversationId = null;
  }

  void disconnect() {
    debugPrint('SOCKET DISCONNECT CALLED');

    _subscription?.cancel();
    _subscription = null;

    try {
      _channel?.sink.close();
    } catch (_) {}

    _channel = null;
    _markDisconnected();
  }
}