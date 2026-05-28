// Replace your full AppChatData file with this.
// This is only fallback/mock data, but it will not break your production app.

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

  static final List<ChatItem> chats = [
    ChatItem(
      id: 'c1',
      name: 'Sarah Johnson',
      phone: '+9779800000001',
      avatarUrl:
          'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=300&q=80',
      isOnline: true,
      message: 'Hey, are you free tonight?',
      time: '2:34 PM',
      unreadCount: 2,
      messages: [
        ChatMessage(
          id: 'm1',
          type: MessageType.text,
          text: 'Hey 👋',
          isMe: false,
          sentAt: DateTime.now().subtract(const Duration(minutes: 18)),
        ),
        ChatMessage(
          id: 'm2',
          type: MessageType.text,
          text: 'Hi, yes. What happened?',
          isMe: true,
          sentAt: DateTime.now().subtract(const Duration(minutes: 16)),
          isSeen: true,
        ),
        ChatMessage(
          id: 'm3',
          type: MessageType.text,
          text: 'Are you free tonight?',
          isMe: false,
          sentAt: DateTime.now().subtract(const Duration(minutes: 14)),
        ),
      ],
    ),
    ChatItem(
      id: 'c2',
      name: 'Michael Chen',
      phone: '+9779800000002',
      avatarUrl:
          'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=300&q=80',
      isOnline: true,
      message: 'Let’s test the new call UI.',
      time: '1:20 PM',
      unreadCount: 0,
      messages: [
        ChatMessage(
          id: 'm4',
          type: MessageType.text,
          text: 'Let’s test the new call UI.',
          isMe: false,
          sentAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ],
    ),
    ChatItem(
      id: 'c3',
      name: 'Design Team',
      phone: '',
      avatarUrl:
          'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=300&q=80',
      isOnline: false,
      isGroup: true,
      message: 'Updated the Messenger layout preview.',
      time: 'Yesterday',
      unreadCount: 4,
      messages: [
        ChatMessage(
          id: 'm5',
          type: MessageType.text,
          text: 'Updated the Messenger layout preview.',
          isMe: false,
          sentAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ],
    ),
  ];

  static final List<CallEntry> allCalls = [
    CallEntry(
      id: 'call1',
      chatId: 'c1',
      name: 'Sarah Johnson',
      avatarUrl:
          'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=300&q=80',
      isGroup: false,
      relativeTime: '10 min ago',
      type: CallEntryType.voice,
      status: CallEntryStatus.outgoing,
    ),
    CallEntry(
      id: 'call2',
      chatId: 'c2',
      name: 'Michael Chen',
      avatarUrl:
          'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=300&q=80',
      isGroup: false,
      relativeTime: '1 hour ago',
      type: CallEntryType.video,
      status: CallEntryStatus.incoming,
    ),
  ];

  static void notify() {
    refresh.value++;
  }

  static ChatItem getOrCreateChat({
    required String name,
    required String avatarUrl,
    String phone = '',
    bool isGroup = false,
  }) {
    try {
      return chats.firstWhere((c) => c.name == name && c.isGroup == isGroup);
    } catch (_) {
      final chat = ChatItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        phone: phone,
        avatarUrl: avatarUrl,
        isGroup: isGroup,
        isOnline: true,
        message: 'Start chatting',
        time: 'Now',
        unreadCount: 0,
        messages: [],
      );

      chats.insert(0, chat);
      notify();
      return chat;
    }
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