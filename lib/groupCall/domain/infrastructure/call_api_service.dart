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
    final data =
        error.response?.data;

    String message =
        'Call request failed';

    if (data is Map) {
      message =
          (data['error'] ??
                  data['detail'] ??
                  data['message'] ??
                  message)
              .toString();
    } else if (data != null) {
      message = data.toString();
    } else if (error.message != null) {
      message = error.message!;
    }

    return CallApiException(
      statusCode:
          error.response?.statusCode,
      message: message,
      data: data,
    );
  }

  @override
  String toString() {
    return 'CallApiException('
        '$statusCode): $message';
  }
}

class CallApiService {
  final Dio dio;

  CallApiService({
    Dio? dio,
  }) : dio = dio ?? ApiClient.dio;

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
      message:
          'Invalid response from $endpoint',
      data: value,
    );
  }

  Future<CallSessionDto> startGroupCall({
    required int conversationId,
    required bool isVideo,
  }) async {
    try {
      final response = await dio.post(
        '/chat/calls/start/',
        data: {
          'conversation_id':
              conversationId,
          'is_video_call': isVideo,
        },
      );

      final raw = _requireMap(
        response.data,
        '/chat/calls/start/',
      );

      /*
       * Some backend serializers may not include
       * these values in the start response.
       */
      final normalized =
          <String, dynamic>{
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
      };

      final call =
          CallSessionDto.fromJson(
        normalized,
      );

      if (call.callId <= 0) {
        throw CallApiException(
          statusCode:
              response.statusCode,
          message:
              'Backend did not return a valid call_id.',
          data: response.data,
        );
      }

      return call;
    } on CallApiException {
      rethrow;
    } on DioException catch (e) {
      throw CallApiException.fromDio(e);
    }
  }

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

      final raw = _requireMap(
        response.data,
        '/chat/calls/livekit-token/',
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
          statusCode:
              response.statusCode,
          message:
              'LiveKit server URL or token is missing.',
          data: response.data,
        );
      }

      return credentials;
    } on CallApiException {
      rethrow;
    } on DioException catch (e) {
      throw CallApiException.fromDio(e);
    }
  }

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

    try {
      final response = await dio.post(
        '/chat/calls/$callId/status/',
        data: {
          'action': action,
        },
      );

      if (response.data == null) {
        return <String, dynamic>{};
      }

      if (response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      return <String, dynamic>{};
    } on DioException catch (e) {
      throw CallApiException.fromDio(e);
    }
  }

  Future<ActiveCallResult>
      getActiveGroupCall(
    int conversationId,
  ) async {
    if (conversationId <= 0) {
      throw const CallApiException(
        statusCode: null,
        message:
            'Invalid conversation ID.',
      );
    }

    try {
      final response = await dio.get(
        '/chat/conversations/'
        '$conversationId/active-call/',
      );

      final raw = _requireMap(
        response.data,
        '/chat/conversations/'
        '$conversationId/active-call/',
      );

      return ActiveCallResult.fromJson(
        raw,
      );
    } on CallApiException {
      rethrow;
    } on DioException catch (e) {
      throw CallApiException.fromDio(e);
    }
  }
}