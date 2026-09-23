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

  factory CallApiException.fromDio(
    DioException error,
  ) {
    final data = error.response?.data;

    String message = 'Call request failed';

    if (data is Map) {
      final candidate =
          data['error'] ??
          data['detail'] ??
          data['message'] ??
          data['non_field_errors'];

      if (candidate is List &&
          candidate.isNotEmpty) {
        message = candidate.first.toString();
      } else if (candidate != null) {
        message = candidate.toString();
      }
    } else if (data is String &&
        data.trim().isNotEmpty) {
      message = data.trim();
    } else if (error.message != null &&
        error.message!.trim().isNotEmpty) {
      message = error.message!.trim();
    }

    return CallApiException(
      statusCode: error.response?.statusCode,
      message: message,
      data: data,
    );
  }

  @override
  String toString() {
    if (statusCode == null) {
      return message;
    }

    return 'CallApiException($statusCode): $message';
  }
}

class CallApiService {
  final Dio dio;

  CallApiService({
    Dio? dio,
  }) : dio = dio ?? ApiClient.dio;

  // ============================================================
  // RESPONSE MAP
  // ============================================================

  Map<String, dynamic> _requireMap(
    dynamic value,
    String endpoint,
  ) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    throw CallApiException(
      statusCode: null,
      message: 'Invalid response from $endpoint',
      data: value,
    );
  }

  // ============================================================
  // UNWRAP OPTIONAL NESTED RESPONSE
  // ============================================================

  Map<String, dynamic> _unwrapMap(
    dynamic value,
    String endpoint, {
    List<String> keys = const [],
  }) {
    final raw = _requireMap(
      value,
      endpoint,
    );

    for (final key in keys) {
      final nested = raw[key];

      if (nested is Map) {
        return Map<String, dynamic>.from(
          nested,
        );
      }
    }

    return raw;
  }

  // ============================================================
  // START GROUP CALL
  // ============================================================

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

    try {
      final response = await dio.post(
        '/chat/calls/start/',
        data: {
          'conversation_id': conversationId,
          'is_video_call': isVideo,
        },
      );

      final raw = _unwrapMap(
        response.data,
        '/chat/calls/start/',
        keys: const [
          'call',
          'data',
        ],
      );

      final normalized = <String, dynamic>{
        ...raw,

        'conversation_id':
            raw['conversation_id'] ??
            conversationId,

        'conversation_type':
            raw['conversation_type'] ??
            'group',

        'is_group_call':
            raw['is_group_call'] ??
            true,

        'is_video_call':
            raw['is_video_call'] ??
            isVideo,
      };

      final call =
          CallSessionDto.fromJson(
        normalized,
      );

      if (call.callId <= 0) {
        throw CallApiException(
          statusCode: response.statusCode,
          message:
              'Backend did not return a valid call_id.',
          data: response.data,
        );
      }

      return call;
    } on CallApiException {
      rethrow;
    } on DioException catch (error) {
      throw CallApiException.fromDio(
        error,
      );
    }
  }

  // ============================================================
  // LIVEKIT TOKEN
  // ============================================================

  Future<LiveKitCredentials>
      getLiveKitToken(
    int callId,
  ) async {
    if (callId <= 0) {
      throw const CallApiException(
        statusCode: null,
        message: 'Invalid call ID.',
      );
    }

    try {
      final response = await dio.post(
        '/chat/calls/livekit-token/',
        data: {
          'call_id': callId,
        },
      );

      final raw = _unwrapMap(
        response.data,
        '/chat/calls/livekit-token/',
        keys: const [
          'credentials',
          'livekit',
          'data',
        ],
      );

      final credentials =
          LiveKitCredentials.fromJson(
        raw,
      );

      if (credentials.serverUrl
              .trim()
              .isEmpty ||
          credentials.participantToken
              .trim()
              .isEmpty) {
        throw CallApiException(
          statusCode: response.statusCode,
          message:
              'LiveKit server URL or participant token is missing.',
          data: response.data,
        );
      }

      return credentials;
    } on CallApiException {
      rethrow;
    } on DioException catch (error) {
      throw CallApiException.fromDio(
        error,
      );
    }
  }

  // ============================================================
  // UPDATE CALL STATUS
  // ============================================================

  Future<Map<String, dynamic>>
      updateStatus({
    required int callId,
    required String action,
  }) async {
    if (callId <= 0) {
      throw const CallApiException(
        statusCode: null,
        message: 'Invalid call ID.',
      );
    }

    final cleanAction =
        action.trim();

    if (cleanAction.isEmpty) {
      throw const CallApiException(
        statusCode: null,
        message:
            'Call status action cannot be empty.',
      );
    }

    try {
      final response = await dio.post(
        '/chat/calls/$callId/status/',
        data: {
          'action': cleanAction,
        },
      );

      if (response.data == null) {
        return <String, dynamic>{};
      }

      if (response.data is Map) {
        final raw =
            Map<String, dynamic>.from(
          response.data as Map,
        );

        final nested =
            raw['call'] ??
            raw['data'];

        if (nested is Map) {
          return Map<String, dynamic>.from(
            nested,
          );
        }

        return raw;
      }

      return <String, dynamic>{};
    } on DioException catch (error) {
      throw CallApiException.fromDio(
        error,
      );
    }
  }

  // ============================================================
  // GET ACTIVE GROUP CALL
  // ============================================================

  Future<ActiveCallResult>
      getActiveGroupCall(
    int conversationId,
  ) async {
    if (conversationId <= 0) {
      throw const CallApiException(
        statusCode: null,
        message: 'Invalid conversation ID.',
      );
    }

    try {
      final response = await dio.get(
        '/chat/conversations/'
        '$conversationId/active-call/',
      );

      final raw = _unwrapMap(
        response.data,
        '/chat/conversations/'
        '$conversationId/active-call/',
        keys: const [
          'data',
        ],
      );

      return ActiveCallResult.fromJson(
        raw,
      );
    } on CallApiException {
      rethrow;
    } on DioException catch (error) {
      throw CallApiException.fromDio(
        error,
      );
    }
  }
}