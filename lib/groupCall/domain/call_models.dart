enum CallType {
  audio,
  video;

  static CallType fromJson(Object? value) {
    return value?.toString().toLowerCase() == 'video'
        ? CallType.video
        : CallType.audio;
  }

  String get apiValue => name;
}

enum CallSessionStatus {
  ringing,
  accepted,
  rejected,
  ended,
  missed,
  cancelled,
  unknown;

  static CallSessionStatus fromJson(Object? value) {
    final raw = value?.toString().toLowerCase();
    for (final item in CallSessionStatus.values) {
      if (item.name == raw) return item;
    }
    return CallSessionStatus.unknown;
  }

  bool get isTerminal => {
        CallSessionStatus.rejected,
        CallSessionStatus.ended,
        CallSessionStatus.missed,
        CallSessionStatus.cancelled,
      }.contains(this);

  bool get isActive =>
      this == CallSessionStatus.ringing ||
      this == CallSessionStatus.accepted;
}

enum CallParticipantStatus {
  invited,
  ringing,
  joined,
  declined,
  left,
  missed,
  unknown;

  static CallParticipantStatus fromJson(Object? value) {
    final raw = value?.toString().toLowerCase();
    for (final item in CallParticipantStatus.values) {
      if (item.name == raw) return item;
    }
    return CallParticipantStatus.unknown;
  }
}

class CallParticipantDto {
  final int userId;
  final String name;
  final String profilePicture;
  final CallParticipantStatus status;
  final DateTime? joinedAt;
  final DateTime? leftAt;

  const CallParticipantDto({
    required this.userId,
    required this.name,
    required this.profilePicture,
    required this.status,
    this.joinedAt,
    this.leftAt,
  });

  factory CallParticipantDto.fromJson(Map<String, dynamic> json) {
    return CallParticipantDto(
      userId: _asInt(json['user_id']) ?? 0,
      name: (json['name'] ?? '').toString(),
      profilePicture: (json['profile_picture'] ?? '').toString(),
      status: CallParticipantStatus.fromJson(json['status']),
      joinedAt: _asDate(json['joined_at']),
      leftAt: _asDate(json['left_at']),
    );
  }
}

class CallSessionDto {
  final int callId;
  final String callUuid;
  final int conversationId;
  final String conversationType;
  final int callerId;
  final int? receiverId;
  final CallType callType;
  final CallSessionStatus status;
  final String roomName;
  final String conversationName;
  final String callerName;
  final String callerAvatar;
  final String myParticipantStatus;
  final List<CallParticipantDto> participants;

  const CallSessionDto({
    required this.callId,
    required this.callUuid,
    required this.conversationId,
    required this.conversationType,
    required this.callerId,
    required this.receiverId,
    required this.callType,
    required this.status,
    this.roomName = '',
    this.conversationName = '',
    this.callerName = '',
    this.callerAvatar = '',
    this.myParticipantStatus = '',
    this.participants = const [],
  });

  bool get isGroup => conversationType == 'group';
  bool get isVideo => callType == CallType.video;
  bool get isActive => status.isActive;

  factory CallSessionDto.fromJson(Map<String, dynamic> json) {
    final list = (json['participants'] as List?)
            ?.whereType<Map>()
            .map((e) => CallParticipantDto.fromJson(
                  Map<String, dynamic>.from(e),
                ))
            .toList() ??
        const <CallParticipantDto>[];

    return CallSessionDto(
      callId: _asInt(json['call_id']) ?? 0,
      callUuid: (json['call_uuid'] ?? '').toString(),
      conversationId: _asInt(json['conversation_id']) ?? 0,
      conversationType: (json['conversation_type'] ?? 'group').toString(),
      callerId: _asInt(json['caller_id']) ?? 0,
      receiverId: _asInt(json['receiver_id']),
      callType: CallType.fromJson(
        json['call_type'] ??
            ((json['is_video_call'] == true ||
                    json['is_video_call']?.toString() == 'true')
                ? 'video'
                : 'audio'),
      ),
      status: CallSessionStatus.fromJson(json['status']),
      roomName: (json['room_name'] ??
              json['livekit_room_name'] ??
              '')
          .toString(),
      conversationName: (json['conversation_name'] ?? '').toString(),
      callerName: (json['caller_name'] ?? '').toString(),
      callerAvatar: (json['caller_avatar'] ?? '').toString(),
      myParticipantStatus:
          (json['my_participant_status'] ?? '').toString(),
      participants: list,
    );
  }

  CallSessionDto copyWith({
    CallSessionStatus? status,
    String? roomName,
    String? conversationName,
    String? callerName,
    String? callerAvatar,
    String? myParticipantStatus,
    List<CallParticipantDto>? participants,
  }) {
    return CallSessionDto(
      callId: callId,
      callUuid: callUuid,
      conversationId: conversationId,
      conversationType: conversationType,
      callerId: callerId,
      receiverId: receiverId,
      callType: callType,
      status: status ?? this.status,
      roomName: roomName ?? this.roomName,
      conversationName: conversationName ?? this.conversationName,
      callerName: callerName ?? this.callerName,
      callerAvatar: callerAvatar ?? this.callerAvatar,
      myParticipantStatus:
          myParticipantStatus ?? this.myParticipantStatus,
      participants: participants ?? this.participants,
    );
  }
}

class ActiveCallResult {
  final bool active;
  final CallSessionDto? call;

  const ActiveCallResult({
    required this.active,
    required this.call,
  });

  factory ActiveCallResult.fromJson(Map<String, dynamic> json) {
    final active = json['active'] == true ||
        json['active']?.toString().toLowerCase() == 'true';

    final rawCall = json['call'];
    return ActiveCallResult(
      active: active,
      call: rawCall is Map
          ? CallSessionDto.fromJson(
              Map<String, dynamic>.from(rawCall),
            )
          : null,
    );
  }
}

class LiveKitCredentials {
  final String serverUrl;
  final String participantToken;
  final String roomName;
  final int callId;
  final String callUuid;
  final CallType callType;
  final String participantIdentity;

  const LiveKitCredentials({
    required this.serverUrl,
    required this.participantToken,
    required this.roomName,
    required this.callId,
    required this.callUuid,
    required this.callType,
    required this.participantIdentity,
  });

  factory LiveKitCredentials.fromJson(Map<String, dynamic> json) {
    return LiveKitCredentials(
      serverUrl: (json['server_url'] ?? '').toString(),
      participantToken:
          (json['participant_token'] ?? '').toString(),
      roomName: (json['room_name'] ?? '').toString(),
      callId: _asInt(json['call_id']) ?? 0,
      callUuid: (json['call_uuid'] ?? '').toString(),
      callType: CallType.fromJson(
        json['call_type'] ??
            ((json['is_video_call'] == true ||
                    json['is_video_call']?.toString() == 'true')
                ? 'video'
                : 'audio'),
      ),
      participantIdentity:
          (json['participant_identity'] ?? '').toString(),
    );
  }
}

class IncomingCallPayload {
  final CallSessionDto call;

  const IncomingCallPayload(this.call);

  factory IncomingCallPayload.fromMap(Map<String, dynamic> data) {
    return IncomingCallPayload(
      CallSessionDto.fromJson(data),
    );
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

DateTime? _asDate(Object? value) {
  if (value == null || value.toString().isEmpty) return null;
  return DateTime.tryParse(value.toString());
}
