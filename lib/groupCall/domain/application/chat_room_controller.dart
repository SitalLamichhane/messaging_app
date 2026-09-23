import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hiddenly/groupChat/domain/chat_message_model.dart';
import 'package:hiddenly/realtime/realtime_service.dart';
import 'package:image_picker/image_picker.dart';

import '../data/chat_api_service.dart';

class ChatRoomController extends ChangeNotifier {
  final int conversationId;
  final int currentUserId;

  final ChatApiService api;
  final ConversationRealtimeService realtime;

  final List<ChatMessageDto> _messages =
      <ChatMessageDto>[];

  StreamSubscription<ConversationRealtimeEvent>?
      _realtimeSubscription;

  bool _loading = false;
  bool _sending = false;
  bool _initializing = false;
  bool _initialized = false;
  bool _disposed = false;

  String? _error;

  ChatRoomController({
    required this.conversationId,
    required this.currentUserId,
    required this.api,
    required this.realtime,
  });

  List<ChatMessageDto> get messages =>
      List.unmodifiable(_messages);

  bool get loading => _loading;

  bool get sending => _sending;

  bool get initialized => _initialized;

  String? get error => _error;

  // ============================================================
  // NOTIFY
  // ============================================================

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    if (_disposed ||
        _initializing ||
        _initialized) {
      return;
    }

    _initializing = true;
    _error = null;

