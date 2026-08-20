// core/chat/chat_socket_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/core/config/app_config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ChatSocketService
    with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  Timer? _reconnectTimer;

  bool _connected = false;
  bool _connecting = false;

  bool _manualDisconnect = false;

  int? _conversationId;

  FutureOr<void> Function(
    Map<String, dynamic> data,
  )? _onMessage;

  void Function(Object error)? _onError;

  void Function()? _onDisconnected;

  int _reconnectAttempt = 0;

  static const int _maxReconnectAttempts = 20;

  bool get isConnected => _connected;

  bool get isConnecting => _connecting;

  int? get conversationId => _conversationId;

  // ============================================================
  // CONNECT
  // ============================================================

  Future<void> connect({
    required int conversationId,
    required FutureOr<void> Function(
      Map<String, dynamic> data,
    ) onMessage,
    required void Function(
      Object error,
    ) onError,
    required void Function()
        onDisconnected,
  }) async {
    _conversationId = conversationId;

    _onMessage = onMessage;
    _onError = onError;
    _onDisconnected = onDisconnected;

    _manualDisconnect = false;

    WidgetsBinding.instance
        .removeObserver(this);

    WidgetsBinding.instance
        .addObserver(this);

    await _connectInternal();
  }

  // ============================================================
  // INTERNAL CONNECT
  // ============================================================

  Future<void> _connectInternal() async {
    final conversationId =
        _conversationId;

    if (conversationId == null) {
      debugPrint(
        'CHAT WS: conversationId missing',
      );
      return;
    }

    if (_connecting) {
      debugPrint(
        'CHAT WS ALREADY CONNECTING',
      );
      return;
    }

    if (_connected &&
        _channel != null) {
      debugPrint(
        'CHAT WS ALREADY CONNECTED',
      );
      return;
    }

    _connecting = true;

    try {
      await _closeSocketOnly();

      final token =
          await ApiClient.storage.read(
        key: 'access',
      );

      if (token == null ||
          token.trim().isEmpty) {
        throw Exception(
          'Access token missing',
        );
      }

      final cleanToken =
          Uri.encodeComponent(
        token.trim(),
      );

      final url =
          '${AppConfig.wsBaseUrl}'
          '/ws/chat/$conversationId/'
          '?token=$cleanToken';

      debugPrint('');
      debugPrint(
        '########################################',
      );
      debugPrint(
        'CHAT WS CONNECTING',
      );
      debugPrint(
        'conversationId: $conversationId',
      );
      debugPrint(
        '########################################',
      );

      final channel =
          WebSocketChannel.connect(
        Uri.parse(url),
      );

      // Actual WebSocket handshake.
      await channel.ready;

      _channel = channel;

      _connected = true;
      _connecting = false;

      _reconnectAttempt = 0;

      debugPrint(
        'CHAT WS CONNECTED SUCCESSFULLY',
      );

      _subscription =
          channel.stream.listen(
        (message) async {
          debugPrint(
            'CHAT WS RAW: $message',
          );

          try {
            final decoded =
                jsonDecode(
              message.toString(),
            );

            if (decoded is! Map) {
              debugPrint(
                'CHAT WS INVALID MESSAGE',
              );
              return;
            }

            final callback =
                _onMessage;

            if (callback != null) {
              await callback(
                Map<String, dynamic>.from(
                  decoded,
                ),
              );
            }
          } catch (e) {
            debugPrint(
              'CHAT WS PARSE ERROR: $e',
            );
          }
        },

        onError: (error) {
          debugPrint(
            'CHAT WS ERROR: $error',
          );

          _connected = false;
          _connecting = false;

          _onError?.call(error);

          if (!_manualDisconnect) {
            _scheduleReconnect();
          }
        },

        onDone: () {
          debugPrint(
            'CHAT WS CLOSED',
          );

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
      debugPrint(
        'CHAT WS CONNECT ERROR: $e',
      );

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
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    debugPrint(
      'CHAT WS APP STATE: $state',
    );

    // ----------------------------------------------------------
    // APP RETURNS TO FOREGROUND
    // ----------------------------------------------------------

    if (state ==
        AppLifecycleState.resumed) {
      debugPrint(
        'CHAT WS APP RESUMED',
      );

      /*
       * Android may have suspended/destroyed
       * the old WebSocket while app was
       * backgrounded.
       *
       * Establish a fresh connection.
       */
      unawaited(
        _reconnectOnResume(),
      );

      return;
    }

    // ----------------------------------------------------------
    // BACKGROUND
    // ----------------------------------------------------------

    if (state ==
            AppLifecycleState.paused ||
        state ==
            AppLifecycleState.hidden) {
      debugPrint(
        'CHAT WS APP BACKGROUND',
      );

      /*
       * Do not depend on this connection.
       *
       * FCM handles background/killed
       * messages.
       *
       * We don't need to aggressively close
       * here because Android may resume
       * quickly.
       */
      return;
    }

    // ----------------------------------------------------------
    // APP TERMINATING
    // ----------------------------------------------------------

    if (state ==
        AppLifecycleState.detached) {
      debugPrint(
        'CHAT WS APP DETACHED',
      );

      /*
       * FCM takes over when the app process
       * is gone.
       */

      return;
    }
  }

  // ============================================================
  // RESUME RECONNECT
  // ============================================================

  Future<void>
      _reconnectOnResume() async {
    if (_manualDisconnect) {
      return;
    }

    if (_conversationId == null) {
      return;
    }

    /*
     * Even if _connected says true,
     * the underlying TCP socket may have
     * died while Android suspended the app.
     *
     * Create a clean connection.
     */

    await _closeSocketOnly();

    _connected = false;
    _connecting = false;

    await _connectInternal();
  }

  // ============================================================
  // RECONNECT
  // ============================================================

  void _scheduleReconnect() {
    if (_manualDisconnect) {
      return;
    }

    if (_conversationId == null) {
      return;
    }

    if (_reconnectTimer?.isActive ==
        true) {
      return;
    }

    if (_reconnectAttempt >=
        _maxReconnectAttempts) {
      debugPrint(
        'CHAT WS MAX RECONNECT '
        'ATTEMPTS REACHED',
      );
      return;
    }

    _reconnectAttempt++;

    final seconds =
        (_reconnectAttempt * 2)
            .clamp(
      2,
      10,
    );

    debugPrint(
      'CHAT WS RECONNECT '
      '$_reconnectAttempt/'
      '$_maxReconnectAttempts '
      'IN ${seconds}s',
    );

    _reconnectTimer =
        Timer(
      Duration(
        seconds: seconds,
      ),
      () async {
        _reconnectTimer = null;

        if (_manualDisconnect) {
          return;
        }

        await _connectInternal();
      },
    );
  }

  // ============================================================
  // SEND TYPING
  // ============================================================

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

  // ============================================================
  // SEND
  // ============================================================

  bool send(
    Map<String, dynamic> data,
  ) {
    if (_channel == null ||
        !_connected) {
      debugPrint(
        'CHAT WS NOT CONNECTED',
      );

      return false;
    }

    try {
      final encoded =
          jsonEncode(data);

      debugPrint(
        'CHAT WS SEND: $encoded',
      );

      _channel!.sink.add(
        encoded,
      );

      return true;
    } catch (e) {
      debugPrint(
        'CHAT WS SEND ERROR: $e',
      );

      _connected = false;

      if (!_manualDisconnect) {
        _scheduleReconnect();
      }

      return false;
    }
  }

  // ============================================================
  // INTERNAL CLOSE
  // ============================================================

  Future<void>
      _closeSocketOnly() async {
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

  // ============================================================
  // DISCONNECT
  // ============================================================

  Future<void> disconnect() async {
    debugPrint(
      'CHAT WS MANUAL DISCONNECT',
    );

    _manualDisconnect = true;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    WidgetsBinding.instance
        .removeObserver(this);

    await _closeSocketOnly();

    _connected = false;
    _connecting = false;

    _conversationId = null;

    _onMessage = null;
    _onError = null;
    _onDisconnected = null;

    _reconnectAttempt = 0;

    debugPrint(
      'CHAT WS DISCONNECTED',
    );
  }
}