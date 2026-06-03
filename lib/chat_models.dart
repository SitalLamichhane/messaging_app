// chat_models.dart

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

class ChatUser {
  final String id;
  final String name;
  final String phone;
  final String avatarUrl;
  final bool isOnline;

  const ChatUser({
    required this.id,
    required this.name,
    this.phone = '',
    this.avatarUrl = '',
    this.isOnline = false,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: json['id'].toString(),
      name: json['name'] ?? json['username'] ?? '',
      phone: json['phone'] ?? '',
      avatarUrl: json['avatar'] ?? json['avatar_url'] ?? '',
      isOnline: json['is_online'] ?? false,
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

  /// Messenger-like multi photo album.
  /// Use this when type == MessageType.mediaAlbum.
  ///
  /// Example:
  /// [
  ///   "/storage/emulated/0/DCIM/image1.jpg",
  ///   "/storage/emulated/0/DCIM/image2.jpg",
  /// ]
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

  /// Messenger-like nickname support.
  /// Key = user id, Value = custom nickname.
  ///
  /// Example:
  /// {
  ///   "1": "Bro",
  ///   "2": "Captain",
  /// }
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
