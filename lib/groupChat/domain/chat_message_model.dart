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
    final raw = value?.toString().toLowerCase().trim();

    for (final item in values) {
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
      id: _int(json['id']),
      url: _string([
        json['url'],
        json['file'],
        json['media'],
      ]),
      thumbnailUrl: _string([
        json['thumbnail'],
        json['thumbnail_url'],
      ]),
      fileName: _string([
        json['file_name'],
        json['name'],
      ]),
      mimeType: _string([
        json['mime_type'],
        json['content_type'],
      ]),
      fileSize: _int(
        json['file_size'] ?? json['size'],
      ),
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

  final bool delivered;
  final bool seen;

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
    required this.delivered,
    required this.seen,
    required this.createdAt,
    required this.attachments,
    required this.replyToId,
    required this.reaction,
  });

  factory ChatMessageDto.fromJson(
    Map<String, dynamic> json,
  ) {
    final sender = json['sender'];

    int senderId =
        _int(json['sender_id']) ?? 0;

    String senderName = _string([
      json['sender_name'],
    ]);

    String senderAvatar = _string([
      json['sender_avatar'],
      json['avatar'],
    ]);

    if (sender is Map) {
      senderId =
          _int(sender['id']) ?? senderId;

      senderName = _string([
        sender['name'],
        sender['username'],
        sender['full_name'],
        senderName,
      ]);

      senderAvatar = _string([
        sender['avatar'],
        sender['profile_picture'],
        sender['profile_image'],
        senderAvatar,
      ]);
    }

    final attachments =
        <ChatAttachmentDto>[];

    final rawAttachments =
        json['attachments'];

    if (rawAttachments is List) {
      for (final item in rawAttachments) {
        if (item is Map) {
          final attachment =
              ChatAttachmentDto.fromJson(
            Map<String, dynamic>.from(item),
          );

          if (attachment.url.isNotEmpty) {
            attachments.add(attachment);
          }
        }
      }
    }

    if (attachments.isEmpty) {
      final mediaUrl = _string([
        json['media'],
        json['file'],
        json['url'],
      ]);

      if (mediaUrl.isNotEmpty) {
        attachments.add(
          ChatAttachmentDto(
            id: null,
            url: mediaUrl,
            thumbnailUrl: _string([
              json['thumbnail'],
              json['thumbnail_url'],
            ]),
            fileName: _string([
              json['file_name'],
              json['name'],
            ]),
            mimeType: _string([
              json['mime_type'],
              json['content_type'],
            ]),
            fileSize: _int(
              json['file_size'] ??
                  json['size'],
            ),
            type: ChatMessageType.fromJson(
              json['message_type'] ??
                  json['type'],
            ),
          ),
        );
      }
    }

    return ChatMessageDto(
      id: _int(json['id']) ?? 0,

      conversationId: _int(
        json['conversation_id'] ??
            json['conversation'],
      ),

      senderId: senderId,

      senderName: senderName,

      senderAvatar: senderAvatar,

      type: ChatMessageType.fromJson(
        json['message_type'] ??
            json['type'],
      ),

      text: (json['text'] ?? '').toString(),

      isEdited: _bool(
        json['is_edited'] ??
            json['edited'],
      ),

      isDeleted: _bool(
        json['is_deleted'] ??
            json['deleted'],
      ),

      delivered: _bool(
        json['delivered'] ??
            json['is_delivered'],
      ),

      seen: _bool(
        json['seen'] ??
            json['is_seen'] ??
            json['read'] ??
            json['is_read'],
      ),

      createdAt: _date(
        json['created_at'] ??
            json['timestamp'],
      ),

      attachments: attachments,

      replyToId: _replyId(
        json['reply_to'] ??
            json['reply_to_id'],
      ),

      reaction:
          (json['reaction'] ?? '').toString(),
    );
  }

  ChatMessageDto copyWith({
    String? text,
    bool? isDeleted,
    bool? seen,
    bool? delivered,
    bool? isEdited,
  }) {
    return ChatMessageDto(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      senderAvatar: senderAvatar,
      type: type,
      text: text ?? this.text,
      isEdited:
          isEdited ?? this.isEdited,
      isDeleted:
          isDeleted ?? this.isDeleted,
      delivered:
          delivered ?? this.delivered,
      seen:
          seen ?? this.seen,
      createdAt: createdAt,
      attachments: attachments,
      replyToId: replyToId,
      reaction: reaction,
    );
  }
}

int? _replyId(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is Map) {
    return _int(
      value['id'] ??
          value['message_id'],
    );
  }

  return _int(value);
}

int? _int(dynamic value) {
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

bool _bool(dynamic value) {
  if (value == null) {
    return false;
  }

  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final raw =
      value.toString().toLowerCase().trim();

  return raw == 'true' ||
      raw == '1' ||
      raw == 'yes';
}

DateTime? _date(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is DateTime) {
    return value;
  }

  return DateTime.tryParse(
    value.toString(),
  );
}

String _string(
  List<dynamic> values,
) {
  for (final value in values) {
    final text =
        value?.toString().trim() ?? '';

    if (text.isNotEmpty &&
        text.toLowerCase() != 'null') {
      return text;
    }
  }

  return '';
}