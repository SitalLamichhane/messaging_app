// lib/core/call/call_socket_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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

  @Deprecated('Create and send a real SDP answer with call_answer.')
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
  final String? callId;
  final DateTime createdAt;
  final int priority;

  const _PendingSocketMessage({
    required this.event,
    required this.payload,
    required this.createdAt,
    required this.priority,
    this.targetUser,
    this.conversationId,
    this.callId,
  });
}

class _CachedOffer {
  final Map<String, dynamic> payload;
  final String? targetUser;
  final String? conversationId;
  final String? callId;
  final DateTime createdAt;

  const _CachedOffer({
    required this.payload,
    required this.createdAt,
    this.targetUser,
    this.conversationId,
    this.callId,
  });
}

class SocketService {
  static final SocketService instance = SocketService._internal();
  SocketService._internal();

  static const int _maxPendingMessages = 100;
  static const int _maxReconnectAttempts = 12;
  static const Duration _readyTimeout = Duration(seconds: 8);
  static const Duration _offerCacheLifetime = Duration(seconds: 90);
  static const Duration _closedCallLifetime = Duration(minutes: 5);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  final Map<String, List<SocketHandler>> _handlers =
      <String, List<SocketHandler>>{};
  final List<_PendingSocketMessage> _pendingMessages =
      <_PendingSocketMessage>[];

  final Map<String, _CachedOffer> _cachedOffers = <String, _CachedOffer>{};
  final Map<String, DateTime> _lastCallReadyResend = <String, DateTime>{};
  final Map<String, DateTime> _closedCallIds = <String, DateTime>{};

  bool _connected = false;
  bool _connecting = false;
  bool _manualDisconnect = false;
  bool _autoReconnectEnabled = true;

  String? _url;
  String? _activeCallId;
  String? _activeConversationId;

  int _connectionGeneration = 0;
  int _reconnectAttempt = 0;

  Completer<void>? _connectCompleter;
  Timer? _reconnectTimer;

  bool get isConnected => _connected && _channel != null;
  bool get isConnecting => _connecting;
  String? get currentUrl => _url;
  String? get activeCallId => _activeCallId;
  String? get activeConversationId => _activeConversationId;

  /// Optional but recommended. Call this when a call starts or is accepted.
  /// It lets the socket ignore delayed events from older calls.
  void setActiveCallContext({
    String? callId,
    String? conversationId,
  }) {
    final fixedCallId = callId?.trim() ?? '';
    final fixedConversationId = conversationId?.trim() ?? '';

    _activeCallId = fixedCallId.isEmpty ? null : fixedCallId;
    _activeConversationId =
        fixedConversationId.isEmpty ? null : fixedConversationId;

    if (_activeCallId != null) {
      _closedCallIds.remove(_activeCallId);
    }

    _cleanupState();
  }

