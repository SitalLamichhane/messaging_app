import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'call_api_service.dart';

class CallSocketEvent {
  final String type;
  final Map<String, dynamic> data;

  const CallSocketEvent({
    required this.type,
    required this.data,
  });
}

class CallSocketService {
  final String wsBaseUrl;
  final AccessTokenGetter accessTokenGetter;

  /// Your backend can authenticate WebSocket differently.
  /// If your existing one-to-one socket already works, reuse its URL/auth logic.
  final bool tokenInQuery;
  final String tokenQueryKey;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final _events = StreamController<CallSocketEvent>.broadcast();

  Timer? _retryTimer;
  int _conversationId = 0;
  bool _closedByUser = false;
  int _retry = 0;

  CallSocketService({
    required this.wsBaseUrl,
    required this.accessTokenGetter,
    this.tokenInQuery = true,
    this.tokenQueryKey = 'token',
  });

  Stream<CallSocketEvent> get events => _events.stream;

  Future<void> connect(int conversationId) async {
    if (_conversationId == conversationId && _channel != null) {
      return;
    }

    await disconnect();
    _closedByUser = false;
    _conversationId = conversationId;
    await _open();
  }

  Future<void> _open() async {
    if (_conversationId <= 0 || _closedByUser) return;

    final token = await accessTokenGetter();
    final root = wsBaseUrl.endsWith('/')
        ? wsBaseUrl.substring(0, wsBaseUrl.length - 1)
        : wsBaseUrl;

    var uri = Uri.parse('$root/ws/chat/$_conversationId/');

    if (tokenInQuery && token != null && token.isNotEmpty) {
      final query = Map<String, String>.from(uri.queryParameters);
      query[tokenQueryKey] = token;
      uri = uri.replace(queryParameters: query);
    }

    try {
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;

      _channel = channel;
      _retry = 0;

      _subscription = channel.stream.listen(
        _onRawMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onRawMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());

      if (decoded is! Map) return;
      final root = Map<String, dynamic>.from(decoded);

      // Django Channels consumer may send either:
      // {"type":"call_event","data":{...}}
      // or directly {...call event payload...}
      final Map<String, dynamic> payload =
          root['data'] is Map
              ? Map<String, dynamic>.from(root['data'] as Map)
              : root;

      final type =
          (payload['type'] ?? root['type'] ?? '').toString();

      if (type.isEmpty) return;

      _events.add(
        CallSocketEvent(
          type: type,
          data: payload,
        ),
      );
    } catch (_) {
      // Ignore non-JSON or unrelated chat messages.
    }
  }

  void _scheduleReconnect() {
    if (_closedByUser || _conversationId <= 0) return;

    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    _retryTimer?.cancel();

    final seconds = _retry < 5 ? (1 << _retry) : 30;
    _retry = (_retry + 1).clamp(0, 5);

    _retryTimer = Timer(
      Duration(seconds: seconds),
      _open,
    );
  }

  Future<void> disconnect() async {
    _closedByUser = true;
    _retryTimer?.cancel();
    _retryTimer = null;

    await _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close();
    _channel = null;

    _conversationId = 0;
    _retry = 0;
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}
