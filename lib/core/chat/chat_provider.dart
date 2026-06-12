import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/core/chat/chat_api.dart';
import 'package:messaging_app/core/chat/chat_socket_service.dart';
class ChatProvider extends ChangeNotifier {
  bool isLoading = false;
  bool isSending = false;
  bool isTyping = false;
  String? error;

  int? currentUserId;
  int? connectedConversationId;

  final List<ChatItem> conversations = [];
  final Map<String, List<ChatMessage>> conversationMessages = {};
  final ChatSocketService socket = ChatSocketService();
  final List<dynamic> searchedUsers = [];

  Future<String> _myUserId() async {
    return await ApiClient.storage.read(key: 'user_id') ?? '';
  }

  List<ChatItem> get privateChats {
    return conversations.where((chat) => chat.isGroup != true).toList();
  }

  List<ChatItem> searchPrivateUsersByPhone(String query) {
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return privateChats;

    return privateChats.where((chat) {
      final phone = chat.phone.replaceAll(RegExp(r'[^0-9]'), '');
      return phone.contains(digits);
    }).toList();
  }

  void _setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }

  void _setSending(bool value) {
    isSending = value;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> connectSocket({
    required int conversationId,
  }) async {
    final myIdString = await _myUserId();
    final myId = int.tryParse(myIdString) ?? 0;

    currentUserId = myId;
    connectedConversationId = conversationId;

    socket.connect(
      conversationId: conversationId,
      onMessage: (data) async {
        final action = data['action']?.toString();
        final type = data['type']?.toString();

        if (action == 'new_message' || type == 'message') {
          final rawMessage = data['message'] ?? data;
          final message = await _mapMessage(rawMessage);

          if (message.type == MessageType.text && message.text.trim().isEmpty) {
            return;
          }

          final key = '$conversationId';
          conversationMessages.putIfAbsent(key, () => []);

          final alreadyExists = conversationMessages[key]!.any(
            (m) => m.id == message.id,
          );

          if (alreadyExists) return;

          _addLocalMessage(conversationId, message);
          return;
        }

        if (action == 'typing' || type == 'typing') {
          final senderId = data['sender_id']?.toString();

          if (senderId != myIdString) {
            isTyping = data['is_typing'] == true;
            notifyListeners();
          }
          return;
        }

        if (action == 'seen' || type == 'seen') {
          notifyListeners();
          return;
        }
      },
      onError: (err) {
        error = err.toString();
        notifyListeners();
      },
      onDisconnected: () {
        isTyping = false;
        notifyListeners();
      },
    );
  }

  void disconnectSocket() {
    socket.disconnect();
    connectedConversationId = null;
    isTyping = false;

    Future.microtask(() {
      notifyListeners();
    });
  }

  void sendSocketTyping({required bool typing}) {
    if (currentUserId == null) return;

    socket.sendTyping(
      senderId: currentUserId!,
      isTyping: typing,
    );
  }

  Future<void> loadConversations() async {
    _setLoading(true);
    error = null;

    try {
      final response = await ChatApi.getConversations();

      final data = response.data;
      final list =
          data is List ? data : data['results'] ?? data['conversations'] ?? [];

      conversations.clear();

      for (final item in List.from(list)) {
        conversations.add(await _mapConversation(item));
      }
    } catch (e) {
      error = e.toString();
    }

    _setLoading(false);
  }

  Future<void> searchUsers(String phone) async {
    final cleanPhone = phone.trim();

    if (cleanPhone.isEmpty) {
      searchedUsers.clear();
      error = null;
      notifyListeners();
      return;
    }

    try {
      error = null;

      final response = await ChatApi.searchUser(phone: cleanPhone);
      final data = response.data;

      searchedUsers.clear();

      if (data is Map && data['id'] != null) {
        searchedUsers.add(data);
      } else if (data is List) {
        searchedUsers.addAll(data);
      } else if (data is Map) {
        searchedUsers.addAll(data['results'] ?? data['users'] ?? []);
      }
    } catch (e) {
      searchedUsers.clear();
      error = null;
    }

    notifyListeners();
  }

  Future<void> loadMessages(int conversationId) async {
    _setLoading(true);
    error = null;

    try {
      final response = await ChatApi.getMessages(
        conversationId: conversationId,
      );

      final data = response.data;
      final list =
          data is List ? data : data['results'] ?? data['messages'] ?? [];

      final messages = <ChatMessage>[];

      for (final item in List.from(list)) {
        final message = await _mapMessage(item);

        if (message.type == MessageType.text && message.text.trim().isEmpty) {
          continue;
        }

        messages.add(message);
      }

      messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));

      conversationMessages['$conversationId'] = messages;
    } catch (e) {
      error = e.toString();
    }

    _setLoading(false);
  }

  Future<ChatItem?> startPrivateChat(int userId) async {
    if (isSending) return null;

    isSending = true;
    error = null;
    notifyListeners();

    try {
      final response = await ChatApi.startPrivateChat(userId: userId);

      final chat = await _mapConversation(response.data);
      _upsertConversation(chat);

      return chat;
    } catch (e) {
      error = e.toString();
      return null;
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  Future<ChatItem?> createGroup({
    required String name,
    required List<int> memberIds,
    File? groupImage,
  }) async {
    _setLoading(true);
    error = null;

    try {
      final response = await ChatApi.createGroup(
        name: name,
        memberIds: memberIds,
        groupImage: groupImage,
      );

      final chat = await _mapConversation(response.data);
      _upsertConversation(chat);

      _setLoading(false);
      return chat;
    } catch (e) {
      error = e.toString();
      _setLoading(false);
      return null;
    }
  }

  Future<void> sendText({
    required int conversationId,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;

    final cleanText = text.trim();

    final temp = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: MessageType.text,
      text: cleanText,
      isMe: true,
      sentAt: DateTime.now(),
      isSeen: false,
    );

    _addLocalMessage(conversationId, temp);

    _setSending(true);
    error = null;

    try {
      final response = await ChatApi.sendText(
        conversationId: conversationId,
        text: cleanText,
      );

      final realMessage = await _mapMessage(response.data);
      _replaceMessage(conversationId, temp.id, realMessage);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }

    _setSending(false);
  }

  Future<void> sendReply({
    required int conversationId,
    required String text,
    required int replyTo,
    String? replyPreview,
    bool? replyToMe,
  }) async {
    if (text.trim().isEmpty) return;

    final cleanText = text.trim();

    final temp = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: MessageType.text,
      text: cleanText,
      isMe: true,
      sentAt: DateTime.now(),
      isSeen: false,
      replyToMessageId: '$replyTo',
      replyPreview: replyPreview,
      replyToMe: replyToMe,
    );

    _addLocalMessage(conversationId, temp);

    _setSending(true);
    error = null;

    try {
      final response = await ChatApi.sendReply(
        conversationId: conversationId,
        text: cleanText,
        replyTo: replyTo,
      );

      final realMessage = await _mapMessage(response.data);
      _replaceMessage(conversationId, temp.id, realMessage);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }

    _setSending(false);
  }

  Future<void> sendReaction({
    required int conversationId,
    required int reactionTo,
    required String reaction,
  }) async {
    error = null;

    try {
      await ChatApi.sendReaction(
        conversationId: conversationId,
        reactionTo: reactionTo,
        reaction: reaction,
      );
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> sendImage({
    required int conversationId,
    required File image,
    String? caption,
  }) async {
    final temp = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: MessageType.image,
      text: caption ?? '',
      isMe: true,
      sentAt: DateTime.now(),
      isSeen: false,
      filePath: image.path,
      fileName: image.path.split('/').last,
    );

    _addLocalMessage(conversationId, temp);

    _setSending(true);
    error = null;

    try {
      final response = await ChatApi.sendImage(
        conversationId: conversationId,
        image: image,
        caption: caption,
      );

      final realMessage = await _mapMessage(response.data);
      _replaceMessage(conversationId, temp.id, realMessage);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }

    _setSending(false);
  }

  Future<void> sendImages({
  required int conversationId,
  required List<File> images,
  String? caption,
}) async {
  if (images.isEmpty) return;

  final temp = ChatMessage(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    type: MessageType.mediaAlbum,
    text: caption ?? '',
    isMe: true,
    sentAt: DateTime.now(),
    isSeen: false,
    mediaUrls: images.map((e) => e.path).toList(),
  );

  _addLocalMessage(conversationId, temp);

  notifyListeners();
}

  Future<void> sendVideo({
    required int conversationId,
    required File video,
    required double duration,
    String? caption,
  }) async {
    final temp = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: MessageType.video,
      text: caption ?? '',
      isMe: true,
      sentAt: DateTime.now(),
      isSeen: false,
      filePath: video.path,
      fileName: video.path.split('/').last,
    );

    _addLocalMessage(conversationId, temp);

    _setSending(true);
    error = null;

    try {
      final response = await ChatApi.sendVideo(
        conversationId: conversationId,
        video: video,
        duration: duration,
        caption: caption,
      );

      final realMessage = await _mapMessage(response.data);
      _replaceMessage(conversationId, temp.id, realMessage);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }

    _setSending(false);
  }

  Future<void> sendAudio({
    required int conversationId,
    required File audio,
    required double duration,
  }) async {
    final temp = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: MessageType.audio,
      text: 'Voice message',
      isMe: true,
      sentAt: DateTime.now(),
      isSeen: false,
      audioPath: audio.path,
      audioDuration: Duration(milliseconds: (duration * 1000).toInt()),
    );

    _addLocalMessage(conversationId, temp);

    _setSending(true);
    error = null;

    try {
      final response = await ChatApi.sendAudio(
        conversationId: conversationId,
        audio: audio,
        duration: duration,
      );

      final realMessage = await _mapMessage(response.data);
      _replaceMessage(conversationId, temp.id, realMessage);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }

    _setSending(false);
  }

  Future<void> sendFile({
    required int conversationId,
    required File file,
  }) async {
    final temp = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: MessageType.file,
      text: '',
      isMe: true,
      sentAt: DateTime.now(),
      isSeen: false,
      filePath: file.path,
      fileName: file.path.split('/').last,
    );

    _addLocalMessage(conversationId, temp);

    _setSending(true);
    error = null;

    try {
      final response = await ChatApi.sendFile(
        conversationId: conversationId,
        file: file,
      );

      final realMessage = await _mapMessage(response.data);
      _replaceMessage(conversationId, temp.id, realMessage);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }

    _setSending(false);
  }

  Future<void> sendFiles({
    required int conversationId,
    required List<File> files,
  }) async {
    if (files.isEmpty) return;

    for (final file in files) {
      await sendFile(
        conversationId: conversationId,
        file: file,
      );
    }
  }

  List<ChatMessage> getMessagesForChat(String conversationId) {
    return conversationMessages[conversationId] ?? [];
  }

  void _addLocalMessage(int conversationId, ChatMessage message) {
    if (message.type == MessageType.text && message.text.trim().isEmpty) {
      return;
    }

    final key = '$conversationId';

    conversationMessages.putIfAbsent(key, () => []);

    final exists = conversationMessages[key]!.any((m) => m.id == message.id);
    if (!exists) {
      conversationMessages[key]!.add(message);
    }

    conversationMessages[key]!.sort((a, b) => a.sentAt.compareTo(b.sentAt));

    final index = conversations.indexWhere((c) => c.id == key);

    if (index != -1) {
      conversations[index].message = _preview(message);
      conversations[index].time = _formatChatTime(message.sentAt);

      final chat = conversations.removeAt(index);
      conversations.insert(0, chat);
    }

    notifyListeners();
  }

  void _replaceMessage(
    int conversationId,
    String tempId,
    ChatMessage realMessage,
  ) {
    final key = '$conversationId';
    final list = conversationMessages[key];

    if (list == null) return;

    final tempIndex = list.indexWhere((m) => m.id == tempId);
    final realIndex = list.indexWhere((m) => m.id == realMessage.id);

    if (realIndex != -1 && tempIndex != -1 && realIndex != tempIndex) {
      list.removeAt(tempIndex);
    } else if (tempIndex != -1) {
      list[tempIndex] = realMessage;
    } else if (realIndex == -1) {
      list.add(realMessage);
    }

    list.sort((a, b) => a.sentAt.compareTo(b.sentAt));

    final chatIndex = conversations.indexWhere((c) => c.id == key);

    if (chatIndex != -1) {
      conversations[chatIndex].message = _preview(realMessage);
      conversations[chatIndex].time = _formatChatTime(realMessage.sentAt);
    }

    notifyListeners();
  }

  void _upsertConversation(ChatItem chat) {
    final index = conversations.indexWhere((c) => c.id == chat.id);

    if (index == -1) {
      conversations.insert(0, chat);
    } else {
      conversations[index] = chat;
    }

    notifyListeners();
  }

  Future<ChatItem> _mapConversation(dynamic json) async {
    final myId = await _myUserId();

    final lastMessage = json['last_message'];
    final mappedLastMessage =
        lastMessage == null ? null : await _mapMessage(lastMessage);

    final isGroup = json['type'] == 'group' ||
        json['conversation_type'] == 'group' ||
        json['is_group'] == true;

    final members = _mapMembers(json['members']);

    ChatUser? otherUser;

    if (!isGroup && members.isNotEmpty) {
      for (final member in members) {
        if (member.id.toString() != myId.toString()) {
          otherUser = member;
          break;
        }
      }

      otherUser ??= members.first;
    }

    String chatName =
        json['name']?.toString() ?? json['title']?.toString() ?? '';

    String avatarUrl = json['image']?.toString() ??
        json['group_image']?.toString() ??
        json['avatar']?.toString() ??
        json['avatar_url']?.toString() ??
        json['profile_picture']?.toString() ??
        '';

    String phone = '';

    if (!isGroup) {
      phone = json['phone']?.toString() ??
          json['phone_number']?.toString() ??
          json['other_user']?['phone']?.toString() ??
          json['other_user']?['phone_number']?.toString() ??
          '';

      if (otherUser != null) {
        if (phone.trim().isEmpty) {
          phone = otherUser.phone;
        }

        if (chatName.trim().isEmpty) {
          chatName = otherUser.name.trim().isNotEmpty
              ? otherUser.name.trim()
              : otherUser.phone.trim().isNotEmpty
                  ? otherUser.phone.trim()
                  : 'Unknown';
        }

        if (avatarUrl.trim().isEmpty) {
          avatarUrl = otherUser.avatarUrl;
        }
      }

      if (avatarUrl.trim().isEmpty && json['other_user'] is Map) {
        final otherUserMap = json['other_user'] as Map;

        avatarUrl = otherUserMap['profile_picture']?.toString() ??
            otherUserMap['profilePicture']?.toString() ??
            otherUserMap['avatar']?.toString() ??
            otherUserMap['avatar_url']?.toString() ??
            otherUserMap['profile_image']?.toString() ??
            otherUserMap['image']?.toString() ??
            otherUserMap['photo']?.toString() ??
            '';
      }
    }

    if (chatName.trim().isEmpty) {
      chatName = json['other_user']?['full_name']?.toString() ??
          json['other_user']?['profile_name']?.toString() ??
          json['other_user']?['name']?.toString() ??
          json['other_user']?['username']?.toString() ??
          json['other_user']?['phone']?.toString() ??
          'Unknown';
    }

    debugPrint('MAPPED CHAT NAME: $chatName');
    debugPrint('MAPPED CHAT AVATAR: $avatarUrl');

    return ChatItem(
      id: '${json['id']}',
      name: chatName,
      phone: phone,
      avatarUrl: avatarUrl,
      isOnline: otherUser?.isOnline ??
          json['is_online'] ??
          json['other_user']?['is_online'] ??
          false,
      isGroup: isGroup,
      members: members,
      adminIds: _mapAdminIds(json),
      message: mappedLastMessage == null
          ? 'Start chatting'
          : _preview(mappedLastMessage),
      time: mappedLastMessage == null
          ? ''
          : _formatChatTime(mappedLastMessage.sentAt),
      unreadCount: json['unread_count'] ?? 0,
      messages: mappedLastMessage == null ? [] : [mappedLastMessage],
    );
  }

  List<ChatUser> _mapMembers(dynamic membersJson) {
    if (membersJson is! List) return [];

    final members = <ChatUser>[];

    for (final member in membersJson) {
      if (member is! Map) continue;

      final user = member['user'] is Map ? member['user'] as Map : member;

      final avatarUrl = user['profile_picture']?.toString() ??
          user['profilePicture']?.toString() ??
          user['avatar']?.toString() ??
          user['avatar_url']?.toString() ??
          user['profile_image']?.toString() ??
          user['image']?.toString() ??
          user['photo']?.toString() ??
          member['profile_picture']?.toString() ??
          member['profilePicture']?.toString() ??
          member['avatar']?.toString() ??
          member['avatar_url']?.toString() ??
          member['profile_image']?.toString() ??
          member['image']?.toString() ??
          member['photo']?.toString() ??
          '';

      final name = member['display_name']?.toString() ??
          member['nickname']?.toString() ??
          user['full_name']?.toString() ??
          user['profile_name']?.toString() ??
          user['name']?.toString() ??
          user['username']?.toString() ??
          user['phone']?.toString() ??
          user['phone_number']?.toString() ??
          'Unknown';

      final phone = user['phone_number']?.toString() ??
          user['phone']?.toString() ??
          member['phone_number']?.toString() ??
          member['phone']?.toString() ??
          '';

      members.add(
        ChatUser(
          id: user['id']?.toString() ??
              member['user_id']?.toString() ??
              member['id']?.toString() ??
              '',
          name: name,
          phone: phone,
          avatarUrl: avatarUrl,
          isOnline: user['is_online'] ?? member['is_online'] ?? false,
        ),
      );

      debugPrint('MAPPED MEMBER: ${members.last.id} ${members.last.name}');
      debugPrint('MAPPED MEMBER AVATAR: ${members.last.avatarUrl}');
    }

    return members;
  }

  List<String> _mapAdminIds(dynamic json) {
    final rawAdmins = json['admin_ids'] ?? json['admins'] ?? [];

    if (rawAdmins is! List) return [];

    return rawAdmins.map((item) {
      if (item is Map && item['id'] != null) {
        return item['id'].toString();
      }
      return item.toString();
    }).toList();
  }

  Future<ChatMessage> _mapMessage(dynamic json) async {
    final myId = await _myUserId();

    final sender = json['sender'];

    final senderId = sender is Map
        ? sender['id'].toString()
        : json['sender_id']?.toString() ?? sender?.toString() ?? '';

    final messageType = json['message_type']?.toString() ?? 'text';
    final type = _backendTypeToMessageType(messageType);

    return ChatMessage(
      id: '${json['id']}',
      type: type,
      text: json['text']?.toString() ?? json['message']?.toString() ?? '',
      isMe: senderId == myId,
      sentAt: _parseDate(
        json['created_at'] ?? json['sent_at'] ?? json['timestamp'],
      ),
      isSeen: json['is_seen'] ?? json['seen'] ?? false,
      senderId: senderId,
      senderName: sender is Map
          ? sender['full_name']?.toString() ??
              sender['name']?.toString() ??
              sender['username']?.toString()
          : null,
      senderAvatar: sender is Map
          ? sender['profile_picture']?.toString() ??
              sender['profilePicture']?.toString() ??
              sender['avatar']?.toString() ??
              sender['avatar_url']?.toString() ??
              sender['profile_image']?.toString() ??
              sender['image']?.toString() ??
              sender['photo']?.toString()
          : null,
      filePath: json['media']?.toString() ??
          json['media_url']?.toString() ??
          json['file']?.toString(),
      fileName: json['file_name']?.toString() ?? json['media_name']?.toString(),
      fileSizeBytes: json['file_size'] is int ? json['file_size'] : null,
      audioPath: type == MessageType.audio
          ? json['media']?.toString() ??
              json['media_url']?.toString() ??
              json['file']?.toString()
          : null,
      audioDuration: json['duration'] == null
          ? null
          : Duration(
              milliseconds:
                  ((num.tryParse(json['duration'].toString()) ?? 0) * 1000)
                      .toInt(),
            ),
      replyToMessageId: json['reply_to']?.toString(),
      replyPreview: json['reply_preview']?.toString() ??
          json['reply_to_text']?.toString() ??
          json['reply_to_data']?['text']?.toString(),
      replyToMe: json['reply_to_me'],
    );
  }

  MessageType _backendTypeToMessageType(String type) {
    switch (type) {
      case 'image':
        return MessageType.image;
      case 'media_album':
        return MessageType.mediaAlbum;
      case 'video':
        return MessageType.video;
      case 'audio':
        return MessageType.audio;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }

  DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    return DateTime.tryParse(value.toString())?.toLocal() ?? DateTime.now();
  }

  String _preview(ChatMessage message) {
    switch (message.type) {
      case MessageType.mediaAlbum:
     return '📷 ${message.mediaUrls?.length ?? 0} Photos';
      case MessageType.text:
        return message.text.isEmpty ? 'Message' : message.text;
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

  String _formatChatTime(DateTime time) {
    return DateFormat('h:mm a').format(time);
  }
}