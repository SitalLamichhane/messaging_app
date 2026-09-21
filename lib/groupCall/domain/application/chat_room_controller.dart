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

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    if (_disposed ||
        _initializing ||
        _initialized) {
      return;
    }

    _initializing = true;
    _error = null;

    try {
      await _realtimeSubscription
          ?.cancel();

      if (_disposed) return;

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

      try {
        await api.markConversationRead(
          conversationId,
        );
      } catch (e) {
        debugPrint(
          '[CHAT ROOM] mark conversation read failed: $e',
        );
      }

      _initialized = true;
    } catch (e) {
      _error = e.toString();

      debugPrint(
        '[CHAT ROOM] initialize failed: $e',
      );

      _safeNotify();
    } finally {
      _initializing = false;
    }
  }

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
       * Do not simply clear/add without deduplication.
       *
       * A websocket message may arrive while REST history
       * is loading.
       */
      final combined =
          <int, ChatMessageDto>{};

      for (final message in loaded) {
        if (message.id > 0) {
          combined[message.id] =
              message;
        }
      }

      // Keep messages received through websocket while
      // REST history was loading.
      for (final message in _messages) {
        if (message.id > 0) {
          combined[message.id] =
              message;
        }
      }

      _messages
        ..clear()
        ..addAll(combined.values);

      _sortMessages();
    } catch (e) {
      if (!_disposed) {
        _error = e.toString();
      }
    } finally {
      if (!_disposed) {
        _loading = false;
        _safeNotify();
      }
    }
  }

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
      final message =
          await api.sendText(
        conversationId:
            conversationId,
        text: value,
      );

      if (_disposed) return;

      /*
       * WebSocket broadcast may already have inserted
       * this same message.
       *
       * _upsertMessage() prevents duplicate bubbles.
       */
      _upsertMessage(message);
    } catch (e) {
      if (!_disposed) {
        _error = e.toString();
      }

      rethrow;
    } finally {
      if (!_disposed) {
        _sending = false;
        _safeNotify();
      }
    }
  }

  Future<void> sendImages(
    List<XFile> files, {
    String text = '',
  }) async {
    if (_disposed ||
        files.isEmpty ||
        _sending) {
      return;
    }

    _sending = true;
    _error = null;
    _safeNotify();

    try {
      final message =
          await api.sendMedia(
        conversationId:
            conversationId,
        files: files,
        text: text.trim(),
      );

      if (_disposed) return;

      _upsertMessage(message);
    } catch (e) {
      if (!_disposed) {
        _error = e.toString();
      }

      rethrow;
    } finally {
      if (!_disposed) {
        _sending = false;
        _safeNotify();
      }
    }
  }

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

      // _upsertMessage already notifies.
      _upsertMessage(updated);
    } catch (e) {
      if (!_disposed) {
        _error = e.toString();
        _safeNotify();
      }

      rethrow;
    }
  }

  Future<void> deleteMessage(
    int messageId,
  ) async {
    if (_disposed) return;

    _error = null;

    try {
      await api.deleteMessage(
        messageId,
      );

      if (_disposed) return;

      final index =
          _messages.indexWhere(
        (item) =>
            item.id == messageId,
      );

      if (index == -1) {
        return;
      }

      _messages[index] =
          _messages[index].copyWith(
        text: '',
        isDeleted: true,
      );

      _safeNotify();
    } catch (e) {
      if (!_disposed) {
        _error = e.toString();
        _safeNotify();
      }

      rethrow;
    }
  }

  void _onRealtimeEvent(
    ConversationRealtimeEvent event,
  ) {
    if (_disposed) return;

    if (event.type !=
        'chat_message') {
      return;
    }

    final raw =
        event.data['message'];

    if (raw is! Map) {
      debugPrint(
        '[CHAT ROOM] chat_message has no message map',
      );
      return;
    }

    try {
      final message =
          ChatMessageDto.fromJson(
        Map<String, dynamic>.from(
          raw,
        ),
      );

      if (message.id <= 0) {
        return;
      }

      _upsertMessage(message);

      /*
       * Only mark messages from OTHER users as read.
       */
      if (message.senderId !=
              currentUserId &&
          message.senderId != 0) {
        unawaited(
          api
              .markMessageRead(
                message.id,
              )
              .catchError((_) {}),
        );
      }
    } catch (e) {
      debugPrint(
        '[CHAT ROOM] invalid realtime message: $e',
      );
    }
  }

  /// REST response + websocket broadcast can arrive
  /// almost simultaneously.
  ///
  /// Server message ID is the source of truth.
  void _upsertMessage(
    ChatMessageDto message,
  ) {
    if (_disposed ||
        message.id <= 0) {
      return;
    }

    final index =
        _messages.indexWhere(
      (item) =>
          item.id == message.id,
    );

    if (index == -1) {
      _messages.add(message);
    } else {
      _messages[index] =
          message;
    }

    _sortMessages();
    _safeNotify();
  }

  void _sortMessages() {
    _messages.sort((a, b) {
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
          aDate.compareTo(bDate);

      if (dateCompare != 0) {
        return dateCompare;
      }

      return a.id.compareTo(b.id);
    });
  }

  @override
  void dispose() {
    if (_disposed) return;

    _disposed = true;

    final subscription =
        _realtimeSubscription;

    _realtimeSubscription = null;

    if (subscription != null) {
      unawaited(
        subscription.cancel(),
      );
    }

    super.dispose();
  }
}