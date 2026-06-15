// lib/core/call/global_call_socket_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef GlobalSocketHandler = FutureOr<void> Function(Map<String, dynamic> data);

class GlobalCallSocketEvents {
  static const String connected = 'global_call_connected';
  static const String incomingCall = 'incoming_call';
  static const String callCancelled = 'call_cancelled';
}

class GlobalCallSocketService {
  GlobalCallSocketService._internal();

  static final GlobalCallSocketService instance =
      GlobalCallSocketService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final Map<String, List<GlobalSocketHandler>> _handlers = {};

  bool _connected = false;
  bool _connecting = false;
  bool _manualDisconnect = false;

  String? _url;
  Completer<void>? _connectCompleter;
  Timer? _reconnectTimer;

  bool get isConnected => _connected;
  bool get isConnecting => _connecting;
  String? get currentUrl => _url;

  String _sanitizeWsUrl(String url) {
    var fixed = url.trim().replaceAll('#', '');

    if (fixed.startsWith('http://')) {
      fixed = fixed.replaceFirst('http://', 'ws://');
    } else if (fixed.startsWith('https://')) {
      fixed = fixed.replaceFirst('https://', 'wss://');
    }

    return fixed;
  }

  Future<void> connect({required String url}) async {
    final fixedUrl = _sanitizeWsUrl(url);

    if (fixedUrl.isEmpty) {
      debugPrint('GLOBAL CALL WS CONNECT ERROR: URL empty');
      return;
    }

    if (_connected && _channel != null && _url == fixedUrl) {
      debugPrint('GLOBAL CALL WS ALREADY CONNECTED: $fixedUrl');
      return;
    }

    if (_connecting && _connectCompleter != null) {
      debugPrint('GLOBAL CALL WS CONNECT ALREADY IN PROGRESS');
      return _connectCompleter!.future;
    }

    _manualDisconnect = false;
    _connecting = true;
    _connectCompleter = Completer<void>();
    _reconnectTimer?.cancel();

    try {
      if (_channel != null || _subscription != null) {
        await disconnect(
          clearHandlers: false,
          forgetUrl: false,
          manual: false,
        );
      }

      _url = fixedUrl;

      debugPrint('');
      debugPrint('################################################');
      debugPrint('### GLOBAL CALL WS CONNECTING');
      debugPrint('################################################');
      debugPrint('url: $fixedUrl');
      debugPrint('################################################');

      final channel = WebSocketChannel.connect(Uri.parse(fixedUrl));
      _channel = channel;

      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (error, stack) {
          debugPrint('GLOBAL CALL WS ERROR: $error');
          debugPrint(stack.toString());

          _connected = false;
          _channel = null;
          _subscription = null;

          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('GLOBAL CALL WS CLOSED');

          _connected = false;
          _channel = null;
          _subscription = null;

          _scheduleReconnect();
        },
        cancelOnError: false,
      );

      try {
        await channel.ready.timeout(const Duration(seconds: 5));
        debugPrint('GLOBAL CALL WS READY OK');
      } catch (e) {
        debugPrint('GLOBAL CALL WS READY FAILED: $e');

        _connected = false;

        try {
          await _subscription?.cancel();
        } catch (_) {}

        _subscription = null;

        try {
          await _channel?.sink.close();
        } catch (_) {}

        _channel = null;

        if (!(_connectCompleter?.isCompleted ?? true)) {
          _connectCompleter?.complete();
        }

        _scheduleReconnect();
        return;
      }

      if (_channel != channel) {
        debugPrint('GLOBAL CALL WS CONNECT ABORTED: channel changed');
        return;
      }

      _connected = true;

      debugPrint('GLOBAL CALL WS CONNECTED/ACTIVE: $fixedUrl');

      if (!(_connectCompleter?.isCompleted ?? true)) {
        _connectCompleter?.complete();
      }
    } catch (e, st) {
      debugPrint('GLOBAL CALL WS CONNECT ERROR: $e');
      debugPrint(st.toString());

      _connected = false;

      try {
        await _subscription?.cancel();
      } catch (_) {}

      _subscription = null;

      try {
        await _channel?.sink.close();
      } catch (_) {}

      _channel = null;

      if (!(_connectCompleter?.isCompleted ?? true)) {
        _connectCompleter?.complete();
      }

      _scheduleReconnect();
    } finally {
      _connecting = false;
      _connectCompleter = null;
    }
  }

  void _scheduleReconnect() {
    debugPrint('GLOBAL CALL WS AUTO RECONNECT DISABLED');
    return;
  }

  Future<void> _handleMessage(dynamic message) async {
    debugPrint('');
    debugPrint('================ GLOBAL CALL WS MESSAGE ================');
    debugPrint('RAW: $message');

    try {
      final decoded = jsonDecode(message.toString());

      if (decoded is! Map) {
        debugPrint('GLOBAL CALL WS INVALID DATA');
        return;
      }

      final rawData = Map<String, dynamic>.from(decoded);

      final event =
          rawData['event']?.toString() ?? rawData['type']?.toString() ?? '';

      if (event.trim().isEmpty) {
        debugPrint('GLOBAL CALL WS EVENT EMPTY');
        return;
      }

      final data = _normalizeData(rawData, event);

      debugPrint('GLOBAL CALL WS EVENT: $event');
      debugPrint('GLOBAL CALL WS DATA: $data');
      debugPrint('GLOBAL CALL WS PAYLOAD: ${data['payload']}');

      final handlers = _handlers[event];

      if (handlers == null || handlers.isEmpty) {
        debugPrint('GLOBAL CALL WS NO HANDLER FOR: $event');
        return;
      }

      for (final handler in List<GlobalSocketHandler>.from(handlers)) {
        try {
          await handler(data);
        } catch (e, st) {
          debugPrint('GLOBAL CALL WS HANDLER ERROR FOR $event: $e');
          debugPrint(st.toString());
        }
      }
    } catch (e, st) {
      debugPrint('GLOBAL CALL WS PARSE ERROR: $e');
      debugPrint(st.toString());
    } finally {
      debugPrint('========================================================');
    }
  }

  Map<String, dynamic> _normalizeData(
    Map<String, dynamic> rawData,
    String event,
  ) {
    final data = Map<String, dynamic>.from(rawData);

    data['event'] = event;
    data['type'] = event;

    final rawPayload = data['payload'];

    Map<String, dynamic> payload;

    if (rawPayload is Map<String, dynamic>) {
      payload = Map<String, dynamic>.from(rawPayload);
    } else if (rawPayload is Map) {
      payload = Map<String, dynamic>.from(rawPayload);
    } else {
      payload = <String, dynamic>{};
    }

    for (final entry in data.entries) {
      final key = entry.key;

      if (key == 'event' || key == 'type' || key == 'payload') {
        continue;
      }

      payload.putIfAbsent(key, () => entry.value);
    }

    payload['event'] = event;
    payload['type'] = event;

    _mirror(payload, 'conversation_id', 'conversationId');
    _mirror(payload, 'caller_id', 'callerId');
    _mirror(payload, 'caller_name', 'callerName');
    _mirror(payload, 'caller_avatar', 'callerAvatar');
    _mirror(payload, 'call_id', 'callId');
    _mirror(payload, 'is_video_call', 'isVideoCall');
    _mirror(payload, 'from_user', 'fromUser');
    _mirror(payload, 'target_user', 'targetUser');

    if (payload['from'] == null && payload['from_user'] != null) {
      payload['from'] = payload['from_user'];
    }

    if (payload['from_user'] == null && payload['from'] != null) {
      payload['from_user'] = payload['from'];
    }

    data['payload'] = payload;

    return data;
  }

  void _mirror(Map<String, dynamic> map, String snake, String camel) {
    if (map[snake] == null && map[camel] != null) {
      map[snake] = map[camel];
    }

    if (map[camel] == null && map[snake] != null) {
      map[camel] = map[snake];
    }
  }

  void on(String event, GlobalSocketHandler handler) {
    final list = _handlers.putIfAbsent(event, () => []);

    if (!list.contains(handler)) {
      list.add(handler);
    }

    debugPrint(
      'GLOBAL CALL WS HANDLER REGISTERED: $event COUNT: ${list.length}',
    );
  }

  void off(String event, [GlobalSocketHandler? handler]) {
    if (handler == null) return;

    final list = _handlers[event];
    if (list == null) return;

    list.remove(handler);

    if (list.isEmpty) {
      _handlers.remove(event);
    }

    debugPrint('GLOBAL CALL WS HANDLER REMOVED: $event');
  }

  Future<void> disconnect({
    bool clearHandlers = false,
    bool forgetUrl = true,
    bool manual = true,
  }) async {
    debugPrint('GLOBAL CALL WS DISCONNECT');

    if (manual) {
      _manualDisconnect = true;
    }

    _reconnectTimer?.cancel();
    _connected = false;
    _connecting = false;

    final oldSubscription = _subscription;
    final oldChannel = _channel;

    _subscription = null;
    _channel = null;

    if (forgetUrl) {
      _url = null;
    }

    try {
      await oldSubscription?.cancel();
    } catch (_) {}

    try {
      await oldChannel?.sink.close();
    } catch (_) {}

    if (clearHandlers) {
      _handlers.clear();
    }
  }

  Future<void> reconnect() async {
    debugPrint('GLOBAL CALL WS MANUAL RECONNECT DISABLED');
    return;
  }

  void reset() {
    _reconnectTimer?.cancel();
    _handlers.clear();
    _connected = false;
    _connecting = false;
    _manualDisconnect = true;
    _url = null;
    _channel = null;
    _subscription = null;
    _connectCompleter = null;

    debugPrint('GLOBAL CALL WS RESET');
  }
}