
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService instance = SocketService._internal();

  SocketService._internal();

  IO.Socket? socket;

  String? _userId;

  bool get isConnected => socket?.connected == true;

  void connect({
    required String userId,
    required String serverUrl,
  }) {
    if (socket != null && socket!.connected) {
      debugPrint('SOCKET ALREADY CONNECTED');
      return;
    }

    _userId = userId;

    socket = IO.io(
      serverUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(999999)
          .setReconnectionDelay(2000)
          .build(),
    );

    socket!.connect();

    socket!.onConnect((_) {
      debugPrint('SOCKET CONNECTED');

      socket!.emit('join', {
        'userId': userId,
      });

      socket!.emit('user_online', {
        'userId': userId,
      });
    });

    socket!.onReconnect((_) {
      debugPrint('SOCKET RECONNECTED');

      socket!.emit('join', {
        'userId': userId,
      });

      socket!.emit('user_online', {
        'userId': userId,
      });
    });

    socket!.onDisconnect((_) {
      debugPrint('SOCKET DISCONNECTED');
    });

    socket!.onConnectError((data) {
      debugPrint('SOCKET CONNECT ERROR: $data');
    });

    socket!.onError((data) {
      debugPrint('SOCKET ERROR: $data');
    });
  }

  void emit(String event, dynamic data) {
    debugPrint('EMIT => $event');
    debugPrint(data.toString());

    socket?.emit(event, data);
  }

  void on(String event, Function(dynamic) handler) {
    socket?.off(event);

    socket?.on(event, (data) {
      debugPrint('ON => $event');
      debugPrint(data.toString());

      handler(data);
    });
  }

  void off(String event) {
    socket?.off(event);
  }

  void disconnect() {
    if (_userId != null) {
      socket?.emit('user_offline', {
        'userId': _userId,
      });
    }

    socket?.disconnect();
    socket?.dispose();

    socket = null;

    debugPrint('SOCKET CLOSED');
  }
}