    try {
      await _realtimeSubscription?.cancel();

      if (_disposed) return;

      /*
       * Subscribe BEFORE connect/load.
       *
       * This avoids losing websocket messages while
       * the REST message history is loading.
       */
      _realtimeSubscription =
          realtime.events.listen(
        _onRealtimeEvent,
        onError: (Object error) {
          debugPrint(
            '[CHAT ROOM] realtime error: $error',
          );
        },
      );

      await realtime.connect(
        conversationId,
      );

      if (_disposed) return;

      await loadMessages();

      if (_disposed) return;

      /*
       * Mark the conversation as read after the
       * history has been loaded.
       */
      await api.markConversationRead(
        conversationId,
      );

      if (_disposed) return;

      /*
       * Also mark loaded incoming messages locally.
       *
       * The backend websocket receipt should eventually
       * update the sender's copy.
       */
      _markIncomingMessagesSeenLocally();

      _initialized = true;
      _safeNotify();
    } catch (error) {
      if (_disposed) return;

      _error = error.toString();

      debugPrint(
        '[CHAT ROOM] initialize failed: $error',
      );

      _safeNotify();
    } finally {
      _initializing = false;
    }
  }

  // ============================================================
  // LOAD MESSAGES
  // ============================================================

  Future<void> loadMessages() async {
    if (_disposed) return;

    _loading = true;
    _error = null;

    _safeNotify();

    try {
      final loaded =
          await api.loadMessages(
        conversationId,
      );

      if (_disposed) return;

      /*
       * Existing realtime messages are kept.
       *
       * IMPORTANT:
       * Start with existing messages, then apply the
       * server result.
       *
       * This means newer server state such as:
       *
       * delivered=true
       * seen=true
       * isDeleted=true
       * isEdited=true
       *
       * is not overwritten by an older local object.
       */
      final combined =
          <int, ChatMessageDto>{};

      for (final message in _messages) {
        if (message.id > 0) {
          combined[message.id] =
              message;
        }
      }

      for (final message in loaded) {
        if (message.id <= 0) {
          continue;
        }

        final existing =
            combined[message.id];

        combined[message.id] =
            existing == null
                ? message
                : _mergeMessages(
                    existing,
                    message,
                  );
      }

      _messages
        ..clear()
        ..addAll(combined.values);

      _sortMessages();
    } catch (error) {
      if (!_disposed) {
        _error = error.toString();
      }
    } finally {
      if (!_disposed) {
        _loading = false;
        _safeNotify();
      }
    }
  }

  // ============================================================
  // SEND TEXT
  // ============================================================

  Future<void> sendText(
  String text,
) async {
  final value = text.trim();

  if (_disposed ||
      value.isEmpty ||
      _sending) {
    return;
  }

  _sending = true;
  _error = null;
  _safeNotify();

  try {
    // initialize() already connects this realtime socket.
    if (!realtime.connected ||
        realtime.conversationId != conversationId) {
      throw StateError(
        'Conversation websocket is not connected.',
      );
    }

    await realtime.sendJson({
      'action': 'send_message',
      'text': value,
      'message_type': 'text',
    });

    debugPrint(
      '[CHAT ROOM] text sent through websocket: $value',
    );

    // Don't insert locally.
    // Django saves it and broadcasts the real message
    // back with its database ID.
  } catch (error) {
    if (!_disposed) {
      _error = error.toString();
    }

    debugPrint(
      '[CHAT ROOM] websocket text send failed: $error',
    );

    rethrow;
  } finally {
    if (!_disposed) {
      _sending = false;
      _safeNotify();
    }
  }
}

  Future<void> sendLike() {
    return sendText('👍');
  }

  // ============================================================
  // IMAGES
  // ============================================================

  Future<void> sendImages(
    List<XFile> files, {
    String text = '',
  }) {
    return sendMedia(
      files,
      text: text,
      type: 'image',
    );
  }

  // ============================================================
  // MEDIA
  // ============================================================

  Future<void> sendMedia(
    List<XFile> files, {
    String text = '',
    required String type,
  }) async {
    if (_disposed ||
        files.isEmpty ||
        _sending) {
      return;
    }

    await _runSend(
      () => api.sendMedia(
        conversationId:
            conversationId,
        files: files,
        messageType: type,
        text: text.trim(),
      ),
    );
  }

  // ============================================================
  // AUDIO
  // ============================================================

  Future<void> sendAudio(
    XFile file,
  ) {
    return sendMedia(
      [file],
      type: 'audio',
    );
  }

  // ============================================================
  // VIDEO
  // ============================================================

  Future<void> sendVideo(
    XFile file, {
    String text = '',
  }) {
    return sendMedia(
      [file],
      text: text,
      type: 'video',
    );
  }

  // ============================================================
  // FILES
  // ============================================================

  Future<void> sendFiles(
    List<XFile> files, {
    String text = '',
  }) {
    return sendMedia(
      files,
      text: text,
      type: 'file',
    );
  }

  // ============================================================
  // COMMON SEND
  // ============================================================

  Future<void> _runSend(
    Future<ChatMessageDto> Function()
        operation,
  ) async {
    if (_disposed || _sending) {
      return;
    }

    _sending = true;
    _error = null;

    _safeNotify();

    try {
      final message =
          await operation();

      if (_disposed) return;

      /*
       * REST response gives us the message immediately.
       * Later websocket delivery of the same message
       * will merge instead of duplicate it.
       */
      _upsertMessage(
        message,
        merge: true,
      );
    } catch (error) {
      if (!_disposed) {
        _error = error.toString();
      }

      rethrow;
    } finally {
      if (!_disposed) {
        _sending = false;
        _safeNotify();
      }
    }
  }

  // ============================================================
  // EDIT
  // ============================================================

  Future<void> editMessage({
    required int messageId,
    required String text,
  }) async {
    if (_disposed) return;

    final value = text.trim();

    if (value.isEmpty) {
      return;
    }

    _error = null;

    try {
      final updated =
          await api.editMessage(
        messageId: messageId,
        text: value,
      );

      if (_disposed) return;

      _upsertMessage(
        updated,
        merge: true,
      );
    } catch (error) {
      if (!_disposed) {
        _error = error.toString();
        _safeNotify();
      }

      rethrow;
    }
  }

  // ============================================================
  // DELETE
  // ============================================================

  Future<void> deleteMessage(
    int messageId,
  ) async {
    if (_disposed) return;

    final index =
        _indexOfMessage(messageId);

    if (index == -1) {
      return;
    }

    /*
     * Only allow local user to delete their own
     * message from this controller.
     */
    if (_messages[index].senderId !=
        currentUserId) {
      return;
    }

    _error = null;

    try {
      await api.deleteMessage(
        messageId,
      );

      if (_disposed) return;

      _applyDeleted(
        messageId,
        notify: true,
      );
    } catch (error) {
      if (!_disposed) {
        _error = error.toString();
        _safeNotify();
      }

      rethrow;
    }
  }

  // ============================================================
  // REALTIME
  // ============================================================

  void _onRealtimeEvent(
    ConversationRealtimeEvent event,
  ) {
    if (_disposed) return;

    final type = event.type
        .trim()
        .toLowerCase();

    debugPrint(
      '[CHAT ROOM] realtime event: $type',
    );

    switch (type) {
      /*
       * New message.
       */
      case 'chat_message':
      case 'message':
      case 'message_created':
      case 'new_message':
        _handleRealtimeMessage(
          event.data,
        );
        break;

      /*
       * Message edited.
       */
      case 'message_edited':
      case 'chat_message_edited':
      case 'message_updated':
      case 'chat_message_updated':
        _handleRealtimeMessage(
          event.data,
        );
        break;

      /*
       * Message deleted.
       */
      case 'message_deleted':
      case 'chat_message_deleted':
      case 'delete_message':
        _handleRealtimeDelete(
          event.data,
        );
        break;

      /*
       * Delivered receipt.
       */
      case 'message_delivered':
      case 'chat_message_delivered':
      case 'delivered':
      case 'delivery_receipt':
        _handleDelivered(
          event.data,
        );
        break;

      /*
       * Read / seen receipt.
       */
      case 'message_read':
      case 'message_seen':
      case 'chat_message_read':
      case 'chat_message_seen':
      case 'read_receipt':
      case 'seen':
        _handleSeen(
          event.data,
        );
        break;

      /*
       * Conversation-level read event.
       *
       * Useful when backend says all messages up
       * to message_id have been seen.
       */
      case 'conversation_read':
      case 'conversation_seen':
        _handleConversationSeen(
          event.data,
        );
        break;

      default:
        /*
         * Do nothing here.
         *
         * The same realtime connection may also carry
         * group-call events. GroupCallController needs
         * those events.
         */
        break;
    }
  }

  // ============================================================
  // REALTIME MESSAGE
  // ============================================================

  void _handleRealtimeMessage(
    Map<String, dynamic> data,
  ) {
    final raw =
        data['message'] ??
        data['data'];

    Map<String, dynamic>? json;

    if (raw is Map) {
      json =
          Map<String, dynamic>.from(raw);
    } else if (_looksLikeMessage(data)) {
      json =
          Map<String, dynamic>.from(data);
    }

    if (json == null) {
      debugPrint(
        '[CHAT ROOM] realtime message '
        'contains no message object',
      );

      return;
    }

    try {
      final message =
          ChatMessageDto.fromJson(
        json,
      );

      if (message.id <= 0) {
        return;
      }

      _upsertMessage(
        message,
        merge: true,
      );

      /*
       * Message belongs to another user:
       * this chat is currently open, so mark it read.
       */
      if (message.senderId !=
              currentUserId &&
          message.senderId != 0) {
        unawaited(
          _markIncomingRead(
            message.id,
          ),
        );
      }
    } catch (error) {
      debugPrint(
        '[CHAT ROOM] invalid realtime '
        'message: $error',
      );
    }
  }

  Future<void> _markIncomingRead(
    int messageId,
  ) async {
    final success =
        await api.markMessageRead(
      messageId,
    );

    if (_disposed || !success) {
      return;
    }

    /*
     * This represents the state from THIS user's
     * perspective. It also keeps the loaded incoming
     * object consistent.
     *
     * The sender needs a backend websocket read
     * receipt to turn its own ticks blue.
     */
    final index =
        _indexOfMessage(messageId);

    if (index == -1) {
      return;
    }

    final message =
        _messages[index];

    if (message.senderId ==
        currentUserId) {
      return;
    }

    _messages[index] =
        message.copyWith(
      delivered: true,
      seen: true,
    );

    _safeNotify();
  }

  // ============================================================
  // REALTIME DELETE
  // ============================================================

  void _handleRealtimeDelete(
    Map<String, dynamic> data,
  ) {
    final id =
        _extractMessageId(data);

    if (id == null) {
      return;
    }

    _applyDeleted(
      id,
      notify: true,
    );
  }

  void _applyDeleted(
    int messageId, {
    required bool notify,
  }) {
    final index =
        _indexOfMessage(messageId);

    if (index == -1) {
      return;
    }

    final current =
        _messages[index];

    _messages[index] =
        current.copyWith(
      text: '',
      isDeleted: true,
    );

    if (notify) {
      _safeNotify();
    }
  }

  // ============================================================
  // DELIVERED
  // ============================================================

  void _handleDelivered(
    Map<String, dynamic> data,
  ) {
    final ids =
        _extractMessageIds(data);

    if (ids.isEmpty) {
      return;
    }

    bool changed = false;

    for (final id in ids) {
      final index =
          _indexOfMessage(id);

      if (index == -1) {
        continue;
      }

      final current =
          _messages[index];

      /*
       * Receipt ticks only matter for messages
       * sent by the current user.
       */
      if (current.senderId !=
          currentUserId) {
        continue;
      }

      if (!current.delivered) {
        _messages[index] =
            current.copyWith(
          delivered: true,
        );

        changed = true;
      }
    }

    if (changed) {
      _safeNotify();
    }
  }

  // ============================================================
  // SEEN
  // ============================================================

  void _handleSeen(
    Map<String, dynamic> data,
  ) {
    final ids =
        _extractMessageIds(data);

    if (ids.isEmpty) {
      return;
    }

    bool changed = false;

    for (final id in ids) {
      final index =
          _indexOfMessage(id);

      if (index == -1) {
        continue;
      }

      final current =
          _messages[index];

      if (current.senderId !=
          currentUserId) {
        continue;
      }

      if (!current.seen ||
          !current.delivered) {
        _messages[index] =
            current.copyWith(
          delivered: true,
          seen: true,
        );

        changed = true;
      }
    }

    if (changed) {
      _safeNotify();
    }
  }

  // ============================================================
  // CONVERSATION SEEN
  // ============================================================

  void _handleConversationSeen(
    Map<String, dynamic> data,
  ) {
    /*
     * Backend may send:
     *
     * message_ids: [10,11,12]
     *
     * OR:
     *
     * last_read_message_id: 12
     *
     * OR:
     *
     * message_id: 12
     */

    final explicitIds =
        _extractMessageIds(data);

    if (explicitIds.length > 1) {
      _markOwnMessagesSeen(
        explicitIds.toSet(),
      );

      return;
    }

    final lastReadId =
        _intValue(
      data['last_read_message_id'] ??
          data['last_seen_message_id'] ??
          data['up_to_message_id'] ??
          data['message_id'],
    );

    if (lastReadId == null) {
      if (explicitIds.isNotEmpty) {
        _markOwnMessagesSeen(
          explicitIds.toSet(),
        );
      }

      return;
    }

    bool changed = false;

    for (int i = 0;
        i < _messages.length;
        i++) {
      final message =
          _messages[i];

      if (message.senderId !=
          currentUserId) {
        continue;
      }

      if (message.id >
          lastReadId) {
        continue;
      }

      if (!message.seen ||
          !message.delivered) {
        _messages[i] =
            message.copyWith(
          delivered: true,
          seen: true,
        );

        changed = true;
      }
    }

    if (changed) {
      _safeNotify();
    }
  }

  void _markOwnMessagesSeen(
    Set<int> ids,
  ) {
    bool changed = false;

    for (int i = 0;
        i < _messages.length;
        i++) {
      final message =
          _messages[i];

      if (!ids.contains(message.id)) {
        continue;
      }

      if (message.senderId !=
          currentUserId) {
        continue;
      }

      if (!message.seen ||
          !message.delivered) {
        _messages[i] =
            message.copyWith(
          delivered: true,
          seen: true,
        );

        changed = true;
      }
    }

    if (changed) {
      _safeNotify();
    }
  }

  // ============================================================
  // LOCAL READ STATE
  // ============================================================

  void _markIncomingMessagesSeenLocally() {
    bool changed = false;

    for (int i = 0;
        i < _messages.length;
        i++) {
      final message =
          _messages[i];

      if (message.senderId == 0 ||
          message.senderId ==
              currentUserId) {
        continue;
      }

      if (!message.seen ||
          !message.delivered) {
        _messages[i] =
            message.copyWith(
          delivered: true,
          seen: true,
        );

        changed = true;
      }
    }

    if (changed) {
      _safeNotify();
    }
  }

  // ============================================================
  // UPSERT
  // ============================================================

  void _upsertMessage(
    ChatMessageDto message, {
    bool merge = true,
  }) {
    if (_disposed ||
        message.id <= 0) {
      return;
    }

    final index =
        _indexOfMessage(
      message.id,
    );

    if (index == -1) {
      _messages.add(message);
    } else {
      _messages[index] =
          merge
              ? _mergeMessages(
                  _messages[index],
                  message,
                )
              : message;
    }

    _sortMessages();
    _safeNotify();
  }

  // ============================================================
  // MERGE
  // ============================================================

  ChatMessageDto _mergeMessages(
    ChatMessageDto oldMessage,
    ChatMessageDto newMessage,
  ) {
    /*
     * delivered / seen / deleted are monotonic states.
     *
     * Once true, an older websocket or REST response
     * should not accidentally turn them false again.
     */
    return newMessage.copyWith(
      delivered:
          oldMessage.delivered ||
          newMessage.delivered,

      seen:
          oldMessage.seen ||
          newMessage.seen,

      isDeleted:
          oldMessage.isDeleted ||
          newMessage.isDeleted,

      isEdited:
          oldMessage.isEdited ||
          newMessage.isEdited,

      /*
       * If deletion was already received but an older
       * message event arrives later, keep text empty.
       */
      text:
          oldMessage.isDeleted ||
                  newMessage.isDeleted
              ? ''
              : newMessage.text,
    );
  }

  // ============================================================
  // MESSAGE ID HELPERS
  // ============================================================

  int _indexOfMessage(
    int messageId,
  ) {
    return _messages.indexWhere(
      (message) =>
          message.id == messageId,
    );
  }

  int? _extractMessageId(
    Map<String, dynamic> data,
  ) {
    final direct =
        _intValue(
      data['message_id'] ??
          data['id'],
    );

    if (direct != null) {
      return direct;
    }

    final message =
        data['message'];

    if (message is Map) {
      return _intValue(
        message['id'] ??
            message['message_id'],
      );
    }

    final nested =
        data['data'];

    if (nested is Map) {
      return _intValue(
        nested['message_id'] ??
            nested['id'],
      );
    }

    return null;
  }

  List<int> _extractMessageIds(
    Map<String, dynamic> data,
  ) {
    final result =
        <int>{};

    void addValue(dynamic value) {
      final id =
          _intValue(value);

      if (id != null &&
          id > 0) {
        result.add(id);
      }
    }

    final ids =
        data['message_ids'] ??
        data['ids'];

    if (ids is List) {
      for (final value in ids) {
        addValue(value);
      }
    }

    addValue(
      data['message_id'],
    );

    /*
     * Only treat "id" as message ID when no
     * explicit message ID was supplied.
     */
    if (result.isEmpty) {
      addValue(
        data['id'],
      );
    }

    final message =
        data['message'];

    if (message is Map) {
      addValue(
        message['id'] ??
            message['message_id'],
      );
    }

    final nested =
        data['data'];

    if (nested is Map) {
      final nestedIds =
          nested['message_ids'];

      if (nestedIds is List) {
        for (final value
            in nestedIds) {
          addValue(value);
        }
      }

      addValue(
        nested['message_id'] ??
            nested['id'],
      );
    }

    return result.toList();
  }

  int? _intValue(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value.toString(),
    );
  }

  bool _looksLikeMessage(
    Map<String, dynamic> data,
  ) {
    return data.containsKey('id') &&
        (
          data.containsKey('sender') ||
          data.containsKey('sender_id') ||
          data.containsKey('text') ||
          data.containsKey('attachments') ||
          data.containsKey('message_type')
        );
  }

  // ============================================================
  // SORT
  // ============================================================

  void _sortMessages() {
    _messages.sort(
      (a, b) {
        final aDate =
            a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(
              0,
            );

        final bDate =
            b.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(
              0,
            );

        final dateCompare =
            aDate.compareTo(
          bDate,
        );

        if (dateCompare != 0) {
          return dateCompare;
        }

        return a.id.compareTo(
          b.id,
        );
      },
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    final subscription =
        _realtimeSubscription;

    _realtimeSubscription = null;

    if (subscription != null) {
      unawaited(
        subscription.cancel(),
      );
    }

    /*
     * DO NOT dispose realtime here.
     *
     * ConversationChatScreen owns it because
     * GroupCallController also uses the same
     * realtime service.
     */

    super.dispose();
  }
}