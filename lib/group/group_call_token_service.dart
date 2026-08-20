// lib/group/group_call_token_service.dart

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddenly/core/api_client.dart';

class GroupCallTokenResponse {
  final String url;
  final String token;
  final String roomName;

  const GroupCallTokenResponse({
    required this.url,
    required this.token,
    required this.roomName,
  });

  factory GroupCallTokenResponse.fromJson(
    Map<String, dynamic> json, {
    required String fallbackRoomName,
  }) {
    final nestedRaw = json['data'];
    final nested = nestedRaw is Map
        ? Map<String, dynamic>.from(nestedRaw)
        : <String, dynamic>{};

    String read(List<String> keys) {
      for (final key in keys) {
        final direct = json[key];
        if (direct != null && direct.toString().trim().isNotEmpty) {
          return direct.toString().trim();
        }

        final inner = nested[key];
        if (inner != null && inner.toString().trim().isNotEmpty) {
          return inner.toString().trim();
        }
      }

      return '';
    }

    final url = read(const [
      'url',
      'server_url',
      'serverUrl',
      'livekit_url',
      'livekitUrl',
      'ws_url',
      'wsUrl',
    ]);

    final token = read(const [
      'token',
      'access_token',
      'accessToken',
      'participant_token',
      'participantToken',
    ]);

    final roomName = read(const [
      'room_name',
      'roomName',
      'room',
    ]);

    if (url.isEmpty) {
      throw const FormatException(
        'Group-call token response does not contain a LiveKit server URL.',
      );
    }

    if (token.isEmpty) {
      throw const FormatException(
        'Group-call token response does not contain a LiveKit token.',
      );
    }

    return GroupCallTokenResponse(
      url: url,
      token: token,
      roomName: roomName.isEmpty ? fallbackRoomName : roomName,
    );
  }
}

class GroupCallTokenService {
  GroupCallTokenService._();

  /*
    Change this build variable only when your backend route is different:

    flutter run --dart-define="GROUP_CALL_TOKEN_ENDPOINT=/chat/group-call/token/"

    The default endpoint below is used when no dart-define is supplied.
  */
  static const String endpoint = String.fromEnvironment(
    'GROUP_CALL_TOKEN_ENDPOINT',
    defaultValue: '/chat/group-call/token/',
  );

  static Future<GroupCallTokenResponse> getToken({
    required String userId,
    required String userName,
    required String roomName,
  }) async {
    final cleanUserId = userId.trim();
    final cleanUserName =
        userName.trim().isEmpty ? 'User' : userName.trim();
    final cleanRoomName = roomName.trim();

    if (cleanUserId.isEmpty) {
      throw ArgumentError('userId cannot be empty');
    }

    if (cleanRoomName.isEmpty) {
      throw ArgumentError('roomName cannot be empty');
    }

    try {
      final Response<dynamic> response = await ApiClient.dio.post(
        endpoint,
        data: <String, dynamic>{
          'user_id': cleanUserId,
          'userId': cleanUserId,
          'user_name': cleanUserName,
          'userName': cleanUserName,
          'room_name': cleanRoomName,
          'roomName': cleanRoomName,
          'conversation_id': cleanRoomName,
          'conversationId': cleanRoomName,
        },
      );

      final raw = response.data;

      if (raw is! Map) {
        throw const FormatException(
          'Invalid group-call token response.',
        );
      }

      return GroupCallTokenResponse.fromJson(
        Map<String, dynamic>.from(raw),
        fallbackRoomName: cleanRoomName,
      );
    } on DioException catch (error, stackTrace) {
      debugPrint(
        'GROUP CALL TOKEN ERROR: '
        '${error.response?.statusCode} ${error.response?.data}',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }
}
