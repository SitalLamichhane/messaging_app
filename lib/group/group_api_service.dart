import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/group/group_models.dart';

class GroupApiService {
  GroupApiService._();

  static Dio get _dio => ApiClient.dio;

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw const FormatException('Expected JSON object from group API.');
  }

  static Future<GroupDetails> createGroup({
    required String subject,
    required List<String> memberIds,
    String description = '',
    File? image,
  }) async {
    final cleanIds = memberIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    if (subject.trim().isEmpty) {
      throw ArgumentError('Group subject cannot be empty.');
    }

    if (cleanIds.isEmpty) {
      throw ArgumentError('Select at least one participant.');
    }

    dynamic data;
    Options? options;

    if (image != null) {
      data = FormData.fromMap({
        'subject': subject.trim(),
        'description': description.trim(),
        // Send comma-separated IDs for predictable multipart parsing.
        'member_ids': cleanIds.join(','),
        'image': await MultipartFile.fromFile(
          image.path,
          filename: image.path.split(Platform.pathSeparator).last,
        ),
      });
      options = Options(contentType: 'multipart/form-data');
    } else {
      data = {
        'subject': subject.trim(),
        'description': description.trim(),
        'member_ids': cleanIds,
      };
    }

    final response = await _dio.post(
      '/chat/groups/',
      data: data,
      options: options,
    );

    final map = _asMap(response.data);
    final groupRaw = map['group'];
    return GroupDetails.fromJson(
      groupRaw is Map ? Map<String, dynamic>.from(groupRaw) : map,
    );
  }

  static Future<GroupDetails> getGroup(String conversationId) async {
    final response = await _dio.get('/chat/groups/$conversationId/');
    final map = _asMap(response.data);
    final groupRaw = map['group'];
    return GroupDetails.fromJson(
      groupRaw is Map ? Map<String, dynamic>.from(groupRaw) : map,
    );
  }

  static Future<GroupDetails> updateGroup({
    required String conversationId,
    String? subject,
    String? description,
    File? image,
  }) async {
    final payload = <String, dynamic>{};
    if (subject != null) payload['subject'] = subject.trim();
    if (description != null) payload['description'] = description.trim();

    dynamic data = payload;
    Options? options;

    if (image != null) {
      data = FormData.fromMap({
        ...payload,
        'image': await MultipartFile.fromFile(
          image.path,
          filename: image.path.split(Platform.pathSeparator).last,
        ),
      });
      options = Options(contentType: 'multipart/form-data');
    }

    final response = await _dio.patch(
      '/chat/groups/$conversationId/',
      data: data,
      options: options,
    );

    final map = _asMap(response.data);
    final groupRaw = map['group'];
    return GroupDetails.fromJson(
      groupRaw is Map ? Map<String, dynamic>.from(groupRaw) : map,
    );
  }

  static Future<List<GroupMember>> searchUsers(String query) async {
    final response = await _dio.get(
      '/chat/group-users/',
      queryParameters: {'q': query.trim()},
    );

    final raw = response.data;
    final items = raw is List
        ? raw
        : raw is Map && raw['results'] is List
            ? raw['results'] as List
            : const [];

    return items
        .whereType<Map>()
        .map((e) => GroupMember.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<GroupDetails> addMembers({
    required String conversationId,
    required List<String> userIds,
  }) async {
    final response = await _dio.post(
      '/chat/groups/$conversationId/add-members/',
      data: {'user_ids': userIds},
    );
    final map = _asMap(response.data);
    return GroupDetails.fromJson(
      map['group'] is Map
          ? Map<String, dynamic>.from(map['group'])
          : map,
    );
  }

  static Future<GroupDetails> removeMember({
    required String conversationId,
    required String userId,
  }) async {
    final response = await _dio.post(
      '/chat/groups/$conversationId/remove-member/',
      data: {'user_id': userId},
    );
    final map = _asMap(response.data);
    return GroupDetails.fromJson(
      map['group'] is Map
          ? Map<String, dynamic>.from(map['group'])
          : map,
    );
  }

  static Future<GroupDetails> setAdmin({
    required String conversationId,
    required String userId,
    required bool makeAdmin,
  }) async {
    final response = await _dio.post(
      '/chat/groups/$conversationId/${makeAdmin ? 'make-admin' : 'dismiss-admin'}/',
      data: {'user_id': userId},
    );
    final map = _asMap(response.data);
    return GroupDetails.fromJson(
      map['group'] is Map
          ? Map<String, dynamic>.from(map['group'])
          : map,
    );
  }

  static Future<GroupDetails> updatePermissions({
    required String conversationId,
    required GroupPermissions permissions,
  }) async {
    final response = await _dio.patch(
      '/chat/groups/$conversationId/permissions/',
      data: permissions.toJson(),
    );
    final map = _asMap(response.data);
    return GroupDetails.fromJson(
      map['group'] is Map
          ? Map<String, dynamic>.from(map['group'])
          : map,
    );
  }

  /// Blocking is an account/direct-interaction action. It does not remove the
  /// person from a shared group. Group messages can still be visible because
  /// both users remain participants in the same group.
  static Future<void> blockMember(String userId) async {
    await _dio.post('/chat/blocks/', data: {'user_id': userId});
  }

  static Future<void> unblockMember(String userId) async {
    await _dio.delete('/chat/blocks/$userId/');
  }

  static Future<void> exitGroup(String conversationId) async {
    await _dio.post('/chat/groups/$conversationId/exit/');
  }

  static Future<void> deleteGroupForMe(String conversationId) async {
    await _dio.delete('/chat/groups/$conversationId/delete-for-me/');
  }

  static Future<String> resetInviteLink(String conversationId) async {
    final response = await _dio.post(
      '/chat/groups/$conversationId/reset-invite-link/',
    );
    final map = _asMap(response.data);
    return (map['invite_code'] ?? '').toString();
  }

  static Future<GroupCallJoinCredentials> startCall({
    required String conversationId,
    required bool video,
  }) async {
    final response = await _dio.post(
      '/chat/groups/$conversationId/calls/start/',
      data: {'call_type': video ? 'video' : 'audio'},
    );
    return GroupCallJoinCredentials.fromJson(_asMap(response.data));
  }

  static Future<GroupCallSessionInfo?> getActiveCall(
    String conversationId,
  ) async {
    try {
      final response = await _dio.get(
        '/chat/groups/$conversationId/calls/active/',
      );
      final map = _asMap(response.data);
      final callRaw = map['call'];
      if (callRaw == null) return null;
      return GroupCallSessionInfo.fromJson(
        callRaw is Map ? Map<String, dynamic>.from(callRaw) : map,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  static Future<GroupCallJoinCredentials> joinCall(String callId) async {
    final response = await _dio.post('/chat/group-calls/$callId/join/');
    return GroupCallJoinCredentials.fromJson(_asMap(response.data));
  }

  static Future<void> declineCall(String callId) async {
    await _dio.post('/chat/group-calls/$callId/decline/');
  }

  static Future<void> leaveCall(String callId) async {
    await _dio.post('/chat/group-calls/$callId/leave/');
  }

  static Future<void> ringMembers({
    required String callId,
    required List<String> userIds,
  }) async {
    await _dio.post(
      '/chat/group-calls/$callId/ring/',
      data: {'user_ids': userIds},
    );
  }
}
