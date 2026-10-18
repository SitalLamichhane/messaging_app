import 'package:dio/dio.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/groupCall/domain/call_models.dart';

class CallApiException implements Exception {
  final int? statusCode;
  final String message;
  final Object? data;

  const CallApiException({
    required this.statusCode,
    required this.message,
    this.data,
  });

  String? get code {
    final value = data;
    if (value is Map) {
      return value['code']?.toString();
    }
    return null;
  }

  bool get isUserBusy => statusCode == 409 && code == 'USER_BUSY';

  // The existing call ID is returned only for same-conversation conflicts.
  bool get isExistingConversationCall {
    if (statusCode != 409 || isUserBusy) return false;
    if (data is! Map) return false;
    final body = data as Map;
    return (body['call_id'] ?? body['id']) != null;
  }

  factory CallApiException.fromDio(DioException error) {
    final body = error.response?.data;
    String message = 'Call request failed';
    if (body is Map) {
      final candidate = body['error'] ?? body['detail'] ??
          body['message'] ?? body['non_field_errors'];
      if (candidate is List && candidate.isNotEmpty) {
        message = candidate.first.toString();
      } else if (candidate != null) {
        message = candidate.toString();
      }
    } else if (body is String && body.trim().isNotEmpty) {
      message = body.trim();
    } else if (error.message?.trim().isNotEmpty == true) {
      message = error.message!.trim();
    }
    return CallApiException(
      statusCode: error.response?.statusCode,
      message: message,
      data: body,
    );
  }

  @override
  String toString() => statusCode == null
      ? message
      : 'CallApiException($statusCode): $message';
}

class CallApiService {
  final Dio dio;

  CallApiService({Dio? dio}) : dio = dio ?? ApiClient.dio;

  Map<String, dynamic> _requireMap(dynamic value, String endpoint) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw CallApiException(
      statusCode: null,
      message: 'Invalid response from $endpoint',
      data: value,
    );
  }

  Map<String, dynamic> _unwrapMap(
    dynamic value,
    String endpoint, {
    List<String> keys = const [],
  }) {
    final raw = _requireMap(value, endpoint);
    for (final key in keys) {
      final nested = raw[key];
      if (nested is Map) return Map<String, dynamic>.from(nested);
    }
    return raw;
  }

  Future<CallSessionDto> startGroupCall({
    required int conversationId,
    required bool isVideo,
  }) async {
    if (conversationId <= 0) {
      throw const CallApiException(
        statusCode: null,
        message: 'Invalid conversation ID.',
      );
    }
    const endpoint = '/chat/calls/start/';
    try {
      final response = await dio.post(
        endpoint,
        data: {
          'conversation_id': conversationId,
          'is_video_call': isVideo,
        },
      );
      final raw = _unwrapMap(
        response.data,
        endpoint,
        keys: const ['call', 'data'],
      );
      final normalized = <String, dynamic>{
        ...raw,
        'conversation_id': raw['conversation_id'] ?? conversationId,
        'conversation_type': raw['conversation_type'] ?? 'group',
        'is_group_call': raw['is_group_call'] ?? true,
        'is_video_call': raw['is_video_call'] ?? isVideo,
      };
      final call = CallSessionDto.fromJson(normalized);
      if (call.callId <= 0) {
        throw CallApiException(
          statusCode: response.statusCode,
          message: 'Backend did not return a valid call_id.',
          data: response.data,
        );
      }
      return call;
    } on CallApiException {
      rethrow;
    } on DioException catch (error) {
      throw CallApiException.fromDio(error);
    }
  }

  Future<LiveKitCredentials> getLiveKitToken(int callId) async {
    if (callId <= 0) {
      throw const CallApiException(
        statusCode: null,
        message: 'Invalid call ID.',
      );
    }
    const endpoint = '/chat/calls/livekit-token/';
    try {
      final response = await dio.post(
        endpoint,
        data: {'call_id': callId},
      );
      final raw = _unwrapMap(
        response.data,
        endpoint,
        keys: const ['credentials', 'livekit', 'data'],
      );
      final credentials = LiveKitCredentials.fromJson(raw);
      if (credentials.serverUrl.trim().isEmpty ||
          credentials.participantToken.trim().isEmpty) {
        throw CallApiException(
          statusCode: response.statusCode,
          message: 'LiveKit server URL or participant token is missing.',
          data: response.data,
        );
      }
      return credentials;
    } on CallApiException {
      rethrow;
    } on DioException catch (error) {
      throw CallApiException.fromDio(error);
    }
  }

  Future<Map<String, dynamic>> updateStatus({
    required int callId,
    required String action,
  }) async {
    if (callId <= 0 || action.trim().isEmpty) {
      throw const CallApiException(
        statusCode: null,
        message: 'Valid call ID and action are required.',
      );
    }
    try {
      final response = await dio.post(
        '/chat/calls/$callId/status/',
        data: {'action': action.trim()},
      );
      if (response.data == null) return <String, dynamic>{};
      final raw = _requireMap(response.data, 'call status');
      final nested = raw['call'] ?? raw['data'];
      if (nested is Map) return Map<String, dynamic>.from(nested);
      return raw;
    } on CallApiException {
      rethrow;
    } on DioException catch (error) {
      throw CallApiException.fromDio(error);
    }
  }

  Future<ActiveCallResult> getActiveGroupCall(int conversationId) async {
    if (conversationId <= 0) {
      throw const CallApiException(
        statusCode: null,
        message: 'Invalid conversation ID.',
      );
    }
    final endpoint = '/chat/conversations/$conversationId/active-call/';
    try {
      final response = await dio.get(endpoint);
      final raw = _unwrapMap(
        response.data,
        endpoint,
        keys: const ['data'],
      );
      return ActiveCallResult.fromJson(raw);
    } on CallApiException {
      rethrow;
    } on DioException catch (error) {
      throw CallApiException.fromDio(error);
    }
  }
}
