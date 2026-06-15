// lib/core/call/call_socket_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class CallSocketEvents {
  static const String incomingCall = 'incoming_call';

  static const String callOffer = 'call_offer';
  static const String callAnswer = 'call_answer';
  static const String iceCandidate = 'ice_candidate';

  static const String callReady = 'call_ready';

  static const String callReject = 'call_reject';
  static const String callEnd = 'call_end';
  static const String callLeave = 'call_leave';
  static const String callBusy = 'call_busy';
  static const String callTimeout = 'call_timeout';

  @Deprecated('Do not use call_join. Backend does not support it.')
  static const String callJoin = 'call_join';

  @Deprecated('Use call_answer instead.')
  static const String callAccept = 'call_accept';

  static const String callRenegotiateOffer = 'call_renegotiate_offer';
  static const String callRenegotiateAnswer = 'call_renegotiate_answer';
  static const String callVideoToggle = 'call_video_toggle';
  static const String callVideoUpgradeRejected =
      'call_video_upgrade_rejected';

  static const String callEventSent = 'call_event_sent';
}

typedef SocketHandler = FutureOr<void> Function(Map<String, dynamic> data);

class _PendingSocketMessage {
  final String event;
  final Map<String, dynamic> payload;
  final String? targetUser;
  final String? conversationId;

  const _PendingSocketMessage({
    required this.event,
    required this.payload,
    this.targetUser,
    this.conversationId,
  });
}

class _CachedOffer {
  final Map<String, dynamic> payload;
  final String? targetUser;
  final String? conversationId;
  final DateTime createdAt;

  const _CachedOffer({
    required this.payload,
    required this.targetUser,
    required this.conversationId,
    required this.createdAt,
  });
}

class SocketService {
  static final SocketService instance = SocketService._internal();
  SocketService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final Map<String, List<SocketHandler>> _handlers = {};
  final List<_PendingSocketMessage> _pendingMessages = [];

  final Map<String, _CachedOffer> _cachedOffers = {};
  final Map<String, DateTime> _lastCallReadyResend = {};

  bool _connected = false;
  bool _connecting = false;
  String? _url;

  Completer<void>? _connectCompleter;

  bool get isConnected => _connected;
  bool get isConnecting => _connecting;
  String? get currentUrl => _url;

  String _sanitizeWsUrl(String url) {
    var fixed = url.trim();
    fixed = fixed.replaceAll('#', '');

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
      debugPrint('CALL WS CONNECT ERROR: URL empty');
      return;
    }

    if (_connected && _channel != null && _url == fixedUrl) {
      debugPrint('CALL WS ALREADY CONNECTED');
      return;
    }

    if (_connecting && _connectCompleter != null) {
      debugPrint('CALL WS CONNECT ALREADY IN PROGRESS');
      return _connectCompleter!.future;
    }

    _connecting = true;
    _connectCompleter = Completer<void>();

    try {
      if (_channel != null) {
        await disconnect(
          clearHandlers: false,
          clearQueue: false,
          clearCache: false,
          forgetUrl: false,
        );
      }

      _url = fixedUrl;

      debugPrint('CALL WS CONNECTING: $fixedUrl');

      final channel = WebSocketChannel.connect(Uri.parse(fixedUrl));
      _channel = channel;

      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (error) {
          debugPrint('CALL WS ERROR: $error');
          _connected = false;
          _channel = null;
          _subscription = null;
        },
        onDone: () {
          debugPrint('CALL WS CLOSED');
          _connected = false;
          _channel = null;
          _subscription = null;
        },
        cancelOnError: false,
      );

      if (_channel != channel) {
        debugPrint('CALL WS CONNECT ABORTED: channel changed');
        return;
      }

      // IMPORTANT FIX:
      // Do not wait for channel.ready before sending call_offer.
      // Waiting here can delay the offer and receiver will fail to connect.
      _connected = true;

      debugPrint('CALL WS CONNECTED EARLY: $fixedUrl');

      _flushPendingMessages();

      channel.ready.then((_) {
        debugPrint('CALL WS READY OK');
      }).catchError((e) {
        debugPrint('CALL WS READY ERROR IGNORED: $e');
      });

