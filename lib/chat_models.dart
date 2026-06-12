// lib/chat_models.dart

import 'package:flutter/foundation.dart';

enum MessageType {
  text,
  image,
  video,
  file,
  call,
  audio,
  mediaAlbum,
}

enum CallEntryType {
  voice,
  video,
}

enum CallEntryStatus {
  outgoing,
  incoming,
  missed,
}

String _stringValue(dynamic value) {
  if (value == null) return '';
  return value.toString();
}

bool _boolValue(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;

  final text = _stringValue(value).toLowerCase().trim();

  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;

  return fallback;
}

int _intValue(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();

  return int.tryParse(_stringValue(value)) ?? fallback;
}

DateTime _dateTimeValue(dynamic value) {
  final text = _stringValue(value).trim();

  if (text.isEmpty) return DateTime.now();

  return DateTime.tryParse(text)?.toLocal() ?? DateTime.now();
}

String _formatChatTime(DateTime dateTime) {
  final now = DateTime.now();
  final local = dateTime.toLocal();

  final sameDay =
      now.year == local.year && now.month == local.month && now.day == local.day;

  final hour = local.hour == 0
      ? 12
      : local.hour > 12
          ? local.hour - 12
          : local.hour;

  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';

  if (sameDay) {
    return '$hour:$minute $period';
  }

  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

String _profileImageFromUserMap(Map<dynamic, dynamic> user) {
  return _stringValue(
    user['profile_picture'] ??
        user['profilePicture'] ??
        user['avatarUrl'] ??
        user['avatar_url'] ??
        user['avatar'] ??
        user['image'] ??
        user['photo'] ??
        '',
  );
}

class ChatUser {
  final String id;
  final String name;
  final String phone;
  final String avatarUrl;
  final bool isOnline;

  // Messenger-like block status.
  // These values must come from ConversationMember object:
  // {
  //   id: 36,
  //   user: {...},
  //   is_blocked: true,
  //   blocked_by: 5,
  //   blocked_by_name: "sital don"
  // }
  final bool isBlocked;
  final int? blockedBy;
  final String blockedByName;

  const ChatUser({
    required this.id,
    required this.name,
    this.phone = '',
    this.avatarUrl = '',
    this.isOnline = false,
    this.isBlocked = false,
    this.blockedBy,
    this.blockedByName = '',
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];

    final bool parsedIsBlocked = _boolValue(json['is_blocked']);

    final int? parsedBlockedBy = json['blocked_by'] == null
        ? null
        : _intValue(json['blocked_by']);

    final String parsedBlockedByName = _stringValue(json['blocked_by_name']);

    // ConversationMember format:
    //
    // {
    //   id: member_id,
    //   user: {
    //     id: user_id,
    //     phone,
    //     full_name,
    //     profile_picture
    //   },
    //   nickname,
    //   display_name,
    //   is_admin,
    //   is_muted,
    //   is_blocked,
    //   blocked_by,
    //   blocked_by_name
    // }
    //
    // IMPORTANT:
    // is_blocked and blocked_by are outside user map.
    if (rawUser is Map) {
      final user = Map<String, dynamic>.from(rawUser);

      final parsedUserId = _stringValue(
        user['id'] ?? json['user_id'] ?? json['id'],
      );

      final parsedName = _stringValue(
        json['display_name'] ??
            json['nickname'] ??
            user['full_name'] ??
            user['name'] ??
            user['username'] ??
            '',
      );

      final parsedAvatar = _profileImageFromUserMap(user);

      debugPrint('========== MEMBER MAP ==========');
      debugPrint('MEMBER RAW JSON: $json');
      debugPrint('MAPPED MEMBER ID: $parsedUserId');
      debugPrint('MAPPED MEMBER NAME: $parsedName');
      debugPrint('MAPPED MEMBER AVATAR: $parsedAvatar');
      debugPrint('MAPPED MEMBER isBlocked: $parsedIsBlocked');
      debugPrint('MAPPED MEMBER blockedBy: $parsedBlockedBy');
      debugPrint('MAPPED MEMBER blockedByName: $parsedBlockedByName');
      debugPrint('================================');

      return ChatUser(
        id: parsedUserId,
        name: parsedName,
        phone: _stringValue(
          user['phone_number'] ?? user['phone'] ?? json['phone'] ?? '',
        ),
        avatarUrl: parsedAvatar,
        isOnline: _boolValue(
          user['is_online'] ?? json['is_online'],
        ),
        isBlocked: parsedIsBlocked,
        blockedBy: parsedBlockedBy,
        blockedByName: parsedBlockedByName,
      );
    }

    // Direct user format:
    //
    // {
    //   id,
    //   name/full_name/profile_name/username,
    //   profile_picture,
    //   is_blocked,
    //   blocked_by,
    //   blocked_by_name
    // }
    final parsedUserId = _stringValue(json['id']);

    final parsedName = _stringValue(
      json['name'] ??
          json['full_name'] ??
          json['profile_name'] ??
          json['username'] ??
          '',
    );

    final parsedAvatar = _profileImageFromUserMap(json);

    debugPrint('========== DIRECT USER MAP ==========');
    debugPrint('DIRECT RAW JSON: $json');
    debugPrint('MAPPED DIRECT USER ID: $parsedUserId');
    debugPrint('MAPPED DIRECT USER NAME: $parsedName');
    debugPrint('MAPPED DIRECT USER AVATAR: $parsedAvatar');
    debugPrint('MAPPED DIRECT USER isBlocked: $parsedIsBlocked');
    debugPrint('MAPPED DIRECT USER blockedBy: $parsedBlockedBy');
    debugPrint('MAPPED DIRECT USER blockedByName: $parsedBlockedByName');
    debugPrint('=====================================');

    return ChatUser(
      id: parsedUserId,
      name: parsedName,
      phone: _stringValue(json['phone_number'] ?? json['phone'] ?? ''),
      avatarUrl: parsedAvatar,
      isOnline: _boolValue(json['is_online']),
      isBlocked: parsedIsBlocked,
      blockedBy: parsedBlockedBy,
      blockedByName: parsedBlockedByName,
    );
  }

  ChatUser copyWith({
    String? id,
    String? name,
    String? phone,
    String? avatarUrl,
    bool? isOnline,
    bool? isBlocked,
    int? blockedBy,
    bool clearBlockedBy = false,
    String? blockedByName,
  }) {
    return ChatUser(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isOnline: isOnline ?? this.isOnline,
      isBlocked: isBlocked ?? this.isBlocked,
      blockedBy: clearBlockedBy ? null : blockedBy ?? this.blockedBy,
      blockedByName: blockedByName ?? this.blockedByName,
    );
  }
}

class ChatMessage {
  final String id;
  final MessageType type;
  final String text;
  final bool isMe;
  final DateTime sentAt;
  final bool isSeen;

  final String? senderId;
  final String? senderName;
  final String? senderAvatar;

  final String? filePath;
  final String? fileName;
  final int? fileSizeBytes;

  final List<String>? mediaUrls;

  final CallEntryType? callType;
  final Duration? callDuration;
  final bool? callAnswered;

  final String? audioPath;
  final Duration? audioDuration;

  final String? replyToMessageId;
  final String? replyPreview;
  final bool? replyToMe;

  ChatMessage({
    required this.id,
    required this.type,
    required this.text,
    required this.isMe,
    required this.sentAt,
    this.isSeen = false,
    this.senderId,
    this.senderName,
    this.senderAvatar,
    this.filePath,
    this.fileName,
    this.fileSizeBytes,
    this.mediaUrls,
    this.callType,
    this.callDuration,
    this.callAnswered,
    this.audioPath,
    this.audioDuration,
    this.replyToMessageId,
    this.replyPreview,
    this.replyToMe,
  });

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    String currentUserId = '',
  }) {
    final sender = json['sender'];
    final senderMap = sender is Map ? Map<String, dynamic>.from(sender) : null;

    final senderId = _stringValue(
      senderMap?['id'] ?? json['sender_id'] ?? json['sender'],
    );

    final messageType = _stringValue(
      json['message_type'] ?? json['type'] ?? 'text',
    );

    MessageType type;

    switch (messageType) {
      case 'image':
        type = MessageType.image;
        break;
      case 'video':
        type = MessageType.video;
        break;
      case 'file':
        type = MessageType.file;
        break;
      case 'call':
        type = MessageType.call;
        break;
      case 'audio':
        type = MessageType.audio;
        break;
      case 'mediaAlbum':
      case 'media_album':
        type = MessageType.mediaAlbum;
        break;
      case 'text':
      default:
        type = MessageType.text;
        break;
    }

    final media = json['media'];
    final mediaUrls = json['media_urls'];

    List<String>? parsedMediaUrls;

    if (mediaUrls is List) {
      parsedMediaUrls = mediaUrls.map((e) => _stringValue(e)).toList();
    }

    final filePathValue = _stringValue(
      media ?? json['file'] ?? json['file_path'],
    );

    final audioDurationValue = json['audio_duration'] ?? json['duration'];

    return ChatMessage(
      id: _stringValue(json['id']),
      type: type,
      text: _stringValue(json['text'] ?? json['message'] ?? ''),
      isMe: currentUserId.isNotEmpty && senderId == currentUserId,
      sentAt: _dateTimeValue(json['created_at'] ?? json['sent_at']),
      isSeen: _boolValue(json['is_seen'] ?? json['seen']),
      senderId: senderId,
      senderName: _stringValue(
        senderMap?['full_name'] ??
            senderMap?['name'] ??
            senderMap?['username'] ??
            json['sender_name'] ??
            '',
      ),
      senderAvatar: senderMap == null ? null : _profileImageFromUserMap(senderMap),
      filePath: filePathValue.trim().isEmpty ? null : filePathValue,
      fileName: _stringValue(json['file_name']).trim().isEmpty
          ? null
          : _stringValue(json['file_name']),
      fileSizeBytes: json['file_size'] == null && json['file_size_bytes'] == null
          ? null
          : _intValue(json['file_size'] ?? json['file_size_bytes']),
      mediaUrls: parsedMediaUrls,
      audioPath: type == MessageType.audio
          ? _stringValue(media ?? json['audio'] ?? json['audio_path'])
          : null,
      audioDuration: audioDurationValue == null
          ? null
          : Duration(
              milliseconds: (_intValue(audioDurationValue) * 1000).toInt(),
            ),
      replyToMessageId: _stringValue(json['reply_to']).trim().isEmpty
          ? null
          : _stringValue(json['reply_to']),
      replyPreview: _stringValue(
        json['reply_preview'] ??
            json['reply_to_data']?['text'] ??
            json['reply_to_data']?['message'] ??
            '',
      ).trim().isEmpty
          ? null
          : _stringValue(
              json['reply_preview'] ??
                  json['reply_to_data']?['text'] ??
                  json['reply_to_data']?['message'] ??
                  '',
            ),
      replyToMe:
          json['reply_to_me'] == null ? null : _boolValue(json['reply_to_me']),
    );
  }

  ChatMessage copyWith({
    String? id,
    MessageType? type,
    String? text,
    bool? isMe,
    DateTime? sentAt,
    bool? isSeen,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? filePath,
    String? fileName,
    int? fileSizeBytes,
    List<String>? mediaUrls,
    CallEntryType? callType,
    Duration? callDuration,
    bool? callAnswered,
    String? audioPath,
    Duration? audioDuration,
    String? replyToMessageId,
    String? replyPreview,
    bool? replyToMe,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      isMe: isMe ?? this.isMe,
      sentAt: sentAt ?? this.sentAt,
      isSeen: isSeen ?? this.isSeen,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      callType: callType ?? this.callType,
      callDuration: callDuration ?? this.callDuration,
      callAnswered: callAnswered ?? this.callAnswered,
      audioPath: audioPath ?? this.audioPath,
      audioDuration: audioDuration ?? this.audioDuration,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyPreview: replyPreview ?? this.replyPreview,
      replyToMe: replyToMe ?? this.replyToMe,
    );
  }
}

