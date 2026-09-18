// lib/core/call/global_call_socket_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef GlobalSocketHandler = FutureOr<void> Function(
  Map<String, dynamic> data,
);

typedef GlobalSocketUrlProvider = Future<String?> Function();

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
  StreamSubscription<dynamic>? _subscription;

  final Map<String, List<GlobalSocketHandler>> _handlers =
      <String, List<GlobalSocketHandler>>{};

  bool _connected = false;
  bool _connecting = false;
  bool _manualDisconnect = false;

  String? _url;
  GlobalSocketUrlProvider? _reconnectUrlProvider;

  Completer<void>? _connectCompleter;
  Timer? _reconnectTimer;

  Timer? _heartbeatTimer;
  Timer? _heartbeatTimeoutTimer;
  DateTime? _lastPongAt;
  bool _heartbeatWaitingForPong = false;

  static const Duration _heartbeatInterval = Duration(seconds: 25);
  static const Duration _heartbeatTimeout = Duration(seconds: 20);
  static const Duration _healthyWindow = Duration(seconds: 70);

  int _reconnectAttempt = 0;
  int _generation = 0;

  bool get isConnected =>
      _connected && _channel != null && _subscription != null;

  bool get isConnecting => _connecting;
  String? get currentUrl => _url;

  bool get isHealthy {
    if (!isConnected) return false;
    final last = _lastPongAt;
    if (last == null) return true;
    return DateTime.now().difference(last) <= _healthyWindow;
  }

  void setReconnectUrlProvider(GlobalSocketUrlProvider? provider) {
    _reconnectUrlProvider = provider;
  }

  String _safeEndpoint(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.replace(query: '', fragment: '').toString();
    } catch (_) {
      return '<websocket>';
    }
  }

  String _sanitizeWsUrl(String url) {
    var fixed = url.trim().replaceAll('#', '');

    if (fixed.startsWith('http://')) {
      fixed = fixed.replaceFirst('http://', 'ws://');
    } else if (fixed.startsWith('https://')) {
      fixed = fixed.replaceFirst('https://', 'wss://');
    }

    return fixed;
  }

  Future<String?> _resolveReconnectUrl() async {
    final provider = _reconnectUrlProvider;

    if (provider != null) {
      try {
        final fresh = await provider();
        final clean = fresh?.trim() ?? '';
        if (clean.isNotEmpty) {
          return _sanitizeWsUrl(clean);
        }
      } catch (e, st) {
        debugPrint('GLOBAL CALL WS URL PROVIDER ERROR: $e');
        debugPrint(st.toString());
      }
    }

    final existing = _url?.trim() ?? '';
    if (existing.isEmpty) return null;

    return _sanitizeWsUrl(existing);
  }

  Future<void> connect({required String url}) async {
    final fixedUrl = _sanitizeWsUrl(url);

    if (fixedUrl.isEmpty) {
      debugPrint('GLOBAL CALL WS CONNECT ERROR: URL empty');
      return;
    }

    if (isConnected && _url == fixedUrl) {
      debugPrint('GLOBAL CALL WS ALREADY CONNECTED');
      return;
    }

    if (_connecting && _connectCompleter != null) {
      debugPrint('GLOBAL CALL WS CONNECT ALREADY IN PROGRESS');
      return _connectCompleter!.future;
    }

    _manualDisconnect = false;
    _connecting = true;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final completer = Completer<void>();
    _connectCompleter = completer;

    final myGeneration = ++_generation;

    try {
      final oldSubscription = _subscription;
      final oldChannel = _channel;

      _stopHeartbeat();
      _subscription = null;
      _channel = null;
      _connected = false;

      try {
        await oldSubscription?.cancel();
      } catch (_) {}

      try {
        await oldChannel?.sink.close();
      } catch (_) {}

      if (myGeneration != _generation) {
        debugPrint('GLOBAL CALL WS CONNECT ABORTED: generation changed');
        return;
      }

      _url = fixedUrl;

      debugPrint('');
      debugPrint('################################################');
      debugPrint('### GLOBAL CALL WS CONNECTING');
      debugPrint('################################################');
      debugPrint('endpoint: ${_safeEndpoint(fixedUrl)}');
      debugPrint('################################################');

      final channel = WebSocketChannel.connect(Uri.parse(fixedUrl));
      _channel = channel;

      late final StreamSubscription<dynamic> subscription;

      subscription = channel.stream.listen(
        _handleMessage,
        onError: (Object error, StackTrace stack) {
          if (myGeneration != _generation || _channel != channel) {
            debugPrint('GLOBAL CALL WS STALE ERROR IGNORED');
            return;
          }

          debugPrint('GLOBAL CALL WS ERROR: $error');
          debugPrint(stack.toString());

          _stopHeartbeat();
          _connected = false;
          _channel = null;

          if (identical(_subscription, subscription)) {
            _subscription = null;
          }

          _scheduleReconnect();
        },
        onDone: () {
          if (myGeneration != _generation || _channel != channel) {
            debugPrint('GLOBAL CALL WS STALE CLOSE IGNORED');
            return;
          }

          debugPrint('GLOBAL CALL WS CLOSED');

          _stopHeartbeat();
          _connected = false;
          _channel = null;

          if (identical(_subscription, subscription)) {
            _subscription = null;
          }

          _scheduleReconnect();
        },
        cancelOnError: false,
      );

      _subscription = subscription;

      try {
        await channel.ready.timeout(const Duration(seconds: 10));
      } catch (e) {
        if (myGeneration != _generation || _channel != channel) {
          debugPrint('GLOBAL CALL WS READY FAILURE IGNORED: stale transport');
          return;
        }

        debugPrint('GLOBAL CALL WS READY FAILED: $e');

        _stopHeartbeat();
        _connected = false;

        if (identical(_subscription, subscription)) {
          _subscription = null;
        }

        if (_channel == channel) {
          _channel = null;
        }

        try {
          await subscription.cancel();
        } catch (_) {}

        try {
          await channel.sink.close();
        } catch (_) {}

        _scheduleReconnect();
        return;
      }

      if (myGeneration != _generation || _channel != channel) {
        debugPrint('GLOBAL CALL WS READY IGNORED: stale transport');
        try {
          await subscription.cancel();
        } catch (_) {}
        try {
          await channel.sink.close();
        } catch (_) {}
        return;
      }

      _connected = true;
      _reconnectAttempt = 0;
      _lastPongAt = DateTime.now();
      _startHeartbeat(myGeneration, channel);

      debugPrint(
        'GLOBAL CALL WS CONNECTED/ACTIVE: ${_safeEndpoint(fixedUrl)}',
      );

      // unawaited(
      //   _dispatchLocalEvent(
      //     GlobalCallSocketEvents.connected,
      //     <String, dynamic>{
      //       'event': GlobalCallSocketEvents.connected,
      //       'type': GlobalCallSocketEvents.connected,
      //       'endpoint': _safeEndpoint(fixedUrl),
      //     },
      //   ),
      // );
    } catch (e, st) {
      if (myGeneration != _generation) {
        debugPrint('GLOBAL CALL WS CONNECT ERROR IGNORED: stale generation');
        return;
      }

      debugPrint('GLOBAL CALL WS CONNECT ERROR: $e');
      debugPrint(st.toString());

      _stopHeartbeat();
      _connected = false;

      final sub = _subscription;
      final channel = _channel;

      _subscription = null;
      _channel = null;

      try {
        await sub?.cancel();
      } catch (_) {}

      try {
        await channel?.sink.close();
      } catch (_) {}

      _scheduleReconnect();
    } finally {
      if (myGeneration == _generation) {
        _connecting = false;
      }

      if (identical(_connectCompleter, completer)) {
        if (!completer.isCompleted) {
          completer.complete();
        }
        _connectCompleter = null;
      }
    }
  }

  void _scheduleReconnect() {
    if (_manualDisconnect) {
      debugPrint('GLOBAL CALL WS RECONNECT SKIPPED: manual disconnect');
      return;
    }

    _reconnectTimer?.cancel();

    _reconnectAttempt++;

    final delaySeconds = _reconnectAttempt <= 1
        ? 1
        : _reconnectAttempt <= 3
            ? 3
            : _reconnectAttempt <= 6
                ? 5
                : 10;

    debugPrint(
      'GLOBAL CALL WS RECONNECT SCHEDULED in ${delaySeconds}s '
      'attempt=$_reconnectAttempt',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_manualDisconnect) {
        debugPrint('GLOBAL CALL WS RECONNECT CANCELLED: manual disconnect');
        return;
      }

      if (isConnected) {
        debugPrint('GLOBAL CALL WS RECONNECT CANCELLED: already connected');
        return;
      }

      if (_connecting) {
        debugPrint('GLOBAL CALL WS RECONNECT DEFERRED: connect in progress');
        _scheduleReconnect();
        return;
      }

      try {
        final nextUrl = await _resolveReconnectUrl();

        if (nextUrl == null || nextUrl.trim().isEmpty) {
          debugPrint('GLOBAL CALL WS RECONNECT: no URL available');
          _scheduleReconnect();
          return;
        }

        debugPrint('GLOBAL CALL WS AUTO RECONNECT START');
        await connect(url: nextUrl);
      } catch (e, st) {
        debugPrint('GLOBAL CALL WS AUTO RECONNECT ERROR: $e');
        debugPrint(st.toString());
        _scheduleReconnect();
      }
    });
  }

  Future<void> ensureConnected() async {
    if (_manualDisconnect) {
      _manualDisconnect = false;
    }

    if (_connecting) return;

    if (isConnected && isHealthy) {
      return;
    }

    if (isConnected && !isHealthy) {
      debugPrint('GLOBAL CALL WS ENSURE: stale connection detected');
      await forceReconnect(reason: 'ensure_unhealthy');
      return;
    }

    final nextUrl = await _resolveReconnectUrl();

    if (nextUrl == null || nextUrl.trim().isEmpty) {
      debugPrint('GLOBAL CALL WS ENSURE CONNECTED FAILED: URL unavailable');
      return;
    }

    await connect(url: nextUrl);
  }

  Future<void> forceReconnect({String reason = 'manual_health_reconnect'}) async {
    if (_manualDisconnect) {
      _manualDisconnect = false;
    }

    debugPrint('GLOBAL CALL WS FORCE RECONNECT: $reason');

    _stopHeartbeat();

    ++_generation;

    _connected = false;
    _connecting = false;

    final oldSubscription = _subscription;
    final oldChannel = _channel;

    _subscription = null;
    _channel = null;

    try {
      await oldSubscription?.cancel();
    } catch (_) {}

    try {
      await oldChannel?.sink.close();
    } catch (_) {}

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final nextUrl = await _resolveReconnectUrl();

    if (nextUrl == null || nextUrl.trim().isEmpty) {
      _scheduleReconnect();
      return;
    }

    await connect(url: nextUrl);
  }

  void _startHeartbeat(
  int generation,
  WebSocketChannel channel,
) {
  _stopHeartbeat();

  _lastPongAt = DateTime.now();
  _heartbeatWaitingForPong = false;

  _heartbeatTimer = Timer.periodic(
    _heartbeatInterval,
    (_) {
      if (_manualDisconnect ||
          generation != _generation ||
          _channel != channel ||
          !isConnected) {
        return;
      }

      // Don't send multiple pings simultaneously.
      if (_heartbeatWaitingForPong) {
        debugPrint(
          'GLOBAL CALL WS PING SKIPPED: waiting for previous pong',
        );
        return;
      }

      final payload = <String, dynamic>{
        'event': 'ping',
        'type': 'ping',
        'action': 'ping',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      try {
        _heartbeatWaitingForPong = true;

        channel.sink.add(
          jsonEncode(payload),
        );

        debugPrint('GLOBAL CALL WS PING');
      } catch (e, st) {
        _heartbeatWaitingForPong = false;

        debugPrint(
          'GLOBAL CALL WS PING SEND ERROR: $e',
        );
        debugPrint(st.toString());

        unawaited(
          forceReconnect(
            reason: 'ping_send_error',
          ),
        );

        return;
      }

      _heartbeatTimeoutTimer?.cancel();

      _heartbeatTimeoutTimer = Timer(
        _heartbeatTimeout,
        () {
          if (_manualDisconnect ||
              generation != _generation ||
              _channel != channel ||
              !isConnected) {
            return;
          }

          if (!_heartbeatWaitingForPong) {
            return;
          }

          debugPrint(
            'GLOBAL CALL WS HEARTBEAT TIMEOUT -> reconnect',
          );

          _heartbeatWaitingForPong = false;

          unawaited(
            forceReconnect(
              reason: 'heartbeat_timeout',
            ),
          );
        },
      );
    },
  );
}

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = null;

    _heartbeatWaitingForPong = false;
  }

 Future<void> _handleMessage(dynamic message) async {
  debugPrint('');
  debugPrint(
    '================ GLOBAL CALL WS MESSAGE ================',
  );

  try {
    final decoded = jsonDecode(message.toString());

    if (decoded is! Map) {
      debugPrint('GLOBAL CALL WS INVALID DATA');
      return;
    }

    final rawData = Map<String, dynamic>.from(decoded);

    // Any valid message means the socket/server is alive.
    _lastPongAt = DateTime.now();

    final event = (
      rawData['event'] ??
      rawData['type'] ??
      rawData['action'] ??
      ''
    ).toString();

    if (event.trim().isEmpty) {
      debugPrint('GLOBAL CALL WS EVENT EMPTY');
      return;
    }

    // Accept all common heartbeat acknowledgements.
    if (event == 'pong' ||
        event == 'global_pong' ||
        event == 'ping_ack' ||
        event == 'heartbeat_ack' ||
        event == 'heartbeat') {
      _heartbeatWaitingForPong = false;

      _heartbeatTimeoutTimer?.cancel();
      _heartbeatTimeoutTimer = null;

      debugPrint('GLOBAL CALL WS PONG');
      return;
    }

    // A real server message also proves this connection is alive.
    //
    // For example incoming_call/call_cancelled may arrive while we're
    // waiting for a pong. Don't destroy a perfectly working socket.
    if (_heartbeatWaitingForPong) {
      debugPrint(
        'GLOBAL CALL WS ACTIVITY RECEIVED WHILE WAITING FOR PONG: $event',
      );

      _heartbeatWaitingForPong = false;

      _heartbeatTimeoutTimer?.cancel();
      _heartbeatTimeoutTimer = null;
    }

    final data = _normalizeData(rawData, event);

    debugPrint('GLOBAL CALL WS EVENT: $event');

    final handlers = _handlers[event];

    if (handlers == null || handlers.isEmpty) {
      debugPrint('GLOBAL CALL WS NO HANDLER FOR: $event');
      return;
    }

    for (final handler in List<GlobalSocketHandler>.from(handlers)) {
      try {
        await handler(data);
      } catch (e, st) {
        debugPrint(
          'GLOBAL CALL WS HANDLER ERROR FOR $event: $e',
        );
        debugPrint(st.toString());
      }
    }
  } catch (e, st) {
    debugPrint('GLOBAL CALL WS PARSE ERROR: $e');
    debugPrint(st.toString());
  } finally {
    debugPrint(
      '========================================================',
    );
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

  Future<void> _dispatchLocalEvent(
    String event,
    Map<String, dynamic> data,
  ) async {
    final handlers = _handlers[event];

    if (handlers == null || handlers.isEmpty) {
      debugPrint('GLOBAL CALL WS NO HANDLER FOR LOCAL EVENT: $event');
      return;
    }

    for (final handler in List<GlobalSocketHandler>.from(handlers)) {
      try {
        await handler(data);
      } catch (e, st) {
        debugPrint('GLOBAL CALL WS LOCAL HANDLER ERROR FOR $event: $e');
        debugPrint(st.toString());
      }
    }
  }

  void on(String event, GlobalSocketHandler handler) {
    final list = _handlers.putIfAbsent(
      event,
      () => <GlobalSocketHandler>[],
    );

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
    _reconnectTimer = null;
    _stopHeartbeat();

    ++_generation;

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

    final completer = _connectCompleter;
    _connectCompleter = null;

    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> reconnect() async {
    if (_connecting) return;

    _manualDisconnect = false;

    final nextUrl = await _resolveReconnectUrl();

    if (nextUrl == null || nextUrl.trim().isEmpty) {
      debugPrint('GLOBAL CALL WS MANUAL RECONNECT FAILED: URL unavailable');
      return;
    }

    debugPrint('GLOBAL CALL WS MANUAL RECONNECT START');
    await connect(url: nextUrl);
  }

  void reset() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();

    ++_generation;

    final oldSubscription = _subscription;
    final oldChannel = _channel;

    _subscription = null;
    _channel = null;

    if (oldSubscription != null) {
      unawaited(oldSubscription.cancel());
    }

    if (oldChannel != null) {
      unawaited(oldChannel.sink.close());
    }

    _handlers.clear();
    _connected = false;
    _connecting = false;
    _manualDisconnect = true;
    _url = null;
    _reconnectUrlProvider = null;
    _connectCompleter = null;
    _reconnectAttempt = 0;
    _lastPongAt = null;
    _heartbeatWaitingForPong = false;

    debugPrint('GLOBAL CALL WS RESET');
  }
}