      if (!(_connectCompleter?.isCompleted ?? true)) {
        _connectCompleter?.complete();
      }
    } catch (e, stack) {
      debugPrint('CALL WS CONNECT ERROR: $e');
      debugPrint(stack.toString());

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
    } finally {
      _connecting = false;
      _connectCompleter = null;
    }
  }

  Future<void> ensureConnected({String? url}) async {
    final connectUrl = url ?? _url;

    if (_connected && _channel != null) return;

    if (connectUrl == null || connectUrl.trim().isEmpty) {
      debugPrint('CALL WS ENSURE CONNECTED FAILED: URL missing');
      return;
    }

    await connect(url: connectUrl);
  }

  Future<void> _handleMessage(dynamic message) async {
    debugPrint('========================');
    debugPrint('CALL WS RAW: $message');

    try {
      final decoded = jsonDecode(message.toString());

      if (decoded is! Map) {
        debugPrint('CALL WS INVALID DATA');
        return;
      }

      final rawData = Map<String, dynamic>.from(decoded);
      final event =
          rawData['event']?.toString() ?? rawData['type']?.toString();

      if (event == null || event.trim().isEmpty) {
        debugPrint('CALL WS EVENT NULL');
        return;
      }

      final data = _normalizeSocketData(rawData, event);

      debugPrint('CALL WS EVENT: $event');
      debugPrint('CALL WS DATA: $data');
      debugPrint('CALL WS PAYLOAD: ${data['payload']}');

      final payload = data['payload'];

      if (event == CallSocketEvents.callEventSent ||
          data['type'] == CallSocketEvents.callEventSent) {
        String ackType = '';

        if (payload is Map) {
          ackType = payload['sent_event']?.toString() ??
              payload['sentEvent']?.toString() ??
              '';
        }

        ackType = ackType.isNotEmpty
            ? ackType
            : rawData['sent_event']?.toString() ??
                rawData['sentEvent']?.toString() ??
                '';

        debugPrint('CALL WS ACK IGNORED: $ackType');
        return;
      }

      final hasError =
          data['error'] != null || (payload is Map && payload['error'] != null);

      if (hasError) {
        debugPrint(
          'CALL WS BACKEND ERROR: ${data['error'] ?? payload['error']}',
        );
        return;
      }

      if (event == CallSocketEvents.callReady) {
        _handleCallReadyAutoResend(data);
      }

      final handlers = _handlers[event];

      if (handlers != null && handlers.isNotEmpty) {
        debugPrint('CALL WS HANDLER FOUND: $event COUNT: ${handlers.length}');

        for (final handler in List<SocketHandler>.from(handlers)) {
          try {
            await handler(data);
          } catch (e, stack) {
            debugPrint('CALL WS HANDLER ERROR FOR $event: $e');
            debugPrint(stack.toString());
          }
        }
      } else {
        debugPrint('CALL WS NO HANDLER FOR: $event');
      }
    } catch (e, stack) {
      debugPrint('CALL WS PARSE ERROR: $e');
      debugPrint(stack.toString());
    } finally {
      debugPrint('========================');
    }
  }

  Map<String, dynamic> _normalizeSocketData(
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

      if (key == 'event' || key == 'type' || key == 'payload') continue;

      payload.putIfAbsent(key, () => entry.value);
    }

    payload['event'] = event;
    payload['type'] = event;

    _mirror(payload, 'conversation_id', 'conversationId');
    _mirror(payload, 'caller_id', 'callerId');
    _mirror(payload, 'receiver_id', 'receiverId');
    _mirror(payload, 'target_user', 'targetUser');
    _mirror(payload, 'from_user', 'fromUser');
    _mirror(payload, 'is_video_call', 'isVideoCall');
    _mirror(payload, 'caller_name', 'callerName');
    _mirror(payload, 'caller_avatar', 'callerAvatar');
    _mirror(payload, 'call_id', 'callId');
    _mirror(payload, 'sent_event', 'sentEvent');

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

  String? _normalizeOutgoingEvent(String event) {
    switch (event) {
      case CallSocketEvents.callAccept:
        debugPrint(
          'CALL WS NORMALIZED OUTGOING EVENT: call_accept -> call_answer',
        );
        return CallSocketEvents.callAnswer;

      case CallSocketEvents.callJoin:
        debugPrint(
          'CALL WS BLOCKED OUTGOING EVENT: call_join is not supported',
        );
        return null;

      default:
        return event;
    }
  }

  Map<String, dynamic> _normalizeOutgoingPayload(
    String event,
    Map<String, dynamic> payload,
  ) {
    final fixedPayload = Map<String, dynamic>.from(payload);

    _mirror(fixedPayload, 'conversation_id', 'conversationId');
    _mirror(fixedPayload, 'caller_id', 'callerId');
    _mirror(fixedPayload, 'receiver_id', 'receiverId');
    _mirror(fixedPayload, 'target_user', 'targetUser');
    _mirror(fixedPayload, 'from_user', 'fromUser');
    _mirror(fixedPayload, 'is_video_call', 'isVideoCall');
    _mirror(fixedPayload, 'caller_name', 'callerName');
    _mirror(fixedPayload, 'caller_avatar', 'callerAvatar');
    _mirror(fixedPayload, 'call_id', 'callId');
    _mirror(fixedPayload, 'sent_event', 'sentEvent');

    if (fixedPayload['from'] == null && fixedPayload['from_user'] != null) {
      fixedPayload['from'] = fixedPayload['from_user'];
    }

    if (fixedPayload['from_user'] == null && fixedPayload['from'] != null) {
      fixedPayload['from_user'] = fixedPayload['from'];
    }

    if (event == CallSocketEvents.callAnswer &&
        fixedPayload['answer'] == null &&
        fixedPayload['sdp'] != null) {
      fixedPayload['answer'] = {
        'sdp': fixedPayload['sdp'],
        'type': fixedPayload['type'] ?? 'answer',
      };
    }

    if (event == CallSocketEvents.callOffer &&
        fixedPayload['offer'] == null &&
        fixedPayload['sdp'] != null) {
      fixedPayload['offer'] = {
        'sdp': fixedPayload['sdp'],
        'type': fixedPayload['type'] ?? 'offer',
      };
    }

    return fixedPayload;
  }

  void emit(
    String event,
    Map<String, dynamic> payload, {
    String? targetUser,
    String? conversationId,
    bool queueIfDisconnected = true,
  }) {
    final normalizedEvent = _normalizeOutgoingEvent(event);

    if (normalizedEvent == null) return;

    final normalizedPayload = _normalizeOutgoingPayload(
      normalizedEvent,
      payload,
    );

    final fixedTargetUser = targetUser ??
        normalizedPayload['target_user']?.toString() ??
        normalizedPayload['targetUser']?.toString();

    final fixedConversationId = conversationId ??
        normalizedPayload['conversation_id']?.toString() ??
        normalizedPayload['conversationId']?.toString();

    if (normalizedEvent == CallSocketEvents.callOffer) {
      _cacheCallOffer(
        normalizedPayload,
        targetUser: fixedTargetUser,
        conversationId: fixedConversationId,
      );
    }

    if (_channel == null || !_connected) {
      debugPrint('CALL WS NOT CONNECTED: $normalizedEvent');

      if (queueIfDisconnected) {
        _queue(
          normalizedEvent,
          normalizedPayload,
          targetUser: fixedTargetUser,
          conversationId: fixedConversationId,
        );
      }

      return;
    }

    _sendNow(
      normalizedEvent,
      normalizedPayload,
      targetUser: fixedTargetUser,
      conversationId: fixedConversationId,
    );
  }

  void _sendNow(
    String event,
    Map<String, dynamic> payload, {
    String? targetUser,
    String? conversationId,
  }) {
    if (_channel == null || !_connected) {
      debugPrint('CALL WS SEND FAILED NOT CONNECTED: $event');
      return;
    }

    final message = <String, dynamic>{
      'event': event,
      'type': event,
      'payload': payload,
      if (targetUser != null) 'target_user': targetUser,
      if (conversationId != null) 'conversation_id': conversationId,
    };

    try {
      _channel!.sink.add(jsonEncode(message));
      debugPrint('CALL WS SENT: $message');
    } catch (e, stack) {
      debugPrint('CALL WS SEND ERROR: $e');
      debugPrint(stack.toString());
    }
  }

  void _queue(
    String event,
    Map<String, dynamic> payload, {
    String? targetUser,
    String? conversationId,
  }) {
    if (_pendingMessages.length >= 20) {
      _pendingMessages.removeAt(0);
    }

    _pendingMessages.add(
      _PendingSocketMessage(
        event: event,
        payload: payload,
        targetUser: targetUser,
        conversationId: conversationId,
      ),
    );

    debugPrint('CALL WS MESSAGE QUEUED: $event');
  }

  void _flushPendingMessages() {
    if (_pendingMessages.isEmpty) return;
    if (_channel == null || !_connected) return;

    final messages = List<_PendingSocketMessage>.from(_pendingMessages);
    _pendingMessages.clear();

    debugPrint('CALL WS FLUSHING QUEUED MESSAGES: ${messages.length}');

    for (final item in messages) {
      _sendNow(
        item.event,
        item.payload,
        targetUser: item.targetUser,
        conversationId: item.conversationId,
      );
    }
  }

  void _cacheCallOffer(
    Map<String, dynamic> payload, {
    String? targetUser,
    String? conversationId,
  }) {
    final callId =
        payload['call_id']?.toString() ?? payload['callId']?.toString() ?? '';

    final key = _offerKey(
      callId: callId,
      conversationId: conversationId ??
          payload['conversation_id']?.toString() ??
          payload['conversationId']?.toString(),
      targetUser: targetUser ??
          payload['target_user']?.toString() ??
          payload['targetUser']?.toString() ??
          payload['receiver_id']?.toString() ??
          payload['receiverId']?.toString(),
    );

    if (key.isEmpty) {
      debugPrint('CALL WS OFFER CACHE SKIPPED: missing key');
      return;
    }

    _cachedOffers[key] = _CachedOffer(
      payload: Map<String, dynamic>.from(payload),
      targetUser: targetUser,
      conversationId: conversationId,
      createdAt: DateTime.now(),
    );

    debugPrint('CALL WS OFFER CACHED: $key');

    _cleanupOldCachedOffers();
  }

  String _offerKey({
    String? callId,
    String? conversationId,
    String? targetUser,
  }) {
    final c = callId?.trim() ?? '';
    final conv = conversationId?.trim() ?? '';
    final target = targetUser?.trim() ?? '';

    if (c.isNotEmpty && conv.isNotEmpty && target.isNotEmpty) {
      return 'call:$c|conv:$conv|target:$target';
    }

    if (conv.isNotEmpty && target.isNotEmpty) {
      return 'conv:$conv|target:$target';
    }

    if (c.isNotEmpty && target.isNotEmpty) {
      return 'call:$c|target:$target';
    }

    return '';
  }

  void _handleCallReadyAutoResend(Map<String, dynamic> data) {
    final payloadRaw = data['payload'];

    if (payloadRaw is! Map) {
      debugPrint('CALL READY AUTO RESEND FAILED: payload invalid');
      return;
    }

    final payload = Map<String, dynamic>.from(payloadRaw);

    final fromUser = payload['from']?.toString() ??
        payload['from_user']?.toString() ??
        data['from_user']?.toString() ??
        '';

    final conversationId = payload['conversation_id']?.toString() ??
        payload['conversationId']?.toString() ??
        data['conversation_id']?.toString();

    final callId =
        payload['call_id']?.toString() ?? payload['callId']?.toString();

    if (fromUser.trim().isEmpty) {
      debugPrint('CALL READY AUTO RESEND FAILED: fromUser missing');
      return;
    }

    final key1 = _offerKey(
      callId: callId,
      conversationId: conversationId,
      targetUser: fromUser,
    );

    final key2 = _offerKey(
      conversationId: conversationId,
      targetUser: fromUser,
    );

    final cached = _cachedOffers[key1] ?? _cachedOffers[key2];

    if (cached == null) {
      debugPrint('CALL READY RECEIVED BUT NO CACHED OFFER FOUND');
      debugPrint('CALL READY FROM: $fromUser');
      debugPrint('CALL READY CONVERSATION: ${conversationId ?? ''}');
      debugPrint('CALL READY CALL ID: ${callId ?? ''}');
      return;
    }

    final age = DateTime.now().difference(cached.createdAt);

    if (age.inSeconds > 90) {
      debugPrint('CALL READY CACHED OFFER TOO OLD: ${age.inSeconds}s');
      return;
    }

    final offerPayload = Map<String, dynamic>.from(cached.payload);

    if (callId != null && callId.trim().isNotEmpty) {
      offerPayload['call_id'] = callId;
      offerPayload['callId'] = callId;
    }

    final resendKey = key1.isNotEmpty ? key1 : key2;
    final lastResendTime = _lastCallReadyResend[resendKey];

    if (lastResendTime != null) {
      final diff = DateTime.now().difference(lastResendTime).inSeconds;

      if (diff <= 5) {
        debugPrint('CALL READY AUTO RESEND SKIPPED DUPLICATE: $resendKey');
        return;
      }
    }

    _lastCallReadyResend[resendKey] = DateTime.now();

    debugPrint('CALL READY RECEIVED: RESENDING CACHED CALL OFFER');

    emit(
      CallSocketEvents.callOffer,
      offerPayload,
      targetUser: fromUser,
      conversationId: conversationId ?? cached.conversationId,
      queueIfDisconnected: true,
    );
  }

  void _cleanupOldCachedOffers() {
    final now = DateTime.now();

    _cachedOffers.removeWhere((key, value) {
      return now.difference(value.createdAt).inMinutes >= 3;
    });

    _lastCallReadyResend.removeWhere((key, value) {
      return now.difference(value).inMinutes >= 3;
    });
  }

  void on(String event, SocketHandler handler) {
    final normalizedEvent = _normalizeOutgoingEvent(event);

    if (normalizedEvent == null) {
      debugPrint('CALL WS HANDLER NOT REGISTERED: $event is not supported');
      return;
    }

    final list = _handlers.putIfAbsent(normalizedEvent, () => []);

    if (!list.contains(handler)) {
      list.add(handler);
    }

    debugPrint(
      'CALL WS HANDLER REGISTERED: $normalizedEvent COUNT: ${list.length}',
    );
  }

  void off(String event, [SocketHandler? handler]) {
    final normalizedEvent = _normalizeOutgoingEvent(event);

    debugPrint('CALL WS OFF CALLED FOR: $event');

    if (normalizedEvent == null) {
      if (handler == null) {
        debugPrint(
          'CALL WS OFF IGNORED WITHOUT HANDLER: $event. Pass handler to remove one listener.',
        );
        debugPrint(StackTrace.current.toString());
        return;
      }

      _handlers[event]?.remove(handler);

      if (_handlers[event]?.isEmpty ?? false) {
        _handlers.remove(event);
      }

      debugPrint('CALL WS HANDLER REMOVED ONE: $event');
      return;
    }

    if (handler == null) {
      debugPrint(
        'CALL WS OFF IGNORED WITHOUT HANDLER: $normalizedEvent. Pass handler to remove one listener.',
      );
      debugPrint(StackTrace.current.toString());
      return;
    }

    _handlers[normalizedEvent]?.remove(handler);

    if (_handlers[normalizedEvent]?.isEmpty ?? false) {
      _handlers.remove(normalizedEvent);
    }

    debugPrint('CALL WS HANDLER REMOVED ONE: $normalizedEvent');
  }

  void clearHandlers() {
    _handlers.clear();
    debugPrint('CALL WS HANDLERS CLEARED');
  }

  Future<void> reconnect() async {
    final oldUrl = _url;

    if (oldUrl == null || oldUrl.trim().isEmpty) {
      debugPrint('CALL WS RECONNECT FAILED: old url missing');
      return;
    }

    await connect(url: oldUrl);
  }

  Future<void> disconnect({
    bool clearHandlers = false,
    bool clearQueue = true,
    bool clearCache = true,
    bool forgetUrl = true,
  }) async {
    debugPrint('CALL WS DISCONNECT REQUESTED');

    _connected = false;
    _connecting = false;

    final oldSubscription = _subscription;
    final oldChannel = _channel;

    _subscription = null;
    _channel = null;

    if (forgetUrl) {
      _url = null;
    }

    if (!(_connectCompleter?.isCompleted ?? true)) {
      _connectCompleter?.complete();
    }

    _connectCompleter = null;

    try {
      await oldSubscription?.cancel();
    } catch (e) {
      debugPrint('CALL WS SUBSCRIPTION CANCEL ERROR: $e');
    }

    try {
      await oldChannel?.sink.close();
    } catch (e) {
      debugPrint('CALL WS CHANNEL CLOSE ERROR: $e');
    }

    if (clearHandlers) {
      _handlers.clear();
    }

    if (clearQueue) {
      _pendingMessages.clear();
    }

    if (clearCache) {
      _cachedOffers.clear();
      _lastCallReadyResend.clear();
    }

    debugPrint('CALL WS DISCONNECTED');
  }

  void reset() {
    _handlers.clear();
    _pendingMessages.clear();
    _cachedOffers.clear();
    _lastCallReadyResend.clear();
    _connected = false;
    _connecting = false;
    _url = null;
    _channel = null;
    _subscription = null;
    _connectCompleter = null;
    debugPrint('CALL WS RESET');
  }
}