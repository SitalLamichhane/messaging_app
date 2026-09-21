import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef ConversationSocketUriBuilder = Future<Uri> Function(
  int conversationId,
);

class ConversationRealtimeEvent {
  final String type;
  final Map<String, dynamic> data;

  const ConversationRealtimeEvent({
    required this.type,
    required this.data,
  });

  @override
  String toString() {
    return 'ConversationRealtimeEvent($type, $data)';
  }
}

/// Owns ONE websocket for one open conversation.
///
/// Both:
/// - ChatRoomController
/// - GroupCallController
///
/// listen to the same broadcast event stream.
///
/// This service should be owned/disposed by ConversationChatScreen,
/// NOT by the individual controllers.
class ConversationRealtimeService {
  final ConversationSocketUriBuilder uriBuilder;

  final StreamController<ConversationRealtimeEvent> _events =
      StreamController<ConversationRealtimeEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;

  int? _conversationId;

  int _retryAttempt = 0;
  int _connectionGeneration = 0;

  bool _manualClose = false;
  bool _connecting = false;
  bool _socketReady = false;
  bool _disposed = false;

  ConversationRealtimeService({
    required this.uriBuilder,
  });

  Stream<ConversationRealtimeEvent> get events => _events.stream;

  bool get connected =>
      !_disposed &&
      _socketReady &&
      _channel != null;

  bool get connecting => _connecting;

  int? get conversationId => _conversationId;

  Future<void> connect(int conversationId) async {
    if (_disposed) {
      throw StateError(
        'ConversationRealtimeService has been disposed.',
      );
    }

    if (_conversationId == conversationId &&
        (connected || _connecting)) {
      return;
    }

    await _closeCurrentConnection(
      clearConversation: true,
    );

    if (_disposed) return;

    _conversationId = conversationId;
    _manualClose = false;
    _retryAttempt = 0;

    _connectionGeneration++;

    await _open(
      generation: _connectionGeneration,
    );
  }

  Future<void> _open({
    required int generation,
  }) async {
    final conversationId = _conversationId;

    if (_disposed ||
        conversationId == null ||
        _manualClose ||
        _connecting ||
        generation != _connectionGeneration) {
      return;
    }

    _connecting = true;

    WebSocketChannel? newChannel;

    try {
      final uri =
          await uriBuilder(conversationId);

      if (_disposed ||
          _manualClose ||
          generation != _connectionGeneration ||
          _conversationId != conversationId) {
        return;
      }

      debugPrint(
        'CHAT WS CONNECT => $uri',
      );

      newChannel =
          WebSocketChannel.connect(uri);

      await newChannel.ready;

      if (_disposed ||
          _manualClose ||
          generation != _connectionGeneration ||
          _conversationId != conversationId) {
        try {
          await newChannel.sink.close();
        } catch (_) {}

        return;
      }

      await _subscription?.cancel();
      _subscription = null;

      final activeChannel = newChannel;

      _channel = activeChannel;
      _socketReady = true;
      _retryAttempt = 0;

      _reconnectTimer?.cancel();
      _reconnectTimer = null;

      _subscription =
          activeChannel.stream.listen(
        _onRawMessage,
        onError: (
          Object error,
          StackTrace stackTrace,
        ) {
          debugPrint(
            'CHAT WS ERROR => $error',
          );

          _handleSocketClosed(
            channel: activeChannel,
            generation: generation,
          );
        },
        onDone: () {
          debugPrint(
            'CHAT WS CLOSED',
          );

          _handleSocketClosed(
            channel: activeChannel,
            generation: generation,
          );
        },
        cancelOnError: false,
      );

      debugPrint(
        'CHAT WS CONNECTED => conversation=$conversationId',
      );
    } catch (e) {
      debugPrint(
        'CHAT WS CONNECT ERROR => $e',
      );

      if (newChannel != null &&
          newChannel != _channel) {
        try {
          await newChannel.sink.close();
        } catch (_) {}
      }

      _scheduleReconnect(
        generation: generation,
      );
    } finally {
      if (generation ==
          _connectionGeneration) {
        _connecting = false;
      }
    }
  }

