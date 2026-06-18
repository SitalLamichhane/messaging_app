import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:hiddenly/chat_models.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/core/chat/chat_api.dart';
import 'package:hiddenly/core/chat/chat_socket_service.dart';

class ChatProvider extends ChangeNotifier {
  bool isLoading = false;
  bool isSending = false;
  bool isTyping = false;
  String? error;

  int? currentUserId;
  int? connectedConversationId;

  final List<ChatItem> conversations = [];
  final Map<String, List<ChatMessage>> conversationMessages = {};

  /// Messenger-like reactions stored per conversation/message.
  /// key: conversationId, value: {messageId: emoji}
  final Map<String, Map<String, String>> conversationMessageReactions = {};

  /// Messenger-like pinned messages stored per conversation.
  /// key: conversationId, value: pinned message ids
  final Map<String, Set<String>> conversationPinnedMessageIds = {};

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


  Map<String, String> getReactionsForChat(String conversationId) {
    return Map<String, String>.from(
      conversationMessageReactions[conversationId] ?? const {},
    );
  }

  Set<String> getPinnedMessageIdsForChat(String conversationId) {
    return Set<String>.from(
      conversationPinnedMessageIds[conversationId] ?? const {},
    );
  }

  String? getReactionForMessage({
    required String conversationId,
    required String messageId,
  }) {
    final reaction = conversationMessageReactions[conversationId]?[messageId];
    if (reaction == null || reaction.trim().isEmpty) return null;
    return reaction;
  }

