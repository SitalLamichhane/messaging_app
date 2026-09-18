import 'package:flutter/foundation.dart';

enum GroupRole { admin, member }

enum GroupCallType { audio, video }

enum GroupCallParticipantState { invited, ringing, joined, declined, left }

@immutable
class GroupMember {
  final String id;
  final String name;
  final String phone;
  final String avatarUrl;
  final GroupRole role;
  final bool isBlockedByMe;
  final bool hasBlockedMe;
  final bool isCurrentUser;

  const GroupMember({
    required this.id,
    required this.name,
    required this.phone,
    required this.avatarUrl,
    required this.role,
    required this.isBlockedByMe,
    required this.hasBlockedMe,
    required this.isCurrentUser,
  });

  bool get isAdmin => role == GroupRole.admin;

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final roleRaw = (json['role'] ?? json['group_role'] ?? 'member')
        .toString()
        .toLowerCase();

    return GroupMember(
      id: (json['id'] ?? json['user_id'] ?? json['userId'] ?? '').toString(),
      name: (json['name'] ?? json['full_name'] ?? json['display_name'] ?? 'User')
          .toString(),
      phone: (json['phone'] ?? json['phone_number'] ?? '').toString(),
      avatarUrl: (json['avatar_url'] ??
              json['avatarUrl'] ??
              json['profile_picture'] ??
              '')
          .toString(),
      role: roleRaw == 'admin' ? GroupRole.admin : GroupRole.member,
      isBlockedByMe: json['is_blocked_by_me'] == true ||
          json['blocked_by_me'] == true,
      hasBlockedMe:
          json['has_blocked_me'] == true || json['blocked_me'] == true,
      isCurrentUser: json['is_current_user'] == true,
    );
  }
}

@immutable
class GroupPermissions {
  final bool onlyAdminsCanEditInfo;
  final bool onlyAdminsCanSendMessages;
  final bool onlyAdminsCanAddMembers;

  const GroupPermissions({
    this.onlyAdminsCanEditInfo = false,
    this.onlyAdminsCanSendMessages = false,
    this.onlyAdminsCanAddMembers = true,
  });

  factory GroupPermissions.fromJson(Map<String, dynamic> json) {
    return GroupPermissions(
      onlyAdminsCanEditInfo: json['only_admins_can_edit_info'] == true,
      onlyAdminsCanSendMessages: json['only_admins_can_send_messages'] == true,
      onlyAdminsCanAddMembers:
          json['only_admins_can_add_members'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'only_admins_can_edit_info': onlyAdminsCanEditInfo,
        'only_admins_can_send_messages': onlyAdminsCanSendMessages,
        'only_admins_can_add_members': onlyAdminsCanAddMembers,
      };
}

@immutable
class GroupDetails {
  final String conversationId;
  final String subject;
  final String description;
  final String imageUrl;
  final String createdById;
  final String createdAt;
  final List<GroupMember> members;
  final GroupPermissions permissions;
  final bool isCurrentUserAdmin;
  final bool isCurrentUserMember;
  final String inviteCode;

  const GroupDetails({
    required this.conversationId,
    required this.subject,
    required this.description,
    required this.imageUrl,
    required this.createdById,
    required this.createdAt,
    required this.members,
    required this.permissions,
    required this.isCurrentUserAdmin,
    required this.isCurrentUserMember,
    required this.inviteCode,
  });

  factory GroupDetails.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'];
    final rawPermissions = json['permissions'];

    return GroupDetails(
      conversationId:
          (json['conversation_id'] ?? json['id'] ?? json['conversationId'] ?? '')
              .toString(),
      subject: (json['subject'] ?? json['name'] ?? 'Group').toString(),
      description: (json['description'] ?? '').toString(),
      imageUrl: (json['image_url'] ?? json['image'] ?? json['avatar_url'] ?? '')
          .toString(),
      createdById:
          (json['created_by_id'] ?? json['createdById'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      members: rawMembers is List
          ? rawMembers
              .whereType<Map>()
              .map((e) => GroupMember.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      permissions: rawPermissions is Map
          ? GroupPermissions.fromJson(
              Map<String, dynamic>.from(rawPermissions),
            )
          : const GroupPermissions(),
      isCurrentUserAdmin: json['is_current_user_admin'] == true,
      isCurrentUserMember: json['is_current_user_member'] != false,
      inviteCode: (json['invite_code'] ?? '').toString(),
    );
  }
}

@immutable
class GroupCallSessionInfo {
  final String callId;
  final String conversationId;
  final String roomName;
  final GroupCallType type;
  final String status;
  final String startedById;
  final String startedByName;
  final List<GroupMember> joinedMembers;

  const GroupCallSessionInfo({
    required this.callId,
    required this.conversationId,
    required this.roomName,
    required this.type,
    required this.status,
    required this.startedById,
    required this.startedByName,
    required this.joinedMembers,
  });

  bool get isVideo => type == GroupCallType.video;
  bool get isActive => status == 'active' || status == 'ringing';

  factory GroupCallSessionInfo.fromJson(Map<String, dynamic> json) {
    final rawJoined = json['joined_members'];
    final typeRaw = (json['call_type'] ?? json['type'] ?? 'audio')
        .toString()
        .toLowerCase();

    return GroupCallSessionInfo(
      callId: (json['call_id'] ?? json['id'] ?? '').toString(),
      conversationId:
          (json['conversation_id'] ?? json['conversationId'] ?? '').toString(),
      roomName: (json['room_name'] ?? json['roomName'] ?? '').toString(),
      type: typeRaw == 'video' ? GroupCallType.video : GroupCallType.audio,
      status: (json['status'] ?? 'active').toString(),
      startedById:
          (json['started_by_id'] ?? json['startedById'] ?? '').toString(),
      startedByName:
          (json['started_by_name'] ?? json['startedByName'] ?? 'User')
              .toString(),
      joinedMembers: rawJoined is List
          ? rawJoined
              .whereType<Map>()
              .map((e) => GroupMember.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

@immutable
class GroupCallJoinCredentials {
  final GroupCallSessionInfo call;
  final String url;
  final String token;

  const GroupCallJoinCredentials({
    required this.call,
    required this.url,
    required this.token,
  });

  factory GroupCallJoinCredentials.fromJson(Map<String, dynamic> json) {
    final callRaw = json['call'];
    return GroupCallJoinCredentials(
      call: GroupCallSessionInfo.fromJson(
        callRaw is Map
            ? Map<String, dynamic>.from(callRaw)
            : Map<String, dynamic>.from(json),
      ),
      url: (json['url'] ?? json['server_url'] ?? json['livekit_url'] ?? '')
          .toString(),
      token: (json['token'] ?? json['access_token'] ?? '').toString(),
    );
  }
}
