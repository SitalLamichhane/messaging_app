enum CallType {
  audio,
  video;

  static CallType fromJson(Object? value) {
    return value?.toString().toLowerCase() == 'video'
        ? CallType.video
        : CallType.audio;
  }
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
      if (item.name == raw) {
        return item;
      }
    }

    return CallSessionStatus.unknown;
  }

  bool get isActive =>
      this == CallSessionStatus.ringing ||
      this == CallSessionStatus.accepted;

  bool get isTerminal => {
        CallSessionStatus.rejected,
        CallSessionStatus.ended,
        CallSessionStatus.missed,
        CallSessionStatus.cancelled,
      }.contains(this);
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
      if (item.name == raw) {
        return item;
      }
    }

    return CallParticipantStatus.unknown;
  }
}

// ============================================================
// CALL PARTICIPANT
// ============================================================

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

  factory CallParticipantDto.fromJson(
    Map<String, dynamic> json,
  ) {
    return CallParticipantDto(
      userId: _asInt(json['user_id']) ?? 0,
      name: (json['name'] ?? '').toString(),
      profilePicture:
          (json['profile_picture'] ?? '').toString(),
      status: CallParticipantStatus.fromJson(
        json['status'],
      ),
      joinedAt: _asDate(
        json['joined_at'],
      ),
      leftAt: _asDate(
        json['left_at'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      'profile_picture': profilePicture,
      'status': status.name,
      'joined_at': joinedAt?.toIso8601String(),
      'left_at': leftAt?.toIso8601String(),
    };
  }
}

// ============================================================
// CALL SESSION
// ============================================================

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

  bool get isGroup =>
      conversationType.toLowerCase() == 'group';

  bool get isVideo =>
      callType == CallType.video;

  bool get isActive =>
      status.isActive;

  factory CallSessionDto.fromJson(
    Map<String, dynamic> json,
  ) {
    final participants = <CallParticipantDto>[];

    final rawParticipants =
        json['participants'];

    if (rawParticipants is List) {
      for (final item in rawParticipants) {
        if (item is Map) {
          participants.add(
            CallParticipantDto.fromJson(
              Map<String, dynamic>.from(
                item,
              ),
            ),
          );
        }
      }
    }

    final isGroupCall = _asBool(
      json['is_group_call'],
    );

    final isVideoCall = _asBool(
      json['is_video_call'],
    );

    return CallSessionDto(
      callId:
          _asInt(json['call_id']) ??
          _asInt(json['id']) ??
          0,

      callUuid:
          (json['call_uuid'] ??
                  json['uuid'] ??
                  '')
              .toString(),

      conversationId:
          _asInt(
            json['conversation_id'],
          ) ??
          0,

      conversationType:
          (json['conversation_type'] ??
                  (isGroupCall
                      ? 'group'
                      : 'private'))
              .toString(),

      callerId:
          _asInt(json['caller_id']) ??
          0,

      receiverId:
          _asInt(json['receiver_id']),

      callType: CallType.fromJson(
        json['call_type'] ??
            (isVideoCall
                ? 'video'
                : 'audio'),
      ),

      status:
          CallSessionStatus.fromJson(
        json['status'],
      ),

      roomName:
          (json['room_name'] ??
                  json['livekit_room_name'] ??
                  '')
              .toString(),

      conversationName:
          (json['conversation_name'] ??
                  json['group_name'] ??
                  '')
              .toString(),

      callerName:
          (json['caller_name'] ??
                  json['callerName'] ??
                  '')
              .toString(),

      callerAvatar:
          (json['caller_avatar'] ??
                  json['callerAvatar'] ??
                  '')
              .toString(),

      myParticipantStatus:
          (json['my_participant_status'] ??
                  '')
              .toString(),

      participants: participants,
    );
  }

  CallSessionDto copyWith({
    CallSessionStatus? status,
    String? roomName,
    String? conversationName,
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

      status:
          status ?? this.status,

      roomName:
          roomName ?? this.roomName,

      conversationName:
          conversationName ??
          this.conversationName,

      callerName: callerName,
      callerAvatar: callerAvatar,

      myParticipantStatus:
          myParticipantStatus ??
          this.myParticipantStatus,

      participants:
          participants ??
          this.participants,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'call_id': callId,
      'call_uuid': callUuid,
      'conversation_id': conversationId,
      'conversation_type': conversationType,
      'caller_id': callerId,
      'receiver_id': receiverId,
      'call_type': callType.name,
      'is_video_call': isVideo,
      'is_group_call': isGroup,
      'status': status.name,
      'room_name': roomName,
      'conversation_name': conversationName,
      'caller_name': callerName,
      'caller_avatar': callerAvatar,
      'my_participant_status':
          myParticipantStatus,
      'participants': participants
          .map(
            (participant) =>
                participant.toJson(),
          )
          .toList(),
    };
  }
}