  void _handleSocketClosed({
    required WebSocketChannel channel,
    required int generation,
  }) {
    if (_disposed ||
        generation != _connectionGeneration) {
      return;
    }

    // Ignore callbacks from an old socket.
    if (!identical(_channel, channel)) {
      return;
    }

    _socketReady = false;
    _channel = null;

    _subscription = null;

    _scheduleReconnect(
      generation: generation,
    );
  }

  void _scheduleReconnect({
    required int generation,
  }) {
    if (_disposed ||
        _manualClose ||
        _conversationId == null ||
        generation != _connectionGeneration) {
      return;
    }

    // A reconnect is already waiting.
    if (_reconnectTimer?.isActive == true) {
      return;
    }

    _socketReady = false;
    _channel = null;

    final seconds =
        _retryAttempt < 5
            ? (1 << _retryAttempt)
            : 30;

    if (_retryAttempt < 5) {
      _retryAttempt++;
    }

    debugPrint(
      'CHAT WS RECONNECT IN ${seconds}s',
    );

    _reconnectTimer = Timer(
      Duration(seconds: seconds),
      () {
        _reconnectTimer = null;

        if (_disposed ||
            _manualClose ||
            generation !=
                _connectionGeneration) {
          return;
        }

        unawaited(
          _open(
            generation: generation,
          ),
        );
      },
    );
  }

  void _onRawMessage(dynamic raw) {
    if (_disposed || _events.isClosed) {
      return;
    }

    try {
      final decoded =
          jsonDecode(raw.toString());

      if (decoded is! Map) {
        return;
      }

      final root =
          Map<String, dynamic>.from(
        decoded,
      );

      /*
       * Supported call shape:
       *
       * {
       *   "type": "call_event",
       *   "data": {
       *     "type": "incoming_call",
       *     ...
       *   }
       * }
       */
      if (root['type']?.toString() ==
              'call_event' &&
          root['data'] is Map) {
        final data =
            Map<String, dynamic>.from(
          root['data'] as Map,
        );

        final nestedType =
            (data['type'] ?? 'call_event')
                .toString();

        if (nestedType.isEmpty) {
          return;
        }

        _addEvent(
          ConversationRealtimeEvent(
            type: nestedType,
            data: data,
          ),
        );

        return;
      }

      /*
       * Normal shape:
       *
       * {
       *   "type": "chat_message",
       *   ...
       * }
       *
       * or:
       *
       * {
       *   "type": "incoming_call",
       *   ...
       * }
       */
      final type =
          (root['type'] ?? '')
              .toString()
              .trim();

      if (type.isEmpty) {
        return;
      }

      _addEvent(
        ConversationRealtimeEvent(
          type: type,
          data: root,
        ),
      );
    } catch (e) {
      debugPrint(
        'CHAT WS PARSE ERROR => $e',
      );
    }
  }

  void _addEvent(
    ConversationRealtimeEvent event,
  ) {
    if (_disposed ||
        _events.isClosed) {
      return;
    }

    _events.add(event);
  }

  Future<void> sendJson(
    Map<String, dynamic> payload,
  ) async {
    if (_disposed) {
      throw StateError(
        'ConversationRealtimeService has been disposed.',
      );
    }

    final channel = _channel;

    if (!connected ||
        channel == null) {
      throw StateError(
        'Conversation websocket is not connected.',
      );
    }

    channel.sink.add(
      jsonEncode(payload),
    );
  }

  Future<void> disconnect() async {
    if (_disposed) {
      return;
    }

    _manualClose = true;
    _connectionGeneration++;

    await _closeCurrentConnection(
      clearConversation: true,
    );
  }

  Future<void> _closeCurrentConnection({
    required bool clearConversation,
  }) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final subscription =
        _subscription;
    _subscription = null;

    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }

    final channel = _channel;

    _channel = null;
    _socketReady = false;
    _connecting = false;

    if (channel != null) {
      try {
        await channel.sink.close();
      } catch (_) {}
    }

    if (clearConversation) {
      _conversationId = null;
    }

    _retryAttempt = 0;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _manualClose = true;
    _connectionGeneration++;

    await _closeCurrentConnection(
      clearConversation: true,
    );

    if (!_events.isClosed) {
      await _events.close();
    }
  }
}