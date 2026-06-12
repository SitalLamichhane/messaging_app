import 'package:flutter/foundation.dart';
import 'package:messaging_app/chat_models.dart';

class QuickDialContact {
  final String id;
  final String name;
  final String phone;
  final String avatarUrl;
  final bool isOnline;

  QuickDialContact({
    required this.id,
    required this.name,
    this.phone = '',
    required this.avatarUrl,
    this.isOnline = true,
  });
}

class AppChatData {
  static final ValueNotifier<int> refresh = ValueNotifier<int>(0);

  static final List<ChatItem> chats = [];
  static final List<CallEntry> allCalls = [];

  static void notify() {
    refresh.value++;
  }

  static ChatItem? findChatById(String id) {
    try {
      return chats.firstWhere((chat) => chat.id == id);
    } catch (_) {
      return null;
    }
  }

  static void upsertChat(ChatItem chat) {
    final index = chats.indexWhere((c) => c.id == chat.id);

    if (index >= 0) {
      chats[index] = chat;
    } else {
      chats.insert(0, chat);
    }

    notify();
  }

  static void addMessage(ChatItem chat, ChatMessage message) {
    chat.messages.insert(0, message);
    chat.message = _chatPreview(message);
    chat.time = _formatChatTime(message.sentAt);
    _moveChatToTop(chat);
    notify();
  }

  static void addCallLog({
    required ChatItem chat,
    required CallEntryType type,
    required CallEntryStatus status,
    Duration? duration,
    bool answered = true,
  }) {
    allCalls.insert(
      0,
      CallEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        chatId: chat.id,
        name: chat.name,
        avatarUrl: chat.avatarUrl,
        isGroup: chat.isGroup,
        relativeTime: 'Just now',
        type: type,
        status: status,
      ),
    );

    addMessage(
      chat,
      ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: MessageType.call,
        text: type == CallEntryType.video ? 'Video call' : 'Voice call',
        isMe: status == CallEntryStatus.outgoing,
        sentAt: DateTime.now(),
        isSeen: true,
        callType: type,
        callDuration: duration,
        callAnswered: answered,
      ),
    );
  }

  static void _moveChatToTop(ChatItem chat) {
    final index = chats.indexWhere((c) => c.id == chat.id);
    if (index <= 0) return;

    final item = chats.removeAt(index);
    chats.insert(0, item);
  }

  static String _chatPreview(ChatMessage message) {
    switch (message.type) {
      case MessageType.text:
        return message.text;
      case MessageType.image:
        return '📷 Photo';
      case MessageType.mediaAlbum:
        return '📷 ${message.mediaUrls?.length ?? 0} Photos';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.file:
        return '📎 ${message.fileName ?? "File"}';
      case MessageType.call:
        return message.callType == CallEntryType.video
            ? '📹 Video call'
            : '📞 Voice call';
      case MessageType.audio:
        return '🎤 Voice message';
    }
  }

  static String _formatChatTime(DateTime time) {
    final hour = time.hour > 12
        ? time.hour - 12
        : time.hour == 0
            ? 12
            : time.hour;

    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $suffix';
  }
}