// ============================================================
// ACTIVE CALL RESULT
// ============================================================

class ActiveCallResult {
  final bool active;
  final CallSessionDto? call;

  const ActiveCallResult({
    required this.active,
    required this.call,
  });

  factory ActiveCallResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final active =
        _asBool(json['active']);

    final rawCall =
        json['call'];

    return ActiveCallResult(
      active: active,
      call: rawCall is Map
          ? CallSessionDto.fromJson(
              Map<String, dynamic>.from(
                rawCall,
              ),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'active': active,
      'call': call?.toJson(),
    };
  }
}

// ============================================================
// LIVEKIT CREDENTIALS
// ============================================================

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

  factory LiveKitCredentials.fromJson(
    Map<String, dynamic> json,
  ) {
    return LiveKitCredentials(
      serverUrl:
          (json['server_url'] ??
                  json['url'] ??
                  '')
              .toString(),

      participantToken:
          (json['participant_token'] ??
                  json['token'] ??
                  '')
              .toString(),

      roomName:
          (json['room_name'] ??
                  json['livekit_room_name'] ??
                  '')
              .toString(),

      callId:
          _asInt(json['call_id']) ??
          0,

      callUuid:
          (json['call_uuid'] ??
                  '')
              .toString(),

      callType:
          CallType.fromJson(
        json['call_type'] ??
            (_asBool(
              json['is_video_call'],
            )
                ? 'video'
                : 'audio'),
      ),

      participantIdentity:
          (json['participant_identity'] ??
                  json['identity'] ??
                  '')
              .toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'server_url': serverUrl,
      'participant_token':
          participantToken,
      'room_name': roomName,
      'call_id': callId,
      'call_uuid': callUuid,
      'call_type': callType.name,
      'is_video_call':
          callType == CallType.video,
      'participant_identity':
          participantIdentity,
    };
  }
}

// ============================================================
// INCOMING CALL PUSH PAYLOAD
// ============================================================
//
// Used by:
//
// lib/calls/data/call_push_service.dart
//
// This is mainly for routing GROUP incoming-call FCM events.
// Existing private-call FCM / CallKit handling can remain separate.
// ============================================================

class IncomingCallPayload {
  final int callId;
  final String callUuid;

  final int conversationId;

  final int callerId;
  final String callerName;
  final String callerAvatar;

  final CallType callType;

  final bool isGroupCall;

  final String conversationName;
  final String conversationAvatar;

  const IncomingCallPayload({
    required this.callId,
    required this.callUuid,
    required this.conversationId,
    required this.callerId,
    required this.callerName,
    required this.callerAvatar,
    required this.callType,
    required this.isGroupCall,
    this.conversationName = '',
    this.conversationAvatar = '',
  });

  bool get isVideo =>
      callType == CallType.video;

  bool get isAudio =>
      callType == CallType.audio;

  bool get isValid =>
      callId > 0 &&
      conversationId > 0 &&
      callerId > 0;

