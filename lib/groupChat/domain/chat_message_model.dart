enum ChatMessageType {
  text,
  image,
  video,
  audio,
  file,
  reply,
  reaction,
  unknown;

  static ChatMessageType fromJson(Object? value) {
    final raw = value?.toString().trim().toLowerCase();

    for (final item in ChatMessageType.values) {
      if (item.name == raw) {
        return item;
      }
    }

    return ChatMessageType.unknown;
  }
}

class ChatAttachmentDto {
  final int? id;
  final String url;
  final String thumbnailUrl;
  final String fileName;
  final String mimeType;
  final int? fileSize;
  final ChatMessageType type;

  const ChatAttachmentDto({
    this.id,
    required this.url,
    required this.thumbnailUrl,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.type,
  });

  factory ChatAttachmentDto.fromJson(
    Map<String, dynamic> json,
  ) {
    return ChatAttachmentDto(
      id: _asInt(json['id']),
      url: _firstString([
        json['file'],
        json['url'],
        json['media'],
      ]),
      thumbnailUrl: _firstString([
        json['thumbnail'],
        json['thumbnail_url'],
      ]),
      fileName: _firstString([
        json['file_name'],
        json['name'],
      ]),
      mimeType: _firstString([
        json['mime_type'],
        json['content_type'],
      ]),
      fileSize: _asInt(json['file_size']),
      type: ChatMessageType.fromJson(
        json['attachment_type'] ??
            json['message_type'] ??
            json['type'],
      ),
    );
  }
}

class ChatMessageDto {
  final int id;
  final int? conversationId;
  final int senderId;
  final String senderName;
  final String senderAvatar;
  final ChatMessageType type;
  final String text;
  final bool isEdited;
  final bool isDeleted;
  final DateTime? createdAt;
  final List<ChatAttachmentDto> attachments;
  final int? replyToId;
  final String reaction;

  const ChatMessageDto({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.type,
    required this.text,
    required this.isEdited,
    required this.isDeleted,
    required this.createdAt,
    required this.attachments,
    required this.replyToId,
    required this.reaction,
  });

  factory ChatMessageDto.fromJson(
    Map<String, dynamic> json,
  ) {
    final senderRaw = json['sender'];

    int senderId = _asInt(json['sender_id']) ?? 0;
    String senderName = _firstString([
      json['sender_name'],
    ]);
    String senderAvatar = _firstString([
      json['sender_avatar'],
    ]);

    if (senderRaw is Map) {
      final sender = Map<String, dynamic>.from(senderRaw);

      senderId = _asInt(sender['id']) ??
          _asInt(sender['user_id']) ??
          senderId;

      senderName = _firstString([
        sender['full_name'],
        sender['name'],
        sender['username'],
        senderName,
      ]);

      senderAvatar = _firstString([
        sender['profile_picture'],
        sender['avatar'],
        sender['avatar_url'],
        senderAvatar,
      ]);
    } else {
      senderId = _asInt(senderRaw) ?? senderId;
    }

    final parsedAttachments = <ChatAttachmentDto>[];

    final attachmentsRaw = json['attachments'];

    if (attachmentsRaw is List) {
      for (final item in attachmentsRaw) {
        if (item is Map) {
          parsedAttachments.add(
            ChatAttachmentDto.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
    }

    // Your backend keeps Message.media for exactly one uploaded file.
    if (parsedAttachments.isEmpty) {
      final media = _firstString([
        json['media'],
        json['file'],
      ]);

      if (media.isNotEmpty) {
        parsedAttachments.add(
          ChatAttachmentDto(
            id: null,
            url: media,
            thumbnailUrl: _firstString([
              json['thumbnail'],
              json['thumbnail_url'],
            ]),
            fileName: _firstString([
              json['file_name'],
            ]),
            mimeType: _firstString([
              json['mime_type'],
            ]),
            fileSize: _asInt(json['file_size']),
            type: ChatMessageType.fromJson(
              json['message_type'],
            ),
          ),
        );
      }
    }

    final replyRaw = json['reply_to'];

    return ChatMessageDto(
      id: _asInt(json['id']) ??
          _asInt(json['message_id']) ??
          0,
      conversationId:
          _asInt(json['conversation_id']) ??
              _asInt(json['conversation']),
      senderId: senderId,
      senderName: senderName,
      senderAvatar: senderAvatar,
      type: ChatMessageType.fromJson(
        json['message_type'] ?? json['type'],
      ),
      text: (json['text'] ?? '').toString(),
      isEdited: _asBool(json['is_edited']),
      isDeleted: _asBool(json['is_deleted']),
      createdAt: _asDate(
        json['created_at'] ?? json['timestamp'],
      ),
      attachments: parsedAttachments,
      replyToId: replyRaw is Map
          ? _asInt(replyRaw['id'])
          : _asInt(replyRaw),
      reaction: (json['reaction'] ?? '').toString(),
    );
  }

  ChatMessageDto copyWith({
    String? text,
    bool? isEdited,
    bool? isDeleted,
  }) {
    return ChatMessageDto(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      senderAvatar: senderAvatar,
      type: type,
      text: text ?? this.text,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
      attachments: attachments,
      replyToId: replyToId,
      reaction: reaction,
    );
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  final raw = value?.toString().toLowerCase();
  return raw == '1' || raw == 'true' || raw == 'yes';
}

DateTime? _asDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

String _firstString(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty && text != 'null') {
      return text;
    }
  }
  return '';
}
