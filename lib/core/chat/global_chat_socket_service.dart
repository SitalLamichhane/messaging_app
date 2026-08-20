// lib/core/chat/global_chat_socket_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/core/config/app_config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class GlobalChatSocketService with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;

  bool _connected = false;
  bool _connecting = false;
  bool _manualDisconnect = false;

  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 20;

  FutureOr<void> Function(Map<String, dynamic> data)? _onMessage;
  void Function(Object error)? _onError;
  void Function()? _onDisconnected;

  bool get isConnected => _connected;
  bool get isConnecting => _connecting;

  // ============================================================
  // CONNECT
  // ============================================================

  Future<void> connect({
    required FutureOr<void> Function(Map<String, dynamic> data) onMessage,
    required void Function(Object error) onError,
    required void Function() onDisconnected,
  }) async {
    _onMessage = onMessage;
    _onError = onError;
    _onDisconnected = onDisconnected;
    _manualDisconnect = false;

    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);

    await _connectInternal();
  }

  // ============================================================
  // INTERNAL CONNECT
  // ============================================================

  Future<void> _connectInternal() async {
    if (_connecting) {
      debugPrint('GLOBAL CHAT WS ALREADY CONNECTING');
      return;
    }

    if (_connected && _channel != null) {
      debugPrint('GLOBAL CHAT WS ALREADY CONNECTED');
      return;
    }

    _connecting = true;

    try {
      await _closeSocketOnly();

      final token = await ApiClient.storage.read(key: 'access');

      if (token == null || token.trim().isEmpty) {
        throw Exception('Access token missing');
      }

      final cleanToken = Uri.encodeComponent(token.trim());
      final url = '${AppConfig.wsBaseUrl}/ws/global-chat/?token=$cleanToken';

      debugPrint('');
      debugPrint('########################################');
      debugPrint('GLOBAL CHAT WS CONNECTING');
      debugPrint('endpoint: ${AppConfig.wsBaseUrl}/ws/global-chat/');
      debugPrint('########################################');

      final channel = WebSocketChannel.connect(Uri.parse(url));
      await channel.ready;

      _channel = channel;
      _connected = true;
      _connecting = false;
      _reconnectAttempt = 0;

      debugPrint('GLOBAL CHAT WS CONNECTED SUCCESSFULLY');

      _subscription = channel.stream.listen(
        (message) async {
          debugPrint('GLOBAL CHAT WS RAW: $message');

          try {
            final decoded = jsonDecode(message.toString());

            if (decoded is! Map) {
              debugPrint('GLOBAL CHAT WS INVALID MESSAGE');
              return;
            }

            final callback = _onMessage;
            if (callback != null) {
              await callback(Map<String, dynamic>.from(decoded));
            }
          } catch (e) {
            debugPrint('GLOBAL CHAT WS PARSE ERROR: $e');
          }
        },
        onError: (error) {
          debugPrint('GLOBAL CHAT WS ERROR: $error');

          _connected = false;
          _connecting = false;
          _onError?.call(error);

          if (!_manualDisconnect) {
            _scheduleReconnect();
          }
        },
        onDone: () {
          debugPrint('GLOBAL CHAT WS CLOSED');

          _connected = false;
          _connecting = false;
          _channel = null;
          _subscription = null;

          _onDisconnected?.call();

          if (!_manualDisconnect) {
            _scheduleReconnect();
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('GLOBAL CHAT WS CONNECT ERROR: $e');

      _connected = false;
      _connecting = false;
      _channel = null;

      _onError?.call(e);

      if (!_manualDisconnect) {
        _scheduleReconnect();
      }
    }
  }

  // ============================================================
  // APP LIFECYCLE
  // ============================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('GLOBAL CHAT WS APP STATE: $state');

    if (state == AppLifecycleState.resumed) {
      debugPrint('GLOBAL CHAT WS APP RESUMED');
      unawaited(_reconnectOnResume());
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Android/iOS may suspend this connection. FCM should cover background
      // delivery; when the app resumes we establish a clean socket again.
      debugPrint('GLOBAL CHAT WS APP BACKGROUND');
      return;
    }

    if (state == AppLifecycleState.detached) {
      debugPrint('GLOBAL CHAT WS APP DETACHED');
    }
  }

  Future<void> _reconnectOnResume() async {
    if (_manualDisconnect) return;

    await _closeSocketOnly();
    _connected = false;
    _connecting = false;

    await _connectInternal();
  }

  // ============================================================
  // RECONNECT
  // ============================================================

  void _scheduleReconnect() {
    if (_manualDisconnect) return;
    if (_reconnectTimer?.isActive == true) return;

    if (_reconnectAttempt >= _maxReconnectAttempts) {
      debugPrint('GLOBAL CHAT WS MAX RECONNECT ATTEMPTS REACHED');
      return;
    }

    _reconnectAttempt++;
    final seconds = (_reconnectAttempt * 2).clamp(2, 10);

    debugPrint(
      'GLOBAL CHAT WS RECONNECT '
      '$_reconnectAttempt/$_maxReconnectAttempts IN ${seconds}s',
    );

    _reconnectTimer = Timer(
      Duration(seconds: seconds),
      () async {
        _reconnectTimer = null;
        if (_manualDisconnect) return;
        await _connectInternal();
      },
    );
  }

  // ============================================================
  // OPTIONAL PING
  // ============================================================

  bool sendPing() {
    return send({
      'action': 'ping',
      'type': 'ping',
    });
  }

  bool send(Map<String, dynamic> data) {
    if (_channel == null || !_connected) {
      return false;
    }

    try {
      _channel!.sink.add(jsonEncode(data));
      return true;
    } catch (e) {
      debugPrint('GLOBAL CHAT WS SEND ERROR: $e');
      _connected = false;

      if (!_manualDisconnect) {
        _scheduleReconnect();
      }

      return false;
    }
  }

  // ============================================================
  // CLOSE / DISCONNECT
  // ============================================================

  Future<void> _closeSocketOnly() async {
    try {
      await _subscription?.cancel();
    } catch (_) {}

    _subscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _channel = null;
    _connected = false;
  }

  Future<void> disconnect() async {
    debugPrint('GLOBAL CHAT WS MANUAL DISCONNECT');

    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    WidgetsBinding.instance.removeObserver(this);

    await _closeSocketOnly();

    _connected = false;
    _connecting = false;
    _onMessage = null;
    _onError = null;
    _onDisconnected = null;
    _reconnectAttempt = 0;

    debugPrint('GLOBAL CHAT WS DISCONNECTED');
  }
}