  factory IncomingCallPayload.fromMap(
    Map<String, dynamic> map,
  ) {
    final video = _asBool(
      map['is_video_call'] ??
          map['isVideoCall'] ??
          map['video'],
    );

    final group = _asBool(
      map['is_group_call'] ??
          map['isGroupCall'],
    );

    return IncomingCallPayload(
      callId:
          _asInt(map['call_id']) ??
          _asInt(map['callId']) ??
          _asInt(map['id']) ??
          0,

      callUuid:
          _firstString([
        map['call_uuid'],
        map['callUuid'],
        map['uuid'],
      ]),

      conversationId:
          _asInt(
            map['conversation_id'],
          ) ??
          _asInt(
            map['conversationId'],
          ) ??
          0,

      callerId:
          _asInt(
            map['caller_id'],
          ) ??
          _asInt(
            map['callerId'],
          ) ??
          _asInt(
            map['from_user'],
          ) ??
          _asInt(
            map['from'],
          ) ??
          0,

      callerName:
          _firstString(
        [
          map['caller_name'],
          map['callerName'],
          map['nameCaller'],
          map['name'],
        ],
        fallback: 'Unknown',
      ),

      callerAvatar:
          _firstString([
        map['caller_avatar'],
        map['callerAvatar'],
        map['avatar'],
        map['profile_picture'],
      ]),

      callType:
          CallType.fromJson(
        map['call_type'] ??
            map['callType'] ??
            (video
                ? 'video'
                : 'audio'),
      ),

      isGroupCall: group,

      conversationName:
          _firstString([
        map['conversation_name'],
        map['conversationName'],
        map['group_name'],
        map['groupName'],
      ]),

      conversationAvatar:
          _firstString([
        map['conversation_avatar'],
        map['conversationAvatar'],
        map['group_avatar'],
        map['groupAvatar'],
      ]),
    );
  }

  factory IncomingCallPayload.fromJson(
    Map<String, dynamic> json,
  ) {
    return IncomingCallPayload.fromMap(
      json,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': 'incoming_call',

      'call_id': callId,
      'call_uuid': callUuid,

      'conversation_id':
          conversationId,

      'caller_id': callerId,
      'caller_name': callerName,
      'caller_avatar':
          callerAvatar,

      'call_type':
          callType.name,

      'is_video_call':
          isVideo,

      'is_group_call':
          isGroupCall,

      'conversation_name':
          conversationName,

      'conversation_avatar':
          conversationAvatar,
    };
  }

  Map<String, dynamic> toJson() {
    return toMap();
  }

  @override
  String toString() {
    return 'IncomingCallPayload('
        'callId: $callId, '
        'callUuid: $callUuid, '
        'conversationId: $conversationId, '
        'callerId: $callerId, '
        'callerName: $callerName, '
        'callType: ${callType.name}, '
        'isGroupCall: $isGroupCall, '
        'conversationName: $conversationName'
        ')';
  }
}

// ============================================================
// HELPERS
// ============================================================

int? _asInt(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  final raw =
      value.toString().trim();

  if (raw.isEmpty ||
      raw.toLowerCase() == 'null') {
    return null;
  }

  return int.tryParse(raw);
}

bool _asBool(Object? value) {
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
      value
          .toString()
          .trim()
          .toLowerCase();

  return raw == 'true' ||
      raw == '1' ||
      raw == 'yes' ||
      raw == 'y';
}

DateTime? _asDate(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is DateTime) {
    return value;
  }

  final raw =
      value.toString().trim();

  if (raw.isEmpty ||
      raw.toLowerCase() == 'null') {
    return null;
  }

  return DateTime.tryParse(
    raw,
  );
}

String _firstString(
  List<Object?> values, {
  String fallback = '',
}) {
  for (final value in values) {
    if (value == null) {
      continue;
    }

    final text =
        value.toString().trim();

    if (text.isNotEmpty &&
        text.toLowerCase() != 'null') {
      return text;
    }
  }

  return fallback;
}