class ChatItem {
  final String id;
  String name;
  final String phone;
  final String avatarUrl;
  final bool isOnline;
  final bool isGroup;

  final List<ChatUser> members;
  final List<String> adminIds;

  Map<String, String> memberNicknames;

  String message;
  String time;
  int unreadCount;

  final List<ChatMessage> messages;

  ChatItem({
    required this.id,
    required this.name,
    required this.phone,
    required this.avatarUrl,
    this.isOnline = true,
    this.isGroup = false,
    this.members = const [],
    this.adminIds = const [],
    Map<String, String>? memberNicknames,
    required this.message,
    required this.time,
    this.unreadCount = 0,
    List<ChatMessage>? messages,
  })  : memberNicknames = memberNicknames ?? {},
        messages = messages ?? [];

  factory ChatItem.fromJson(
    Map<String, dynamic> json, {
    String currentUserId = '',
  }) {
    final type = _stringValue(json['type']);
    final isGroup = type == 'group' || _boolValue(json['is_group']);

    final membersJson = json['members'];
    final members = <ChatUser>[];

    if (membersJson is List) {
      for (final item in membersJson) {
        if (item is Map<String, dynamic>) {
          members.add(ChatUser.fromJson(item));
        } else if (item is Map) {
          members.add(ChatUser.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    ChatUser? otherUser;

    if (!isGroup) {
      for (final member in members) {
        if (currentUserId.isEmpty || member.id != currentUserId) {
          otherUser = member;
          break;
        }
      }
    }

    final lastMessage = json['last_message'];
    String preview = _stringValue(json['message'] ?? '');
    String time = _stringValue(json['time'] ?? '');

    if (lastMessage is Map) {
      final lastMessageMap = Map<String, dynamic>.from(lastMessage);

      preview = _stringValue(
        lastMessageMap['text'] ??
            lastMessageMap['message'] ??
            lastMessageMap['message_type'] ??
            preview,
      );

      final lastDate = _dateTimeValue(
        lastMessageMap['created_at'] ?? lastMessageMap['sent_at'],
      );

      time = _formatChatTime(lastDate);
    }

    if (preview.trim().isEmpty) {
      preview = 'No messages yet';
    }

    if (time.trim().isEmpty) {
      time = _formatChatTime(
        _dateTimeValue(json['updated_at'] ?? json['created_at']),
      );
    }

    final rawName = _stringValue(json['name']).trim();

    final name = isGroup
        ? (rawName.isNotEmpty ? rawName : 'Group')
        : (otherUser?.name.trim().isNotEmpty == true
            ? otherUser!.name
            : rawName.isNotEmpty
                ? rawName
                : 'Unknown');

    final phone = isGroup
        ? ''
        : _stringValue(
            otherUser?.phone ??
                json['phone_number'] ??
                json['phone'] ??
                '',
          );

    final directAvatar = _stringValue(
      json['profile_picture'] ??
          json['avatarUrl'] ??
          json['avatar_url'] ??
          json['image'] ??
          json['photo'] ??
          '',
    );

    final avatarUrl = directAvatar.trim().isNotEmpty
        ? directAvatar
        : isGroup
            ? _stringValue(
                json['image'] ??
                    json['group_image'] ??
                    json['avatar'] ??
                    json['avatar_url'] ??
                    '',
              )
            : (otherUser?.avatarUrl ?? '');

    debugPrint('========== CHAT MAP ==========');
    debugPrint('MAPPED CHAT ID: ${_stringValue(json['id'])}');
    debugPrint('MAPPED CHAT NAME: $name');
    debugPrint('MAPPED CHAT AVATAR: $avatarUrl');
    debugPrint('MAPPED CHAT MEMBERS: ${members.length}');
    for (final member in members) {
      debugPrint(
        'CHAT MEMBER ${member.id} ${member.name} '
        'isBlocked=${member.isBlocked} '
        'blockedBy=${member.blockedBy} '
        'blockedByName=${member.blockedByName}',
      );
    }
    debugPrint('==============================');

    return ChatItem(
      id: _stringValue(json['id']),
      name: name,
      phone: phone,
      avatarUrl: avatarUrl,
      isOnline: otherUser?.isOnline ?? _boolValue(json['is_online'], fallback: true),
      isGroup: isGroup,
      members: members,
      adminIds: _parseAdminIds(json),
      memberNicknames: _parseMemberNicknames(json),
      message: preview,
      time: time,
      unreadCount: _intValue(json['unread_count']),
      messages: const [],
    );
  }

  static List<String> _parseAdminIds(Map<String, dynamic> json) {
    final value = json['admin_ids'] ?? json['admins'];

    if (value is List) {
      return value.map((e) => _stringValue(e)).toList();
    }

    return const [];
  }

  static Map<String, String> _parseMemberNicknames(Map<String, dynamic> json) {
    final value = json['member_nicknames'] ?? json['nicknames'];

    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(
          _stringValue(key),
          _stringValue(value),
        ),
      );
    }

    return {};
  }

  String get groupInitials {
    if (!isGroup || name.trim().isEmpty) return '';

    final parts = name.trim().split(RegExp(r'\s+'));

    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String get groupSubtitle {
    if (!isGroup) return isOnline ? 'Active now' : 'Offline';

    final count = members.length;
    if (count <= 0) return 'Group chat';

    return '$count members';
  }

  String nicknameFor(ChatUser user) {
    final nickname = memberNicknames[user.id]?.trim();

    if (nickname != null && nickname.isNotEmpty) {
      return nickname;
    }

    return user.name;
  }

  ChatItem copyWith({
    String? id,
    String? name,
    String? phone,
    String? avatarUrl,
    bool? isOnline,
    bool? isGroup,
    List<ChatUser>? members,
    List<String>? adminIds,
    Map<String, String>? memberNicknames,
    String? message,
    String? time,
    int? unreadCount,
    List<ChatMessage>? messages,
  }) {
    return ChatItem(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isOnline: isOnline ?? this.isOnline,
      isGroup: isGroup ?? this.isGroup,
      members: members ?? this.members,
      adminIds: adminIds ?? this.adminIds,
      memberNicknames: memberNicknames ?? this.memberNicknames,
      message: message ?? this.message,
      time: time ?? this.time,
      unreadCount: unreadCount ?? this.unreadCount,
      messages: messages ?? this.messages,
    );
  }
}

class CallEntry {
  final String id;
  final String chatId;
  final String name;
  final String avatarUrl;
  final bool isGroup;
  final String relativeTime;
  final CallEntryType type;
  final CallEntryStatus status;
  final String? filePath;

  CallEntry({
    required this.id,
    required this.chatId,
    required this.name,
    required this.avatarUrl,
    required this.isGroup,
    required this.relativeTime,
    required this.type,
    required this.status,
    this.filePath,
  });

  String get groupLabel {
    if (!isGroup || name.trim().isEmpty) return '';

    final parts = name.trim().split(RegExp(r'\s+'));

    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}