  bool isMessagePinned({
    required String conversationId,
    required String messageId,
  }) {
    return conversationPinnedMessageIds[conversationId]?.contains(messageId) ??
        false;
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

        if (_isReactionPayload(data)) {
          _applyReactionPayload(
            conversationId: conversationId,
            data: data,
          );
          return;
        }

        if (_isDeletePayload(data)) {
          _applyDeletePayload(
            conversationId: conversationId,
            data: data,
          );
          return;
        }

        if (_isPinPayload(data)) {
          _applyPinPayload(
            conversationId: conversationId,
            data: data,
          );
          return;
        }

        if (action == 'new_message' || type == 'message') {
          final rawMessage = data['message'] ?? data;

          if (_isReactionPayload(rawMessage)) {
            _applyReactionPayload(
              conversationId: conversationId,
              data: rawMessage,
            );
            return;
          }

          final message = await _mapMessage(rawMessage);

          if (message.type == MessageType.text && message.text.trim().isEmpty) {
            return;
          }

          _syncMessageMetaFromJson(
            conversationId: conversationId,
            messageId: message.id,
            json: rawMessage,
          );

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

    final myIdString = await _myUserId();
    currentUserId = int.tryParse(myIdString) ?? currentUserId;

    try {
      final response = await ChatApi.getMessages(
        conversationId: conversationId,
      );

      final data = response.data;
      final list =
          data is List ? data : data['results'] ?? data['messages'] ?? [];

      final messages = <ChatMessage>[];

      conversationMessageReactions['$conversationId'] = {};
      conversationPinnedMessageIds['$conversationId'] = {};

      for (final item in List.from(list)) {
        final message = await _mapMessage(item);

        if (message.type == MessageType.text && message.text.trim().isEmpty) {
          continue;
        }

        _syncMessageMetaFromJson(
          conversationId: conversationId,
          messageId: message.id,
          json: item,
        );

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

  Future<bool> setReaction({
    required int conversationId,
    required int messageId,
    required String reaction,
  }) async {
    error = null;

    final key = '$conversationId';
    final messageKey = '$messageId';
    final previousReaction = conversationMessageReactions[key]?[messageKey];

    _setLocalReaction(
      conversationId: conversationId,
      messageId: messageKey,
      reaction: reaction,
    );

    try {
      await ChatApi.sendReaction(
        conversationId: conversationId,
        reactionTo: messageId,
        reaction: reaction,
      );

      return true;
    } catch (e) {
      error = e.toString();

      // Roll back optimistic UI when API fails.
      _setLocalReaction(
        conversationId: conversationId,
        messageId: messageKey,
        reaction: previousReaction ?? '',
      );

      notifyListeners();
      return false;
    }
  }

  /// Backward-compatible wrapper for old screen code.
  Future<void> sendReaction({
    required int conversationId,
    required int reactionTo,
    required String reaction,
  }) async {
    await setReaction(
      conversationId: conversationId,
      messageId: reactionTo,
      reaction: reaction,
    );
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

    _setSending(true);
    error = null;

    try {
      final response = await ChatApi.sendImages(
        conversationId: conversationId,
        images: images,
        caption: caption,
      );

      var realMessage = await _mapMessage(response.data);

      // Some backends return only one "media" URL even when multiple images
      // were uploaded. Messenger should still show the full selected album
      // immediately for the sender, so keep all local paths as a fallback.
      if (realMessage.type == MessageType.mediaAlbum &&
          ((realMessage.mediaUrls ?? []).length < images.length)) {
        realMessage = realMessage.copyWith(
          mediaUrls: images.map((image) => image.path).toList(),
        );
      }

      _syncMessageMetaFromJson(
        conversationId: conversationId,
        messageId: realMessage.id,
        json: response.data,
      );

      _replaceMessage(conversationId, temp.id, realMessage);
    } catch (e) {
      error = e.toString();

      final key = '$conversationId';
      conversationMessages[key]?.removeWhere((m) => m.id == temp.id);

      notifyListeners();
    }

    _setSending(false);
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

  Future<bool> deleteMessageForMe({
    required int conversationId,
    required int messageId,
  }) async {
    error = null;

    try {
      await ChatApi.deleteMessageForMe(
        conversationId: conversationId,
        messageId: messageId,
      );

      _removeLocalMessage(
        conversationId: conversationId,
        messageId: '$messageId',
      );

      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteMessageForEveryone({
    required int conversationId,
    required int messageId,
  }) async {
    error = null;

    try {
      await ChatApi.deleteMessageForEveryone(
        conversationId: conversationId,
        messageId: messageId,
      );

      _removeLocalMessage(
        conversationId: conversationId,
        messageId: '$messageId',
      );

      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> togglePinMessage({
    required int conversationId,
    required int messageId,
  }) async {
    error = null;

    final key = '$conversationId';
    final messageKey = '$messageId';
    final wasPinned = conversationPinnedMessageIds[key]?.contains(messageKey) ??
        false;

    _setLocalPinned(
      conversationId: conversationId,
      messageId: messageKey,
      pinned: !wasPinned,
    );

    try {
      final response = await ChatApi.togglePinMessage(
        conversationId: conversationId,
        messageId: messageId,
      );

      final responseData = response.data;
      final pinnedFromServer = _boolFromDynamic(
        responseData is Map ? responseData['pinned_by_me'] : null,
      );

      if (pinnedFromServer != null) {
        _setLocalPinned(
          conversationId: conversationId,
          messageId: messageKey,
          pinned: pinnedFromServer,
        );
      }

      return true;
    } catch (e) {
      error = e.toString();

      // Roll back optimistic UI when API fails.
      _setLocalPinned(
        conversationId: conversationId,
        messageId: messageKey,
        pinned: wasPinned,
      );

      notifyListeners();
      return false;
    }
  }

  List<ChatMessage> getMessagesForChat(String conversationId) {
    return conversationMessages[conversationId] ?? [];
  }


  bool _looksLikeTempOutgoingId(String id) {
    final cleanId = id.trim();

    if (cleanId.isEmpty) return false;

    // Local optimistic messages use DateTime.now().microsecondsSinceEpoch.
    // Server ids are normally shorter database ids.
    final asNumber = int.tryParse(cleanId);
    if (asNumber == null) return false;

    return cleanId.length >= 14;
  }

  bool _sameOutgoingPayload(ChatMessage a, ChatMessage b) {
    if (a.type != b.type) return false;

    switch (a.type) {
      case MessageType.text:
        return a.text.trim() == b.text.trim();

      case MessageType.image:
      case MessageType.video:
      case MessageType.file:
        final aName = (a.fileName ?? '').trim();
        final bName = (b.fileName ?? '').trim();

        if (aName.isNotEmpty && bName.isNotEmpty && aName == bName) {
          return true;
        }

        final aPath = (a.filePath ?? '').trim();
        final bPath = (b.filePath ?? '').trim();

        if (aPath.isNotEmpty &&
            bPath.isNotEmpty &&
            aPath.split('/').last == bPath.split('/').last) {
          return true;
        }

        return a.text.trim().isNotEmpty && a.text.trim() == b.text.trim();

      case MessageType.mediaAlbum:
        final aUrls = a.mediaUrls ?? const <String>[];
        final bUrls = b.mediaUrls ?? const <String>[];

        if (aUrls.isNotEmpty && bUrls.isNotEmpty) {
          final aFirst = aUrls.first.split('/').last;
          final bFirst = bUrls.first.split('/').last;

          if (aFirst == bFirst) return true;
        }

        return a.text.trim() == b.text.trim();

      case MessageType.audio:
        return true;

      case MessageType.call:
        return false;
    }
  }

  bool _mergeWithPendingOutgoingIfNeeded({
    required int conversationId,
    required ChatMessage realMessage,
  }) {
    if (!realMessage.isMe) return false;
    if (_looksLikeTempOutgoingId(realMessage.id)) return false;

    final key = '$conversationId';
    final list = conversationMessages[key];

    if (list == null || list.isEmpty) return false;

    final now = DateTime.now();

    final pendingIndex = list.lastIndexWhere((message) {
      if (!message.isMe) return false;
      if (!_looksLikeTempOutgoingId(message.id)) return false;
      if (message.type != realMessage.type) return false;

      final age = now.difference(message.sentAt).abs();
      if (age > const Duration(seconds: 45)) return false;

      return _sameOutgoingPayload(message, realMessage);
    });

    if (pendingIndex == -1) return false;

    list[pendingIndex] = realMessage;
    list.sort((a, b) => a.sentAt.compareTo(b.sentAt));

    final chatIndex = conversations.indexWhere((c) => c.id == key);

    if (chatIndex != -1) {
      conversations[chatIndex].message = _preview(realMessage);
      conversations[chatIndex].time = _formatChatTime(realMessage.sentAt);
    }

    notifyListeners();
    return true;
  }


  void _addLocalMessage(int conversationId, ChatMessage message) {
    if (message.type == MessageType.text && message.text.trim().isEmpty) {
      return;
    }

    final key = '$conversationId';

    conversationMessages.putIfAbsent(key, () => []);

    if (_mergeWithPendingOutgoingIfNeeded(
      conversationId: conversationId,
      realMessage: message,
    )) {
      return;
    }

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


  void _removeLocalMessage({
    required int conversationId,
    required String messageId,
  }) {
    final key = '$conversationId';

    conversationMessages[key]?.removeWhere((m) => m.id == messageId);
    conversationMessageReactions[key]?.remove(messageId);
    conversationPinnedMessageIds[key]?.remove(messageId);

    final chatIndex = conversations.indexWhere((c) => c.id == key);
    final messages = conversationMessages[key] ?? [];

    if (chatIndex != -1) {
      if (messages.isEmpty) {
        conversations[chatIndex].message = 'Start chatting';
        conversations[chatIndex].time = '';
      } else {
        final lastMessage = messages.last;
        conversations[chatIndex].message = _preview(lastMessage);
        conversations[chatIndex].time = _formatChatTime(lastMessage.sentAt);
      }
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

    String senderId = '';

    if (sender is Map) {
      senderId = sender['id']?.toString() ??
          sender['user_id']?.toString() ??
          sender['pk']?.toString() ??
          '';
    } else if (sender != null) {
      senderId = sender.toString();
    }

    if (senderId.trim().isEmpty || senderId.trim() == 'null') {
      senderId = json['sender_id']?.toString() ??
          json['user_id']?.toString() ??
          json['from_user_id']?.toString() ??
          json['created_by']?.toString() ??
          '';
    }

    final isOwnMessage = senderId.toString().trim() == myId.toString().trim() ||
        json['is_me'] == true ||
        json['isMe'] == true ||
        json['mine'] == true;

    final messageType = json['message_type']?.toString() ?? 'text';
    final type = _backendTypeToMessageType(messageType);

    return ChatMessage(
      id: '${json['id']}',
      type: type,
      text: json['text']?.toString() ?? json['message']?.toString() ?? '',
      isMe: isOwnMessage,
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
      filePath: type == MessageType.mediaAlbum
          ? null
          : json['media']?.toString() ??
              json['media_url']?.toString() ??
              json['file']?.toString(),
      fileName: json['file_name']?.toString() ?? json['media_name']?.toString(),
      fileSizeBytes: json['file_size'] is int ? json['file_size'] : null,
      mediaUrls: type == MessageType.mediaAlbum
          ? _mapMediaUrls(
              json['media_urls'] ??
                  json['media'] ??
                  json['files'] ??
                  json['album_items'] ??
                  json['attachments'],
            )
          : null,
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
    final cleanType = type.trim().toLowerCase();

    switch (cleanType) {
      case 'image':
      case 'photo':
        return MessageType.image;
      case 'media_album':
      case 'mediaalbum':
      case 'album':
      case 'images':
        return MessageType.mediaAlbum;
      case 'video':
        return MessageType.video;
      case 'audio':
      case 'voice':
      case 'voice_message':
        return MessageType.audio;
      case 'file':
      case 'document':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }

  void _syncMessageMetaFromJson({
    required int conversationId,
    required String messageId,
    required dynamic json,
  }) {
    if (json is! Map) return;

    final key = '$conversationId';

    final reaction = _reactionFromJson(json);
    if (reaction != null) {
      _setLocalReaction(
        conversationId: conversationId,
        messageId: messageId,
        reaction: reaction,
        notify: false,
      );
    }

    final pinned = _pinnedFromJson(json);
    if (pinned != null) {
      _setLocalPinned(
        conversationId: conversationId,
        messageId: messageId,
        pinned: pinned,
        notify: false,
      );
    } else {
      conversationMessageReactions.putIfAbsent(key, () => {});
      conversationPinnedMessageIds.putIfAbsent(key, () => <String>{});
    }
  }

  bool _isReactionPayload(dynamic data) {
    if (data is! Map) return false;

    final action = data['action']?.toString().toLowerCase() ?? '';
    final type = data['type']?.toString().toLowerCase() ?? '';
    final messageType = data['message_type']?.toString().toLowerCase() ?? '';

    return action == 'reaction' ||
        action == 'message_reaction' ||
        action == 'new_reaction' ||
        type == 'reaction' ||
        type == 'message_reaction' ||
        messageType == 'reaction';
  }

  bool _isDeletePayload(dynamic data) {
    if (data is! Map) return false;

    final action = data['action']?.toString().toLowerCase() ?? '';
    final type = data['type']?.toString().toLowerCase() ?? '';

    return action == 'delete_message' ||
        action == 'message_deleted' ||
        action == 'deleted_for_everyone' ||
        type == 'delete_message' ||
        type == 'message_deleted';
  }

  bool _isPinPayload(dynamic data) {
    if (data is! Map) return false;

    final action = data['action']?.toString().toLowerCase() ?? '';
    final type = data['type']?.toString().toLowerCase() ?? '';

    return action == 'pin_message' ||
        action == 'message_pinned' ||
        action == 'message_unpinned' ||
        type == 'pin_message' ||
        type == 'message_pinned' ||
        type == 'message_unpinned';
  }

  void _applyReactionPayload({
    required int conversationId,
    required dynamic data,
  }) {
    if (data is! Map) return;

    final rawMessageId = data['reaction_to'] ??
        data['message_id'] ??
        data['target_message_id'] ??
        data['id'];
    final messageId = rawMessageId?.toString() ?? '';

    if (messageId.trim().isEmpty) return;

    final reaction = data['reaction']?.toString() ??
        data['emoji']?.toString() ??
        data['my_reaction']?.toString() ??
        '';

    _setLocalReaction(
      conversationId: conversationId,
      messageId: messageId,
      reaction: reaction,
    );
  }

  void _applyDeletePayload({
    required int conversationId,
    required dynamic data,
  }) {
    if (data is! Map) return;

    final rawMessageId = data['message_id'] ?? data['id'];
    final messageId = rawMessageId?.toString() ?? '';

    if (messageId.trim().isEmpty) return;

    _removeLocalMessage(
      conversationId: conversationId,
      messageId: messageId,
    );
  }

  void _applyPinPayload({
    required int conversationId,
    required dynamic data,
  }) {
    if (data is! Map) return;

    final rawMessageId = data['message_id'] ?? data['id'];
    final messageId = rawMessageId?.toString() ?? '';

    if (messageId.trim().isEmpty) return;

    final pinned = _boolFromDynamic(data['pinned_by_me'] ?? data['pinned']) ??
        (data['action']?.toString().toLowerCase() == 'message_pinned' ||
            data['type']?.toString().toLowerCase() == 'message_pinned');

    _setLocalPinned(
      conversationId: conversationId,
      messageId: messageId,
      pinned: pinned,
    );
  }

  void _setLocalReaction({
    required int conversationId,
    required String messageId,
    required String reaction,
    bool notify = true,
  }) {
    final key = '$conversationId';
    conversationMessageReactions.putIfAbsent(key, () => {});

    final cleanReaction = reaction.trim();

    if (cleanReaction.isEmpty || cleanReaction == 'null') {
      conversationMessageReactions[key]!.remove(messageId);
    } else {
      conversationMessageReactions[key]![messageId] = cleanReaction;
    }

    if (notify) notifyListeners();
  }

  void _setLocalPinned({
    required int conversationId,
    required String messageId,
    required bool pinned,
    bool notify = true,
  }) {
    final key = '$conversationId';
    conversationPinnedMessageIds.putIfAbsent(key, () => <String>{});

    if (pinned) {
      conversationPinnedMessageIds[key]!.add(messageId);
    } else {
      conversationPinnedMessageIds[key]!.remove(messageId);
    }

    if (notify) notifyListeners();
  }

  String? _reactionFromJson(Map json) {
    final raw = json['my_reaction'] ?? json['reaction'] ?? json['emoji'];
    final reaction = raw?.toString().trim() ?? '';

    if (reaction.isNotEmpty && reaction != 'null') {
      return reaction;
    }

    final reactions = json['reactions'];
    final currentId = currentUserId?.toString();

    if (reactions is Map && currentId != null) {
      final myReaction = reactions[currentId]?.toString().trim() ?? '';
      if (myReaction.isNotEmpty && myReaction != 'null') {
        return myReaction;
      }
    }

    return null;
  }

  bool? _pinnedFromJson(Map json) {
    return _boolFromDynamic(
      json['pinned_by_me'] ??
          json['is_pinned'] ??
          json['pinned'] ??
          json['pinnedByMe'],
    );
  }

  bool? _boolFromDynamic(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;

    final cleanValue = value.toString().trim().toLowerCase();

    if (cleanValue == 'true' || cleanValue == '1' || cleanValue == 'yes') {
      return true;
    }

    if (cleanValue == 'false' || cleanValue == '0' || cleanValue == 'no') {
      return false;
    }

    return null;
  }

  List<String>? _mapMediaUrls(dynamic value) {
    if (value == null) return null;

    dynamic rawValue = value;

    if (rawValue is Map) {
      rawValue = rawValue['media_urls'] ??
          rawValue['urls'] ??
          rawValue['files'] ??
          rawValue['results'] ??
          rawValue['album_items'] ??
          rawValue['attachments'] ??
          rawValue['media'] ??
          rawValue['file'] ??
          rawValue['url'];
    }

    if (rawValue is List) {
      final urls = <String>[];

      for (final item in rawValue) {
        if (item == null) continue;

        if (item is Map) {
          final url = item['url'] ??
              item['file'] ??
              item['media'] ??
              item['media_url'] ??
              item['image'] ??
              item['path'];
          final cleanUrl = url?.toString().trim() ?? '';
          if (cleanUrl.isNotEmpty && cleanUrl != 'null') {
            urls.add(cleanUrl);
          }
          continue;
        }

        final cleanUrl = item.toString().trim();
        if (cleanUrl.isNotEmpty && cleanUrl != 'null') {
          urls.add(cleanUrl);
        }
      }

      return urls.isEmpty ? null : urls;
    }

    final singleUrl = rawValue.toString().trim();
    if (singleUrl.isEmpty || singleUrl == 'null') return null;

    if (singleUrl.contains(',') && !singleUrl.startsWith('http')) {
      final urls = singleUrl
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty && item != 'null')
          .toList();

      return urls.isEmpty ? null : urls;
    }

    return [singleUrl];
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