  void clearActiveCallContext({String? callId}) {
    final expected = callId?.trim() ?? '';

    if (expected.isNotEmpty &&
        _activeCallId != null &&
        _activeCallId != expected) {
      return;
    }

    _activeCallId = null;
    _activeConversationId = null;
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

  Future<void> connect({
    required String url,
    bool autoReconnect = true,
  }) async {
    final fixedUrl = _sanitizeWsUrl(url);

    if (fixedUrl.isEmpty) {
      debugPrint('CALL WS CONNECT ERROR: URL empty');
      return;
    }

    if (isConnected && _url == fixedUrl) {
      debugPrint('CALL WS ALREADY CONNECTED');
      return;
    }

    if (_connecting && _connectCompleter != null) {
      debugPrint('CALL WS CONNECT ALREADY IN PROGRESS');
      return _connectCompleter!.future;
    }

    _manualDisconnect = false;
    _autoReconnectEnabled = autoReconnect;
    _url = fixedUrl;
    _connecting = true;
    _connectCompleter = Completer<void>();

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final generation = ++_connectionGeneration;

    try {
      await _closeTransport(invalidateGeneration: false);

      debugPrint('CALL WS CONNECTING');

      final channel = WebSocketChannel.connect(Uri.parse(fixedUrl));
      _channel = channel;

      _subscription = channel.stream.listen(
        (message) => _handleMessage(message, generation),
        onError: (Object error, StackTrace stackTrace) {
          _handleTransportClosed(
            generation: generation,
            reason: 'socket error: $error',
          );
        },
        onDone: () {
          _handleTransportClosed(
            generation: generation,
            reason: 'socket closed',
          );
        },
        cancelOnError: false,
      );

      await channel.ready.timeout(_readyTimeout);

      if (generation != _connectionGeneration || _channel != channel) {
        debugPrint('CALL WS CONNECT ABORTED: stale connection');
        try {
          await channel.sink.close();
        } catch (_) {}
        return;
      }

      _connected = true;
      _reconnectAttempt = 0;

      debugPrint('CALL WS CONNECTED');

      _flushPendingMessages();
    } on TimeoutException {
      debugPrint('CALL WS CONNECT ERROR: ready timeout');
      await _failCurrentConnection(generation);
      if (generation == _connectionGeneration) {
        _connecting = false;
      }
      _scheduleReconnect();
    } catch (error, stackTrace) {
      debugPrint('CALL WS CONNECT ERROR: $error');
      if (kDebugMode) {
        debugPrint(stackTrace.toString());
      }

      await _failCurrentConnection(generation);
      if (generation == _connectionGeneration) {
        _connecting = false;
      }
      _scheduleReconnect();
    } finally {
      if (generation == _connectionGeneration) {
        _connecting = false;
      }

      if (!(_connectCompleter?.isCompleted ?? true)) {
        _connectCompleter?.complete();
      }

      _connectCompleter = null;
    }
  }

  Future<void> ensureConnected({String? url}) async {
    if (isConnected) return;

    final connectUrl = url ?? _url;

    if (connectUrl == null || connectUrl.trim().isEmpty) {
      debugPrint('CALL WS ENSURE CONNECTED FAILED: URL missing');
      return;
    }

    await connect(
      url: connectUrl,
      autoReconnect: _autoReconnectEnabled,
    );
  }

  Future<void> reconnect() async {
    final reconnectUrl = _url;

    if (reconnectUrl == null || reconnectUrl.trim().isEmpty) {
      debugPrint('CALL WS RECONNECT FAILED: URL missing');
      return;
    }

    _manualDisconnect = false;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await connect(
      url: reconnectUrl,
      autoReconnect: true,
    );
  }

  Future<void> _handleMessage(dynamic message, int generation) async {
    if (generation != _connectionGeneration) return;

    try {
      final decoded = jsonDecode(message.toString());

      if (decoded is! Map) {
        debugPrint('CALL WS INVALID DATA');
        return;
      }

      final rawData = Map<String, dynamic>.from(decoded);
      final event =
          rawData['event']?.toString() ?? rawData['type']?.toString() ?? '';

      if (event.trim().isEmpty) {
        debugPrint('CALL WS EVENT MISSING');
        return;
      }

      final data = _normalizeSocketData(rawData, event);
      final payload = _payloadOf(data);

      if (event == CallSocketEvents.callEventSent ||
          data['type'] == CallSocketEvents.callEventSent) {
        debugPrint('CALL WS ACK RECEIVED');
        return;
      }

      final errorValue = data['error'] ?? payload['error'];
      if (errorValue != null) {
        debugPrint('CALL WS BACKEND ERROR: $errorValue');
        return;
      }

      final incomingCallId = _extractCallId(payload);
      final incomingConversationId = _extractConversationId(payload);

      if (_shouldIgnoreIncomingEvent(
        event: event,
        callId: incomingCallId,
        conversationId: incomingConversationId,
      )) {
        debugPrint('CALL WS IGNORED STALE EVENT: $event');
        return;
      }

      if (_activeCallId == null &&
          (event == CallSocketEvents.callOffer ||
              event == CallSocketEvents.callAnswer)) {
        setActiveCallContext(
          callId: incomingCallId,
          conversationId: incomingConversationId,
        );
      }

      if (event == CallSocketEvents.callReady) {
        _handleCallReadyAutoResend(data);
      }

      if (event == CallSocketEvents.callAnswer) {
        _clearOfferCache(
          callId: incomingCallId,
          conversationId: incomingConversationId,
        );
      }

      if (_isTerminalEvent(event)) {
        _markCallClosed(incomingCallId);
        _clearOfferCache(
          callId: incomingCallId,
          conversationId: incomingConversationId,
        );
      }

      debugPrint('CALL WS EVENT RECEIVED: $event');

      final handlers = _handlers[event];

      if (handlers == null || handlers.isEmpty) {
        debugPrint('CALL WS NO HANDLER FOR: $event');
        return;
      }

      for (final handler in List<SocketHandler>.from(handlers)) {
        try {
          await handler(data);
        } catch (error, stackTrace) {
          debugPrint('CALL WS HANDLER ERROR FOR $event: $error');
          if (kDebugMode) {
            debugPrint(stackTrace.toString());
          }
        }
      }
    } catch (error, stackTrace) {
      debugPrint('CALL WS PARSE ERROR: $error');
      if (kDebugMode) {
        debugPrint(stackTrace.toString());
      }
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
    final payload = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : <String, dynamic>{};

    for (final entry in data.entries) {
      final key = entry.key;
      if (key == 'event' || key == 'type' || key == 'payload') continue;
      payload.putIfAbsent(key, () => entry.value);
    }

    payload['event'] = event;
    payload['socket_event'] = event;
    payload.putIfAbsent('type', () => event);

    if (event == CallSocketEvents.callOffer ||
        event == CallSocketEvents.callRenegotiateOffer) {
      final rawOffer = payload['offer'];
      if (rawOffer is Map) {
        final offer = Map<String, dynamic>.from(rawOffer);
        if ((offer['sdp']?.toString().trim() ?? '').isNotEmpty) {
          offer['type'] = 'offer';
          payload['offer'] = offer;
        }
      } else if ((payload['sdp']?.toString().trim() ?? '').isNotEmpty) {
        payload['type'] = 'offer';
      }
    }

    if (event == CallSocketEvents.callAnswer ||
        event == CallSocketEvents.callRenegotiateAnswer) {
      final rawAnswer = payload['answer'];
      if (rawAnswer is Map) {
        final answer = Map<String, dynamic>.from(rawAnswer);
        if ((answer['sdp']?.toString().trim() ?? '').isNotEmpty) {
          answer['type'] = 'answer';
          payload['answer'] = answer;
        }
      } else if ((payload['sdp']?.toString().trim() ?? '').isNotEmpty) {
        payload['type'] = 'answer';
      }
    }

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

  Map<String, dynamic> _payloadOf(Map<String, dynamic> data) {
    final rawPayload = data['payload'];
    if (rawPayload is Map) {
      return Map<String, dynamic>.from(rawPayload);
    }
    return <String, dynamic>{};
  }

  void _mirror(Map<String, dynamic> map, String snake, String camel) {
    if (map[snake] == null && map[camel] != null) {
      map[snake] = map[camel];
    }

    if (map[camel] == null && map[snake] != null) {
      map[camel] = map[snake];
    }
  }

  String? _normalizeOutgoingEvent(
    String event,
    Map<String, dynamic> payload,
  ) {
    switch (event) {
      case CallSocketEvents.callAccept:
        if (!_containsValidAnswer(payload)) {
          debugPrint(
            'CALL WS BLOCKED: call_accept has no valid SDP answer. '
            'Create the WebRTC answer first and emit call_answer.',
          );
          return null;
        }

        debugPrint('CALL WS NORMALIZED: call_accept -> call_answer');
        return CallSocketEvents.callAnswer;

      case CallSocketEvents.callJoin:
        debugPrint('CALL WS BLOCKED: call_join is not supported');
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

    if (event == CallSocketEvents.callAnswer ||
        event == CallSocketEvents.callRenegotiateAnswer) {
      final rawAnswer = fixedPayload['answer'];

      if (rawAnswer is Map) {
        final answer = Map<String, dynamic>.from(rawAnswer);
        if ((answer['sdp']?.toString().trim() ?? '').isNotEmpty) {
          answer['type'] = 'answer';
          fixedPayload['answer'] = answer;
        }
      } else if (fixedPayload['sdp'] != null) {
        fixedPayload['answer'] = <String, dynamic>{
          'sdp': fixedPayload['sdp'],
          'type': 'answer',
        };
      }
    }

    if (event == CallSocketEvents.callOffer ||
        event == CallSocketEvents.callRenegotiateOffer) {
      final rawOffer = fixedPayload['offer'];

      if (rawOffer is Map) {
        final offer = Map<String, dynamic>.from(rawOffer);
        if ((offer['sdp']?.toString().trim() ?? '').isNotEmpty) {
          offer['type'] = 'offer';
          fixedPayload['offer'] = offer;
        }
      } else if (fixedPayload['sdp'] != null) {
        fixedPayload['offer'] = <String, dynamic>{
          'sdp': fixedPayload['sdp'],
          'type': 'offer',
        };
      }
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
    final normalizedEvent = _normalizeOutgoingEvent(event, payload);
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

    final callId = _extractCallId(normalizedPayload);

    if (_isCallClosed(callId) && !_isTerminalEvent(normalizedEvent)) {
      debugPrint('CALL WS DROPPED EVENT FOR CLOSED CALL: $normalizedEvent');
      return;
    }

    if (normalizedEvent == CallSocketEvents.callOffer) {
      if (!_containsValidOffer(normalizedPayload)) {
        debugPrint('CALL WS BLOCKED INVALID CALL OFFER');
        return;
      }

      _cacheCallOffer(
        normalizedPayload,
        targetUser: fixedTargetUser,
        conversationId: fixedConversationId,
      );
    }

    if (normalizedEvent == CallSocketEvents.callAnswer &&
        !_containsValidAnswer(normalizedPayload)) {
      debugPrint('CALL WS BLOCKED INVALID CALL ANSWER');
      return;
    }

    if (normalizedEvent == CallSocketEvents.callOffer ||
        normalizedEvent == CallSocketEvents.callAnswer) {
      setActiveCallContext(
        callId: callId,
        conversationId: fixedConversationId,
      );
    }

    if (_isTerminalEvent(normalizedEvent)) {
      _markCallClosed(callId);
      _clearOfferCache(
        callId: callId,
        conversationId: fixedConversationId,
      );
    }

    if (!isConnected) {
      debugPrint('CALL WS NOT CONNECTED: $normalizedEvent');

      if (queueIfDisconnected) {
        _queue(
          normalizedEvent,
          normalizedPayload,
          targetUser: fixedTargetUser,
          conversationId: fixedConversationId,
        );

        if (!_connecting && !_manualDisconnect && _url != null) {
          _scheduleReconnect(immediate: true);
        }
      }

      return;
    }

    _sendNow(
      normalizedEvent,
      normalizedPayload,
      targetUser: fixedTargetUser,
      conversationId: fixedConversationId,
      requeueOnFailure: queueIfDisconnected,
    );
  }

  void _sendNow(
    String event,
    Map<String, dynamic> payload, {
    String? targetUser,
    String? conversationId,
    bool requeueOnFailure = true,
  }) {
    if (!isConnected || _channel == null) {
      if (requeueOnFailure) {
        _queue(
          event,
          payload,
          targetUser: targetUser,
          conversationId: conversationId,
        );
      }
      return;
    }

    final fixedPayload = Map<String, dynamic>.from(payload);

    if (targetUser != null && targetUser.trim().isNotEmpty) {
      fixedPayload['target_user'] = targetUser;
      fixedPayload['targetUser'] = targetUser;
      fixedPayload['receiver_id'] = targetUser;
      fixedPayload['receiverId'] = targetUser;
    }

    if (conversationId != null && conversationId.trim().isNotEmpty) {
      fixedPayload['conversation_id'] = conversationId;
      fixedPayload['conversationId'] = conversationId;
    }

    final message = <String, dynamic>{
      'event': event,
      'type': event,
      'payload': fixedPayload,
      if (targetUser != null && targetUser.trim().isNotEmpty)
        'target_user': targetUser,
      if (conversationId != null && conversationId.trim().isNotEmpty)
        'conversation_id': conversationId,
    };

    try {
      _channel!.sink.add(jsonEncode(message));
      debugPrint('CALL WS SENT EVENT: $event');
    } catch (error, stackTrace) {
      debugPrint('CALL WS SEND ERROR FOR $event: $error');
      if (kDebugMode) {
        debugPrint(stackTrace.toString());
      }

      _connected = false;

      if (requeueOnFailure) {
        _queue(
          event,
          payload,
          targetUser: targetUser,
          conversationId: conversationId,
        );
      }

      _scheduleReconnect(immediate: true);
    }
  }

  void _queue(
    String event,
    Map<String, dynamic> payload, {
    String? targetUser,
    String? conversationId,
  }) {
    _cleanupPendingMessages();

    final callId = _extractCallId(payload);
    final candidateKey = event == CallSocketEvents.iceCandidate
        ? _iceCandidateKey(payload)
        : null;

    if (candidateKey != null && candidateKey.isNotEmpty) {
      final duplicate = _pendingMessages.any((item) {
        return item.event == CallSocketEvents.iceCandidate &&
            item.callId == callId &&
            _iceCandidateKey(item.payload) == candidateKey;
      });

      if (duplicate) {
        debugPrint('CALL WS DUPLICATE ICE CANDIDATE SKIPPED');
        return;
      }
    }

    if (event == CallSocketEvents.callOffer ||
        event == CallSocketEvents.callAnswer ||
        event == CallSocketEvents.callReady) {
      _pendingMessages.removeWhere((item) {
        return item.event == event &&
            item.callId == callId &&
            item.conversationId == conversationId;
      });
    }

    while (_pendingMessages.length >= _maxPendingMessages) {
      final removableIndex = _findLowestPriorityMessageIndex();
      _pendingMessages.removeAt(removableIndex);
    }

    _pendingMessages.add(
      _PendingSocketMessage(
        event: event,
        payload: Map<String, dynamic>.from(payload),
        targetUser: targetUser,
        conversationId: conversationId,
        callId: callId,
        createdAt: DateTime.now(),
        priority: _eventPriority(event),
      ),
    );

    debugPrint('CALL WS MESSAGE QUEUED: $event');
  }

  int _findLowestPriorityMessageIndex() {
    if (_pendingMessages.isEmpty) return 0;

    var selectedIndex = 0;
    var selectedPriority = _pendingMessages.first.priority;

    for (var i = 1; i < _pendingMessages.length; i++) {
      final priority = _pendingMessages[i].priority;

      if (priority > selectedPriority) {
        selectedIndex = i;
        selectedPriority = priority;
      }
    }

    return selectedIndex;
  }

  int _eventPriority(String event) {
    if (event == CallSocketEvents.callOffer ||
        event == CallSocketEvents.callAnswer ||
        event == CallSocketEvents.callRenegotiateOffer ||
        event == CallSocketEvents.callRenegotiateAnswer) {
      return 0;
    }

    if (_isTerminalEvent(event) || event == CallSocketEvents.incomingCall) {
      return 1;
    }

    if (event == CallSocketEvents.callReady ||
        event == CallSocketEvents.callVideoToggle ||
        event == CallSocketEvents.callVideoUpgradeRejected) {
      return 2;
    }

    return 3;
  }

  Duration _messageLifetime(String event) {
    if (event == CallSocketEvents.iceCandidate) {
      return const Duration(seconds: 20);
    }

    if (event == CallSocketEvents.callReady) {
      return const Duration(seconds: 15);
    }

    if (event == CallSocketEvents.callOffer ||
        event == CallSocketEvents.callAnswer ||
        event == CallSocketEvents.callRenegotiateOffer ||
        event == CallSocketEvents.callRenegotiateAnswer) {
      return const Duration(seconds: 35);
    }

    if (_isTerminalEvent(event)) {
      return const Duration(seconds: 60);
    }

    return const Duration(seconds: 30);
  }

  void _cleanupPendingMessages() {
    final now = DateTime.now();

    _pendingMessages.removeWhere((item) {
      final stale = now.difference(item.createdAt) > _messageLifetime(item.event);
      final closed = _isCallClosed(item.callId) && !_isTerminalEvent(item.event);
      final wrongCall = _activeCallId != null &&
          item.callId != null &&
          item.callId!.isNotEmpty &&
          item.callId != _activeCallId;

      return stale || closed || wrongCall;
    });
  }

  void _flushPendingMessages() {
    if (_pendingMessages.isEmpty || !isConnected) return;

    _cleanupPendingMessages();

    final messages = List<_PendingSocketMessage>.from(_pendingMessages)
      ..sort((a, b) {
        final byPriority = a.priority.compareTo(b.priority);
        if (byPriority != 0) return byPriority;
        return a.createdAt.compareTo(b.createdAt);
      });

    _pendingMessages.clear();

    debugPrint('CALL WS FLUSHING MESSAGES: ${messages.length}');

    for (final item in messages) {
      if (!isConnected) {
        _pendingMessages.add(item);
        continue;
      }

      _sendNow(
        item.event,
        item.payload,
        targetUser: item.targetUser,
        conversationId: item.conversationId,
        requeueOnFailure: true,
      );
    }
  }

  void _cacheCallOffer(
    Map<String, dynamic> payload, {
    String? targetUser,
    String? conversationId,
  }) {
    final callId = _extractCallId(payload);

    final key = _offerKey(
      callId: callId,
      conversationId: conversationId ?? _extractConversationId(payload),
      targetUser: targetUser ?? _extractTargetUser(payload),
    );

    if (key.isEmpty) {
      debugPrint('CALL WS OFFER CACHE SKIPPED: missing key');
      return;
    }

    _cachedOffers[key] = _CachedOffer(
      payload: Map<String, dynamic>.from(payload),
      targetUser: targetUser,
      conversationId: conversationId,
      callId: callId,
      createdAt: DateTime.now(),
    );

    debugPrint('CALL WS OFFER CACHED');
    _cleanupState();
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
    final payload = _payloadOf(data);

    final fromUser = payload['from']?.toString() ??
        payload['from_user']?.toString() ??
        data['from_user']?.toString() ??
        '';

    final conversationId = _extractConversationId(payload) ??
        data['conversation_id']?.toString();
    final callId = _extractCallId(payload);

    if (fromUser.trim().isEmpty) {
      debugPrint('CALL READY AUTO RESEND FAILED: sender missing');
      return;
    }

    if (_isCallClosed(callId)) {
      debugPrint('CALL READY IGNORED FOR CLOSED CALL');
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
      debugPrint('CALL READY RECEIVED WITHOUT CACHED OFFER');
      return;
    }

    final age = DateTime.now().difference(cached.createdAt);
    if (age > _offerCacheLifetime) {
      _cachedOffers.remove(key1);
      _cachedOffers.remove(key2);
      debugPrint('CALL READY CACHED OFFER EXPIRED');
      return;
    }

    final resendKey = key1.isNotEmpty ? key1 : key2;
    final lastResend = _lastCallReadyResend[resendKey];

    if (lastResend != null &&
        DateTime.now().difference(lastResend) <= const Duration(seconds: 5)) {
      debugPrint('CALL READY DUPLICATE RESEND SKIPPED');
      return;
    }

    _lastCallReadyResend[resendKey] = DateTime.now();

    final offerPayload = Map<String, dynamic>.from(cached.payload);

    if (callId != null && callId.trim().isNotEmpty) {
      offerPayload['call_id'] = callId;
      offerPayload['callId'] = callId;
    }

    debugPrint('CALL READY RECEIVED: RESENDING OFFER');

    emit(
      CallSocketEvents.callOffer,
      offerPayload,
      targetUser: fromUser,
      conversationId: conversationId ?? cached.conversationId,
      queueIfDisconnected: true,
    );
  }

  void _clearOfferCache({
    String? callId,
    String? conversationId,
  }) {
    final fixedCallId = callId?.trim() ?? '';
    final fixedConversationId = conversationId?.trim() ?? '';

    _cachedOffers.removeWhere((key, value) {
      if (fixedCallId.isNotEmpty) {
        return value.callId == fixedCallId;
      }

      return fixedConversationId.isNotEmpty &&
          value.conversationId == fixedConversationId;
    });

    _lastCallReadyResend.removeWhere((key, value) {
      if (fixedCallId.isNotEmpty) {
        return key.contains('call:$fixedCallId');
      }

      return fixedConversationId.isNotEmpty &&
          key.contains('conv:$fixedConversationId');
    });
  }

  bool _containsValidOffer(Map<String, dynamic> payload) {
    final rawOffer = payload['offer'];

    if (rawOffer is Map) {
      final offer = Map<String, dynamic>.from(rawOffer);
      final sdp = offer['sdp']?.toString().trim() ?? '';
      final type = offer['type']?.toString().trim() ?? '';
      if (sdp.isNotEmpty && type.isNotEmpty) return true;
    }

    final sdp = payload['sdp']?.toString().trim() ?? '';
    final type = payload['type']?.toString().trim() ?? '';
    return sdp.isNotEmpty && (type == 'offer' || type.isNotEmpty);
  }

  bool _containsValidAnswer(Map<String, dynamic> payload) {
    final rawAnswer = payload['answer'];

    if (rawAnswer is Map) {
      final answer = Map<String, dynamic>.from(rawAnswer);
      final sdp = answer['sdp']?.toString().trim() ?? '';
      final type = answer['type']?.toString().trim() ?? '';
      if (sdp.isNotEmpty && type.isNotEmpty) return true;
    }

    final sdp = payload['sdp']?.toString().trim() ?? '';
    final type = payload['type']?.toString().trim() ?? '';
    return sdp.isNotEmpty && (type == 'answer' || type.isNotEmpty);
  }

  String? _extractCallId(Map<String, dynamic> payload) {
    final value = payload['call_id']?.toString() ??
        payload['callId']?.toString() ??
        '';
    return value.trim().isEmpty ? null : value.trim();
  }

  String? _extractConversationId(Map<String, dynamic> payload) {
    final value = payload['conversation_id']?.toString() ??
        payload['conversationId']?.toString() ??
        '';
    return value.trim().isEmpty ? null : value.trim();
  }

  String? _extractTargetUser(Map<String, dynamic> payload) {
    final value = payload['target_user']?.toString() ??
        payload['targetUser']?.toString() ??
        payload['receiver_id']?.toString() ??
        payload['receiverId']?.toString() ??
        '';
    return value.trim().isEmpty ? null : value.trim();
  }

  String? _iceCandidateKey(Map<String, dynamic> payload) {
    final rawCandidate = payload['candidate'];

    if (rawCandidate is Map) {
      final candidate = Map<String, dynamic>.from(rawCandidate);
      return '${candidate['candidate'] ?? ''}|'
          '${candidate['sdpMid'] ?? candidate['sdp_mid'] ?? ''}|'
          '${candidate['sdpMLineIndex'] ?? candidate['sdp_mline_index'] ?? ''}';
    }

    final candidateText = rawCandidate?.toString() ?? '';
    if (candidateText.trim().isEmpty) return null;
    return candidateText.trim();
  }

  bool _isTerminalEvent(String event) {
    return event == CallSocketEvents.callReject ||
        event == CallSocketEvents.callEnd ||
        event == CallSocketEvents.callLeave ||
        event == CallSocketEvents.callBusy ||
        event == CallSocketEvents.callTimeout;
  }

  void _markCallClosed(String? callId) {
    final fixedCallId = callId?.trim() ?? '';
    if (fixedCallId.isEmpty) return;

    _closedCallIds[fixedCallId] = DateTime.now();

    _pendingMessages.removeWhere((item) {
      return item.callId == fixedCallId && !_isTerminalEvent(item.event);
    });

    if (_activeCallId == fixedCallId) {
      clearActiveCallContext(callId: fixedCallId);
    }
  }

  bool _isCallClosed(String? callId) {
    final fixedCallId = callId?.trim() ?? '';
    if (fixedCallId.isEmpty) return false;

    final closedAt = _closedCallIds[fixedCallId];
    if (closedAt == null) return false;

    if (DateTime.now().difference(closedAt) > _closedCallLifetime) {
      _closedCallIds.remove(fixedCallId);
      return false;
    }

    return true;
  }

  bool _shouldIgnoreIncomingEvent({
    required String event,
    required String? callId,
    required String? conversationId,
  }) {
    if (event == CallSocketEvents.incomingCall) {
      return false;
    }

    if (_isCallClosed(callId) && !_isTerminalEvent(event)) {
      return true;
    }

    if (_activeCallId != null &&
        callId != null &&
        callId.isNotEmpty &&
        callId != _activeCallId) {
      return true;
    }

    if (_activeCallId == null &&
        _activeConversationId != null &&
        conversationId != null &&
        conversationId.isNotEmpty &&
        conversationId != _activeConversationId) {
      return true;
    }

    return false;
  }

  void on(String event, SocketHandler handler) {
    final normalizedEvent = event == CallSocketEvents.callAccept
        ? CallSocketEvents.callAnswer
        : event;

    if (normalizedEvent == CallSocketEvents.callJoin) {
      debugPrint('CALL WS HANDLER NOT REGISTERED: call_join unsupported');
      return;
    }

    final handlers = _handlers.putIfAbsent(
      normalizedEvent,
      () => <SocketHandler>[],
    );

    if (!handlers.contains(handler)) {
      handlers.add(handler);
    }

    debugPrint(
      'CALL WS HANDLER REGISTERED: $normalizedEvent '
      'COUNT: ${handlers.length}',
    );
  }

  /// Passing no handler now removes every handler for that event.
  void off(String event, [SocketHandler? handler]) {
    final normalizedEvent = event == CallSocketEvents.callAccept
        ? CallSocketEvents.callAnswer
        : event;

    if (handler == null) {
      _handlers.remove(normalizedEvent);
      debugPrint('CALL WS ALL HANDLERS REMOVED: $normalizedEvent');
      return;
    }

    _handlers[normalizedEvent]?.remove(handler);

    if (_handlers[normalizedEvent]?.isEmpty ?? false) {
      _handlers.remove(normalizedEvent);
    }

    debugPrint('CALL WS HANDLER REMOVED: $normalizedEvent');
  }

  void clearHandlers() {
    _handlers.clear();
    debugPrint('CALL WS HANDLERS CLEARED');
  }

  Future<void> disconnect({
    bool clearHandlers = false,
    bool clearQueue = true,
    bool clearCache = true,
    bool forgetUrl = true,
  }) async {
    debugPrint('CALL WS DISCONNECT REQUESTED');

    _manualDisconnect = true;
    _autoReconnectEnabled = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;

    ++_connectionGeneration;

    await _closeTransport(invalidateGeneration: false);

    if (forgetUrl) {
      _url = null;
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
      _closedCallIds.clear();
    }

    clearActiveCallContext();

    if (!(_connectCompleter?.isCompleted ?? true)) {
      _connectCompleter?.complete();
    }

    _connectCompleter = null;

    debugPrint('CALL WS DISCONNECTED');
  }

  void reset() {
    _manualDisconnect = true;
    _autoReconnectEnabled = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    ++_connectionGeneration;

    final oldSubscription = _subscription;
    final oldChannel = _channel;

    _subscription = null;
    _channel = null;
    _connected = false;
    _connecting = false;
    _url = null;
    _reconnectAttempt = 0;

    _handlers.clear();
    _pendingMessages.clear();
    _cachedOffers.clear();
    _lastCallReadyResend.clear();
    _closedCallIds.clear();

    _activeCallId = null;
    _activeConversationId = null;

    if (!(_connectCompleter?.isCompleted ?? true)) {
      _connectCompleter?.complete();
    }
    _connectCompleter = null;

    unawaited(oldSubscription?.cancel());
    try {
      oldChannel?.sink.close();
    } catch (_) {}

    debugPrint('CALL WS RESET');
  }

  Future<void> _closeTransport({required bool invalidateGeneration}) async {
    if (invalidateGeneration) {
      ++_connectionGeneration;
    }

    _connected = false;

    final oldSubscription = _subscription;
    final oldChannel = _channel;

    _subscription = null;
    _channel = null;

    try {
      await oldSubscription?.cancel();
    } catch (error) {
      debugPrint('CALL WS SUBSCRIPTION CLOSE ERROR: $error');
    }

    try {
      await oldChannel?.sink.close();
    } catch (error) {
      debugPrint('CALL WS CHANNEL CLOSE ERROR: $error');
    }
  }

  Future<void> _failCurrentConnection(int generation) async {
    if (generation != _connectionGeneration) return;
    _connected = false;
    await _closeTransport(invalidateGeneration: false);
  }

  void _handleTransportClosed({
    required int generation,
    required String reason,
  }) {
    if (generation != _connectionGeneration) return;

    debugPrint('CALL WS TRANSPORT CLOSED: $reason');

    _connected = false;
    _channel = null;
    _subscription = null;

    if (!_manualDisconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect({bool immediate = false}) {
    if (_manualDisconnect || !_autoReconnectEnabled) return;
    if (_url == null || _url!.trim().isEmpty) return;
    if (_connecting || isConnected) return;
    if (_reconnectTimer?.isActive ?? false) return;

    if (_reconnectAttempt >= _maxReconnectAttempts) {
      debugPrint('CALL WS RECONNECT STOPPED: maximum attempts reached');
      return;
    }

    final attempt = _reconnectAttempt++;
    final delaySeconds = immediate
        ? 0
        : math.min(15, math.max(1, math.pow(2, attempt).toInt())).toInt();

    debugPrint(
      'CALL WS RECONNECT SCHEDULED: attempt ${attempt + 1}, '
      'delay ${delaySeconds}s',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _reconnectTimer = null;

      final reconnectUrl = _url;
      if (reconnectUrl == null || _manualDisconnect) return;

      await connect(
        url: reconnectUrl,
        autoReconnect: true,
      );
    });
  }

  void _cleanupState() {
    final now = DateTime.now();

    _cachedOffers.removeWhere((key, value) {
      return now.difference(value.createdAt) > _offerCacheLifetime;
    });

    _lastCallReadyResend.removeWhere((key, value) {
      return now.difference(value) > const Duration(minutes: 3);
    });

    _closedCallIds.removeWhere((key, value) {
      return now.difference(value) > _closedCallLifetime;
    });

    _cleanupPendingMessages();
  }
}
